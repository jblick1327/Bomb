[CmdletBinding()]
param([string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json'),[ValidateSet('Mono','IL2CPP')][string]$Backend='Mono',[ValidateSet('Reference','Stress')][string]$Load='Reference',[ValidateRange(10,3600)][int]$Seconds=60,[string]$PlayerPath='',[switch]$Tier1,[switch]$SkipBuild)
$ErrorActionPreference='Stop';$integration=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
if(!$SkipBuild){& (Join-Path $PSScriptRoot 'Build-BomPlayers.ps1') -ConfigPath $ConfigPath -Backend $Backend;if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}}
if(!$PlayerPath){$PlayerPath=Join-Path $integration "build/validation/$Backend/BombPerformance.exe"}
$hostBuild=Join-Path $integration 'build/interop-performance-host';$empty=Join-Path $integration 'build/empty-nuget'
New-Item -ItemType Directory -Path $hostBuild,$empty -Force|Out-Null
dotnet build (Join-Path $integration 'soak-host/PerformanceHost.csproj') -c Release -o $hostBuild --source $empty "-p:NativeBindingsPath=$(Join-Path $config.OdinRoot 'bindings/BomNative.cs')"
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$arguments=@((Join-Path $PSScriptRoot 'Run-Performance.py'),'--config',$ConfigPath,'--player',$PlayerPath,'--layout',(Join-Path $integration "fixtures/M9/Performance$Load.json"),'--scene',"Performance$Load",'--seconds',"$Seconds",'--warmup','10','--backend',$Backend)
if($Tier1){$arguments+='--tier1'}
python @arguments
exit $LASTEXITCODE
