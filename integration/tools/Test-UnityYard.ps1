[CmdletBinding()]
param([ValidateSet('Mono','IL2CPP')][string]$Backend='Mono',[ValidateRange(15,120)][int]$Seconds=30,[switch]$SkipBuild,[switch]$MissingArt,[switch]$RejectManifest,[string]$PlayerPath='', [string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json'))
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot;$unityRoot=Split-Path -Parent $integration
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
$layout=Join-Path $integration 'evidence/M6/yard-export/yard.json'
$output=Join-Path $integration "build/Yard-$Backend"
if(!$PlayerPath){$PlayerPath=Join-Path $output 'BombNetworkYard.exe'}
$validation=[IO.Path]::GetFullPath($config.UnityValidationProject)
if(!$SkipBuild){
 if($validation.TrimEnd('\','/') -eq [IO.Path]::GetFullPath($unityRoot).TrimEnd('\','/')){throw 'Use a separate Unity validation project.'}
 $open=Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'"|Where-Object {$_.CommandLine -and $_.CommandLine.Contains($validation)}
 if($open){throw 'Close the dedicated validation Editor before updating its native plugin.'}
 $assets=Join-Path $validation 'Assets/BOMIntegration'
 Copy-Item -Path (Join-Path $unityRoot 'Assets/BOMIntegration/*') -Destination $assets -Recurse -Force
 Copy-Item (Join-Path $config.OdinRoot 'build/bomcore.dll') (Join-Path $assets 'Plugins/x86_64/bomcore.dll') -Force
 Copy-Item (Join-Path $config.OdinRoot 'bindings/BomNative.cs') (Join-Path $assets 'Runtime/BomNative.cs') -Force
 $oldServer=$env:BOM_NATIVE_SERVER_EXE;$oldLayout=$env:BOM_YARD_LAYOUT_OUT;$oldOutput=$env:BOM_YARD_PLAYER_OUT
 try{
  $env:BOM_NATIVE_SERVER_EXE=Join-Path $config.OdinRoot 'build/BOM-server.exe';$env:BOM_YARD_LAYOUT_OUT=$layout;$env:BOM_YARD_PLAYER_OUT=$output
  New-Item -ItemType Directory -Path $output -Force|Out-Null
  $method=if($Backend -eq 'Mono'){'BomYardBuilder.BuildMono'}else{'BomYardBuilder.BuildIl2Cpp'}
  $process=Start-Process -FilePath $config.UnityEditor -ArgumentList @('-batchmode','-quit','-projectPath',('"'+$validation+'"'),'-executeMethod',$method,'-logFile',('"'+(Join-Path $output 'editor-build.log')+'"')) -WindowStyle Hidden -PassThru -Wait
  if($process.ExitCode -ne 0){throw 'Yard standalone build failed; inspect its editor-build.log.'}
 }finally{$env:BOM_NATIVE_SERVER_EXE=$oldServer;$env:BOM_YARD_LAYOUT_OUT=$oldLayout;$env:BOM_YARD_PLAYER_OUT=$oldOutput}
}
$hostOutput=Join-Path $config.OdinRoot 'build/interop-level'
& dotnet build (Join-Path $config.OdinRoot 'tests/interop/Interop.csproj') --source (Join-Path $config.OdinRoot 'build/empty-nuget') --nologo -o $hostOutput
if($LASTEXITCODE -ne 0){throw 'Yard native test host failed to build.'}
Copy-Item (Join-Path $config.OdinRoot 'build/bomcore.dll') (Join-Path $hostOutput 'bomcore.dll') -Force
$tool=if($RejectManifest){'Test-LevelManifest.py'}else{'Run-LevelInterop.py'}
$arguments=@((Join-Path $PSScriptRoot $tool),'--config',$ConfigPath,'--layout',$layout,'--player',$PlayerPath)
if(!$RejectManifest){$arguments+=@('--seconds',"$Seconds");if($MissingArt){$arguments+='--no-visual-registry'}}
& python @arguments
if($LASTEXITCODE -ne 0){throw 'Exported yard gate failed; inspect the new evidence/M6 report.'}
