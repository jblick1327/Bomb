[CmdletBinding()]
param([ValidateSet('Mono','IL2CPP','Editor')][string]$Backend='Mono',[ValidateRange(1,3600)][int]$Seconds=24,[double]$TimeScale=1,[switch]$SingleUnity,[switch]$PredictionOff,[switch]$SkipBuild,[string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json'))
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot;$unityRoot=Split-Path -Parent $integration
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
$validation=[IO.Path]::GetFullPath($config.UnityValidationProject)
if($validation.TrimEnd('\','/') -eq [IO.Path]::GetFullPath($unityRoot).TrimEnd('\','/')){throw 'UnityValidationProject must be a separate disposable project copy.'}
if(!(Test-Path -LiteralPath (Join-Path $validation 'ProjectSettings/ProjectVersion.txt'))){throw 'Prepare a separate copy of Assets, Packages and ProjectSettings and set UnityValidationProject in local.config.json.'}
$version=Get-Content -LiteralPath (Join-Path $validation 'ProjectSettings/ProjectVersion.txt') -Raw
if($version -notmatch '6000\.2\.14f1'){throw 'The validation copy must use the pinned Unity 6000.2.14f1 Editor.'}
$open=Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'"|Where-Object {$_.CommandLine -and $_.CommandLine.Contains($validation)}
if($open){throw 'The dedicated validation Editor is already open; close it before copying or building its plugin.'}
$assets=Join-Path $validation 'Assets/BOMIntegration';New-Item -ItemType Directory -Path $assets -Force|Out-Null
Copy-Item -Path (Join-Path $unityRoot 'Assets/BOMIntegration/*') -Destination $assets -Recurse -Force
Copy-Item -LiteralPath (Join-Path $config.OdinRoot 'build/bomcore.dll') -Destination (Join-Path $assets 'Plugins/x86_64/bomcore.dll') -Force
Copy-Item -LiteralPath (Join-Path $config.OdinRoot 'bindings/BomNative.cs') -Destination (Join-Path $assets 'Runtime/BomNative.cs') -Force
$hostOutput=Join-Path $config.OdinRoot 'build/interop-unity'
& dotnet build (Join-Path $config.OdinRoot 'tests/interop/Interop.csproj') --source (Join-Path $config.OdinRoot 'build/empty-nuget') --nologo -o $hostOutput
if($LASTEXITCODE -ne 0){throw 'Native test-host build failed.'}
Copy-Item -LiteralPath (Join-Path $config.OdinRoot 'build/bomcore.dll') -Destination (Join-Path $hostOutput 'bomcore.dll') -Force
$arguments=@((Join-Path $PSScriptRoot 'Run-UnityLive.py'),'--config',$ConfigPath,'--host-runner',(Join-Path $hostOutput 'Interop.dll'),'--seconds',"$Seconds",'--time-scale',"$TimeScale")
if($PredictionOff){$arguments+='--prediction-off'}
if($Backend -eq 'Editor'){$arguments+='--editor'}else{
 $output=Join-Path $integration "build/$Backend";New-Item -ItemType Directory -Path $output -Force|Out-Null
 if(!$SkipBuild){
  $method=if($Backend -eq 'Mono'){'BomSliceBuilder.BuildMono'}else{'BomSliceBuilder.BuildIl2Cpp'}
  $oldOutput=$env:BOM_SLICE_OUTPUT
  try{
   $env:BOM_SLICE_OUTPUT=$output;$log=Join-Path $output 'editor-build.log'
   $process=Start-Process -FilePath $config.UnityEditor -ArgumentList @('-batchmode','-quit','-projectPath',('"'+$validation+'"'),'-executeMethod',$method,'-logFile',('"'+$log+'"')) -WindowStyle Hidden -PassThru
   $process.WaitForExit();if($process.ExitCode -ne 0){throw "Unity $Backend build exited $($process.ExitCode); see $log"}
  }finally{$env:BOM_SLICE_OUTPUT=$oldOutput}
 }
 $arguments+=@('--player',(Join-Path $output 'BombNativeSlice.exe'))
 if(!$SingleUnity){$arguments+='--two-unity'}
}
& python @arguments
if($LASTEXITCODE -ne 0){throw 'Unity live gate failed; see the new evidence/M4 run directory.'}
