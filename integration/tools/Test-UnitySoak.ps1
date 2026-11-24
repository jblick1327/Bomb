[CmdletBinding()]
param(
 [string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json'),
 [ValidateRange(60,3600)][int]$Seconds=1800,
 [ValidateSet('Mono','IL2CPP','mixed')][string]$Backend='mixed',
 [string]$PrimaryPlayer='', [string]$GuestPlayer='', [switch]$SkipBuild
)
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
if(!$SkipBuild){
 & (Join-Path $PSScriptRoot 'Build-BomPlayers.ps1') -ConfigPath $ConfigPath -Backend Both
 if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
}
if(!$PrimaryPlayer){$kind=if($Backend -eq 'IL2CPP'){'IL2CPP'}else{'Mono'};$PrimaryPlayer=Join-Path $integration "build/validation/$kind/BombPerformance.exe"}
if(!$GuestPlayer){$kind=if($Backend -eq 'Mono'){'Mono'}else{'IL2CPP'};$GuestPlayer=Join-Path $integration "build/validation/$kind/BombPerformance.exe"}
foreach($path in @($PrimaryPlayer,$GuestPlayer)){if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Client build missing: $path"}}
$hostBuild=Join-Path $integration 'build/interop-performance-host'
$empty=Join-Path $integration 'build/empty-nuget'
New-Item -ItemType Directory -Path $hostBuild,$empty -Force|Out-Null
& dotnet build (Join-Path $integration 'soak-host/PerformanceHost.csproj') -c Release -o $hostBuild --source $empty "-p:NativeBindingsPath=$(Join-Path $config.OdinRoot 'bindings/BomNative.cs')"
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& python (Join-Path $PSScriptRoot 'Run-UnitySoak.py') --config $ConfigPath --seconds $Seconds --backend $Backend --primary-player $PrimaryPlayer --guest-player $GuestPlayer --layout (Join-Path $integration 'fixtures/M9/PerformanceReference.json') --host-tool (Join-Path $hostBuild 'PerformanceHost.dll')
exit $LASTEXITCODE
