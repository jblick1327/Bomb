[CmdletBinding()]
param(
 [ValidateSet('All','Yard','Draw')][string]$Scenario='All',
 [switch]$SkipBuild,
 [string]$PlayerPath='',
 [string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json')
)
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot;$unityRoot=Split-Path -Parent $integration
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
$validation=[IO.Path]::GetFullPath($config.UnityValidationProject)
$output=Join-Path $integration 'build/validation/Network-Mono'
if(!$PlayerPath){$PlayerPath=Join-Path $(if($SkipBuild){Join-Path $integration 'build/Network-Mono'}else{$output}) 'BombNetwork.exe'}
if(!$SkipBuild){
 if($validation.TrimEnd('\','/') -eq [IO.Path]::GetFullPath($unityRoot).TrimEnd('\','/')){throw 'Use the separate validation project in local.config.json.'}
 $assets=Join-Path $validation 'Assets/BOMIntegration'
 $plugin=Join-Path $assets 'Plugins/x86_64/bomcore.dll'
 if(Test-Path -LiteralPath $plugin){$probe=[IO.File]::Open($plugin,'Open','ReadWrite','None');$probe.Dispose()}
 New-Item -ItemType Directory -Path $assets,$output -Force|Out-Null
 Copy-Item -Path (Join-Path $unityRoot 'Assets/BOMIntegration/*') -Destination $assets -Recurse -Force
 Copy-Item (Join-Path $config.OdinRoot 'build/bomcore.dll') $plugin -Force
 Copy-Item (Join-Path $config.OdinRoot 'bindings/BomNative.cs') (Join-Path $assets 'Runtime/BomNative.cs') -Force
 $values=@{BOM_NATIVE_SERVER_EXE=(Join-Path $config.OdinRoot 'build/BOM-server.exe');BOM_NETWORK_PLAYER_OUT=$output;BOM_YARD_LAYOUT_OUT=(Join-Path $integration 'fixtures/network-yard/yard.json');BOM_ROUND_DRAW_LAYOUT_OUT=(Join-Path $integration 'build/validation/round-draw/draw.json')}
 $previous=@{}
 try{
  foreach($key in $values.Keys){$previous[$key]=[Environment]::GetEnvironmentVariable($key);[Environment]::SetEnvironmentVariable($key,$values[$key])}
  $log=Join-Path $output 'editor-build.log'
  $process=Start-Process -FilePath $config.UnityEditor -ArgumentList @('-batchmode','-quit','-projectPath',('"'+$validation+'"'),'-executeMethod','BomNetworkMenuBuilder.BuildWithDrawFixture','-logFile',('"'+$log+'"')) -WindowStyle Hidden -Wait -PassThru
  if($process.ExitCode -ne 0){throw "Network player build failed. Inspect $log"}
 }finally{foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key])}}
}
$hostOutput=Join-Path $config.OdinRoot 'build/interop-rounds'
dotnet build (Join-Path $config.OdinRoot 'tests/interop/Interop.csproj') --source (Join-Path $config.OdinRoot 'build/empty-nuget') --nologo -o $hostOutput
if($LASTEXITCODE -ne 0){throw 'Round test host build failed.'}
$scenarios=if($Scenario -eq 'All'){@('Yard','Draw')}else{@($Scenario)}
foreach($kind in $scenarios){
 $layout=if($kind -eq 'Yard'){Join-Path $integration 'fixtures/network-yard/yard.json'}elseif($SkipBuild){Join-Path $integration 'fixtures/round-draw/draw.json'}else{Join-Path $integration 'build/validation/round-draw/draw.json'}
 $arguments=@((Join-Path $PSScriptRoot 'Run-UnityRounds.py'),'--config',$ConfigPath,'--layout',$layout,'--player',$PlayerPath)
 if($kind -eq 'Draw'){$arguments+='--draw'}
 python @arguments
 if($LASTEXITCODE -ne 0){throw "$kind round gate failed. Inspect its evidence/M8 directory."}
}
