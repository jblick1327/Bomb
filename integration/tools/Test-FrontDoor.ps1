[CmdletBinding()]
param(
 [switch]$SkipBuild,
 [string]$PlayerPath='',
 [string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json')
)
# C5 front-door gate. Builds integration/build/validation/Game-Mono/Bomb.exe (MainMenuScene first, Server/ beside it)
# in the validation project, then runs Run-FrontDoor.py. Works in Windows PowerShell 5.1 and PowerShell 7.
# Files outside Assets/BOMIntegration (Darryn's MatchMenuUI.cs hook) must already be mirrored (rule 7, Sync); this checks it.
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot;$unityRoot=Split-Path -Parent $integration
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
$validation=[IO.Path]::GetFullPath($config.UnityValidationProject)
$output=Join-Path $integration 'build/validation/Game-Mono'
if(!$PlayerPath){$PlayerPath=Join-Path $output 'Bomb.exe'}
if(!$SkipBuild){
 if($validation.TrimEnd('\','/') -eq [IO.Path]::GetFullPath($unityRoot).TrimEnd('\','/')){throw 'Use the separate validation project in local.config.json.'}
 foreach($file in @('Assets/Game/Scripts/MatchMenuUI.cs')){
  if((Get-FileHash -LiteralPath (Join-Path $unityRoot $file)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $validation $file)).Hash){throw "$file differs in the validation project. Mirror it first (ALPHA-SYNC rule 7, Sync)."}
 }
 $assets=Join-Path $validation 'Assets/BOMIntegration'
 $plugin=Join-Path $assets 'Plugins/x86_64/bomcore.dll'
 if(Test-Path -LiteralPath $plugin){$probe=[IO.File]::Open($plugin,'Open','ReadWrite','None');$probe.Dispose()}
 New-Item -ItemType Directory -Path $assets,$output -Force|Out-Null
 Copy-Item -Path (Join-Path $unityRoot 'Assets/BOMIntegration/*') -Destination $assets -Recurse -Force
 Copy-Item (Join-Path $config.OdinRoot 'build/bomcore.dll') $plugin -Force
 Copy-Item (Join-Path $config.OdinRoot 'bindings/BomNative.cs') (Join-Path $assets 'Runtime/BomNative.cs') -Force
 $values=@{BOM_NATIVE_SERVER_EXE=(Join-Path $config.OdinRoot 'build/BOM-server.exe');BOM_GAME_PLAYER_OUT=$output;BOM_YARD_LAYOUT_OUT=(Join-Path $integration 'fixtures/network-yard/yard.json')}
 $previous=@{}
 try{
  foreach($key in $values.Keys){$previous[$key]=[Environment]::GetEnvironmentVariable($key);[Environment]::SetEnvironmentVariable($key,$values[$key])}
  $log=Join-Path $output ('editor-build-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'.log')
  $process=Start-Process -FilePath $config.UnityEditor -ArgumentList @('-batchmode','-quit','-projectPath',('"'+$validation+'"'),'-executeMethod','BomFrontDoorBuilder.BuildMono','-logFile',('"'+$log+'"')) -WindowStyle Hidden -PassThru
  $null=$process.Handle # PowerShell 5.1 reports no ExitCode unless the handle was opened before exit
  $process.WaitForExit()
  if($process.ExitCode -ne 0){throw "Front-door player build failed. Inspect $log"}
 }finally{foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key])}}
}
python (Join-Path $PSScriptRoot 'Run-FrontDoor.py') --config $ConfigPath --player $PlayerPath
if($LASTEXITCODE -ne 0){throw 'Front-door gate failed. Inspect its evidence/M8/frontdoor-* directory.'}
