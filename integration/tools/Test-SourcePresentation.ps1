[CmdletBinding()]
param(
 [ValidateSet('All','Fixtures','TierComparison','Invalidation','Yard')][string]$Mode='All',
 [ValidateRange(15,120)][int]$Seconds=60,
 [switch]$SkipBuild,
 [string]$PlayerPath='',
 [string]$YardPlayerPath='',
 [string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json')
)
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
$unityRoot=Split-Path -Parent $integration
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
$validation=[IO.Path]::GetFullPath($config.UnityValidationProject)
$fixtureOutput=Join-Path $integration 'build/SourceFixtures-Mono'
$yardOutput=Join-Path $integration 'build/SourceYard-Mono'
$fixtureLayout=Join-Path $integration 'evidence/M7/source-export/fixtures.json'
$yardLayout=Join-Path $integration 'evidence/M7/yard-export/yard.json'
if(!$PlayerPath){$PlayerPath=Join-Path $fixtureOutput 'BombSourceFixtures.exe'}
if(!$YardPlayerPath){$YardPlayerPath=Join-Path $yardOutput 'BombNetworkYard.exe'}
if(!$SkipBuild){
 if($validation.TrimEnd('\','/') -eq [IO.Path]::GetFullPath($unityRoot).TrimEnd('\','/')){throw 'Use the separate validation project configured in local.config.json.'}
 if(!(Test-Path (Join-Path $unityRoot 'Assets/BOMIntegration/Runtime/BomSourcePresentation.cs'))){throw 'The M7 SDK must be present in Assets/BOMIntegration.'}
 $open=Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'"|Where-Object {$_.CommandLine -and $_.CommandLine.Contains($validation)}
 if($open){throw 'The dedicated validation Editor is already open; wait for its current job to finish.'}
 $assets=Join-Path $validation 'Assets/BOMIntegration'
 New-Item -ItemType Directory -Path $assets,$fixtureOutput,$yardOutput -Force|Out-Null
 Copy-Item -Path (Join-Path $unityRoot 'Assets/BOMIntegration/*') -Destination $assets -Recurse -Force
 Copy-Item (Join-Path $config.OdinRoot 'build/bomcore.dll') (Join-Path $assets 'Plugins/x86_64/bomcore.dll') -Force
 Copy-Item (Join-Path $config.OdinRoot 'bindings/BomNative.cs') (Join-Path $assets 'Runtime/BomNative.cs') -Force
 $values=@{
  BOM_NATIVE_SERVER_EXE=(Join-Path $config.OdinRoot 'build/BOM-server.exe')
  BOM_SOURCE_LAYOUT_OUT=$fixtureLayout
  BOM_SOURCE_PLAYER_OUT=$fixtureOutput
  BOM_YARD_LAYOUT_OUT=$yardLayout
  BOM_YARD_PLAYER_OUT=$yardOutput
 }
 $previous=@{}
 try{
  foreach($key in $values.Keys){$previous[$key]=[Environment]::GetEnvironmentVariable($key);[Environment]::SetEnvironmentVariable($key,$values[$key])}
  $method=if($Mode -eq 'All'){'BomM7FinalBuild.Run'}elseif($Mode -eq 'Yard'){'BomM7YardGate.BuildMono'}else{'BomSourceFixtureBuilder.BuildMono'}
  $log=Join-Path $(if($Mode -eq 'Yard'){$yardOutput}else{$fixtureOutput}) 'editor-build.log'
  $process=Start-Process -FilePath $config.UnityEditor -ArgumentList @('-batchmode','-quit','-projectPath',('"'+$validation+'"'),'-executeMethod',$method,'-logFile',('"'+$log+'"')) -WindowStyle Hidden -PassThru -Wait
  if($process.ExitCode -ne 0){throw "Source presentation build failed. Inspect $log"}
 }finally{foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key])}}
}
foreach($hostName in @('interop-source','interop-level')){
 $hostOutput=Join-Path $config.OdinRoot "build/$hostName"
 & dotnet build (Join-Path $config.OdinRoot 'tests/interop/Interop.csproj') --source (Join-Path $config.OdinRoot 'build/empty-nuget') --nologo -o $hostOutput
 if($LASTEXITCODE -ne 0){throw 'Native test host build failed.'}
 Copy-Item (Join-Path $config.OdinRoot 'build/bomcore.dll') (Join-Path $hostOutput 'bomcore.dll') -Force
}
$scenarios=if($Mode -eq 'All'){@('Fixtures','TierComparison','Invalidation','Yard')}else{@($Mode)}
foreach($scenario in $scenarios){
 if($scenario -eq 'Yard'){
  $arguments=@((Join-Path $PSScriptRoot 'Run-SourceYardInterop.py'),'--config',$ConfigPath,'--layout',$yardLayout,'--player',$YardPlayerPath,'--seconds',"$Seconds")
 }else{
  $arguments=@((Join-Path $PSScriptRoot 'Run-SourceInterop.py'),'--config',$ConfigPath,'--layout',$fixtureLayout,'--player',$PlayerPath,'--seconds',"$Seconds")
  if($scenario -eq 'TierComparison'){$arguments+='--tier1-late'}
  if($scenario -eq 'Invalidation'){$arguments+='--invalidate-jobs'}
 }
 & python @arguments
 if($LASTEXITCODE -ne 0){throw "$scenario failed. Inspect its new evidence/M7 directory."}
}
