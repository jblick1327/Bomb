[CmdletBinding()]
param(
 [string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json'),
 [ValidateSet('Mono','IL2CPP','Both')][string]$Backend='Both',
 [string]$SourceProject='', [string]$OutputRoot=''
)
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
if(!$SourceProject){$SourceProject=Split-Path -Parent $integration}
$source=[IO.Path]::GetFullPath($SourceProject).TrimEnd('\','/')
$validation=[IO.Path]::GetFullPath($config.UnityValidationProject).TrimEnd('\','/')
if($source -eq $validation){throw 'Use a separate validation copy so build settings do not modify the source project.'}
if(!(Test-Path -LiteralPath (Join-Path $source 'Assets/BOMIntegration/Runtime/BomClientBehaviour.cs'))){throw 'SourceProject must contain the completed Assets/BOMIntegration SDK.'}
$open=Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'"|Where-Object {$_.CommandLine -and $_.CommandLine.Contains($validation)}
if($open){throw 'Close the dedicated validation Editor before rebuilding its plugin.'}
if(!(Test-Path -LiteralPath (Join-Path $validation 'ProjectSettings/ProjectVersion.txt'))){
 New-Item -ItemType Directory -Path $validation -Force|Out-Null
 foreach($folder in @('Assets','Packages','ProjectSettings')){Copy-Item -LiteralPath (Join-Path $source $folder) -Destination (Join-Path $validation $folder) -Recurse -Force}
}
$version=Get-Content -LiteralPath (Join-Path $validation 'ProjectSettings/ProjectVersion.txt') -Raw
if($version -notmatch '6000\.2\.14f1'){throw 'The validation copy must use the pinned Unity 6000.2.14f1 Editor.'}
$assets=Join-Path $validation 'Assets/BOMIntegration'
New-Item -ItemType Directory -Path $assets -Force|Out-Null
Copy-Item -Path (Join-Path $source 'Assets/BOMIntegration/*') -Destination $assets -Recurse -Force
Copy-Item -LiteralPath (Join-Path $config.OdinRoot 'build/bomcore.dll') -Destination (Join-Path $assets 'Plugins/x86_64/bomcore.dll') -Force
Copy-Item -LiteralPath (Join-Path $config.OdinRoot 'bindings/BomNative.cs') -Destination (Join-Path $assets 'Runtime/BomNative.cs') -Force
if(!$OutputRoot){$OutputRoot=Join-Path $integration 'build/validation'}
$kinds=if($Backend -eq 'Both'){@('Mono','IL2CPP')}else{@($Backend)}
$oldServer=$env:BOM_NATIVE_SERVER_EXE;$oldOutput=$env:BOM_PERFORMANCE_PLAYER_OUT
try{
 $env:BOM_NATIVE_SERVER_EXE=Join-Path $config.OdinRoot 'build/BOM-server.exe'
 foreach($kind in $kinds){
  $output=Join-Path $OutputRoot $kind;New-Item -ItemType Directory -Path $output -Force|Out-Null
  $env:BOM_PERFORMANCE_PLAYER_OUT=$output
  $method=if($kind -eq 'Mono'){'BomPerformanceBuilder.RebuildMono'}else{'BomPerformanceBuilder.RebuildIl2Cpp'}
  $log=Join-Path $output ('editor-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'.log')
  $process=Start-Process -FilePath $config.UnityEditor -ArgumentList @('-batchmode','-quit','-projectPath',('"'+$validation+'"'),'-executeMethod',$method,'-logFile',('"'+$log+'"')) -WindowStyle Hidden -PassThru -Wait
  if($process.ExitCode -ne 0){throw "$kind build failed; see $log"}
  $plugin=Join-Path $output 'BombPerformance_Data/Plugins/x86_64/bomcore.dll'
  if((Get-FileHash -LiteralPath $plugin).Hash -ne (Get-FileHash -LiteralPath (Join-Path $config.OdinRoot 'build/bomcore.dll')).Hash){throw "$kind packaged a different native library"}
  Write-Output "$kind client: $(Join-Path $output 'BombPerformance.exe')"
 }
}finally{$env:BOM_NATIVE_SERVER_EXE=$oldServer;$env:BOM_PERFORMANCE_PLAYER_OUT=$oldOutput}
