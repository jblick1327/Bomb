[CmdletBinding()]
param(
 [ValidateSet('Mono','IL2CPP','Both')][string]$Backend='Both',
 [string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json'),
 # P3: a release build (no Development watermark) for testers, into Game-<backend>-Release; gates use the Development build.
 [switch]$Release
)
# F4: builds the front-door game (Bomb.exe, MainMenuScene first, Server/BOM-server.exe and Server/levels/*.json beside it)
# into integration/build/validation/Game-Mono and/or Game-IL2CPP. Works in Windows PowerShell 5.1 and PowerShell 7.
# Files outside Assets/BOMIntegration (Darryn's MatchMenuUI.cs) must already be mirrored into the validation project (rule 7, Sync); this checks it.
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot;$unityRoot=Split-Path -Parent $integration
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
$validation=[IO.Path]::GetFullPath($config.UnityValidationProject)
if($validation.TrimEnd('\','/') -eq [IO.Path]::GetFullPath($unityRoot).TrimEnd('\','/')){throw 'Use the separate validation project in local.config.json.'}
foreach($file in @('Assets/Game/Scripts/MatchMenuUI.cs')){
 if((Get-FileHash -LiteralPath (Join-Path $unityRoot $file)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $validation $file)).Hash){throw "$file differs in the validation project. Mirror it first (ALPHA-SYNC rule 7, Sync)."}
}
$assets=Join-Path $validation 'Assets/BOMIntegration'
$plugin=Join-Path $assets 'Plugins/x86_64/bomcore.dll'
if(Test-Path -LiteralPath $plugin){$probe=[IO.File]::Open($plugin,'Open','ReadWrite','None');$probe.Dispose()}
New-Item -ItemType Directory -Path $assets -Force|Out-Null
Copy-Item -Path (Join-Path $unityRoot 'Assets/BOMIntegration/*') -Destination $assets -Recurse -Force
Copy-Item (Join-Path $config.OdinRoot 'build/bomcore.dll') $plugin -Force
Copy-Item (Join-Path $config.OdinRoot 'bindings/BomNative.cs') (Join-Path $assets 'Runtime/BomNative.cs') -Force
$kinds=if($Backend -eq 'Both'){@('Mono','IL2CPP')}else{@($Backend)}
foreach($kind in $kinds){
 $output=Join-Path $integration ('build/validation/Game-'+$kind+$(if($Release){'-Release'}else{''}));New-Item -ItemType Directory -Path $output -Force|Out-Null
 # BOM_INTEGRATION_ROOT: the validation copy has no integration/ of its own, and the level export reads materials.json from it.
 $values=@{BOM_GAME_RELEASE=$(if($Release){'1'}else{''});BOM_INTEGRATION_ROOT=$integration;BOM_NATIVE_SERVER_EXE=(Join-Path $config.OdinRoot 'build/BOM-server.exe');BOM_GAME_PLAYER_OUT=$output;BOM_YARD_LAYOUT_OUT=(Join-Path $integration 'fixtures/network-yard/yard.json');BOM_TILE_LEVEL_DIR=(Join-Path $integration 'fixtures/levels')}
 $previous=@{}
 try{
  foreach($key in $values.Keys){$previous[$key]=[Environment]::GetEnvironmentVariable($key);[Environment]::SetEnvironmentVariable($key,$values[$key])}
  $method=if($kind -eq 'Mono'){'BomFrontDoorBuilder.BuildMono'}else{'BomFrontDoorBuilder.BuildIl2Cpp'}
  $log=Join-Path $output ('editor-build-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'.log')
  $process=Start-Process -FilePath $config.UnityEditor -ArgumentList @('-batchmode','-quit','-projectPath',('"'+$validation+'"'),'-executeMethod',$method,'-logFile',('"'+$log+'"')) -WindowStyle Hidden -PassThru
  $null=$process.Handle # PowerShell 5.1 reports no ExitCode unless the handle was opened before exit
  $process.WaitForExit()
  if($process.ExitCode -ne 0){throw "$kind front-door build failed. Inspect $log"}
 }finally{foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key])}}
 $dll=Get-ChildItem -LiteralPath $output -Recurse -Filter bomcore.dll|Select-Object -First 1
 if((Get-FileHash -LiteralPath $dll.FullName).Hash -ne (Get-FileHash -LiteralPath (Join-Path $config.OdinRoot 'build/bomcore.dll')).Hash){throw "$kind game packaged a different native library"}
 Write-Output "$kind game: $(Join-Path $output 'Bomb.exe')"
}
