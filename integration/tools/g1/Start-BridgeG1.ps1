# G1 prototype launcher (Windows PowerShell 5.1 or 7). Opens the front-door game with the G1 flag and the G1 Bridge layout.
# In each window: ONLINE > HOST GAME > BRIDGE > START (window 2: ONLINE > JOIN GAME > 127.0.0.1, the port window 1 shows, BRIDGE).
# Every window must carry --bom-g1: a window without it expects the shipped Bridge's manifest and the server refuses it.
# Without --bom-g1 the game is unchanged; this script only adds flags. It writes a levels folder under %TEMP% (the
# game's shipped layouts, with BridgeLevel.json replaced by the G1 Bridge) and passes it with --bom-levels.
# The other picker entries keep their shipped layouts and are drawn with depth-from-shape too.
param(
 [string]$Game=(Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'build\validation\Game-Mono\Bomb.exe'),
 [ValidateRange(1,2)][int]$Clients=1,
 [double]$Band=1.6
)
$ErrorActionPreference='Stop'
if(!(Test-Path -LiteralPath $Game)){throw "Game not found: $Game (build it with integration/tools/Build-BomGame.ps1 -Backend Mono)"}
$g1=Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'fixtures\levels-g1\BridgeLevel.json'
if(!(Test-Path -LiteralPath $g1)){throw "G1 layout missing: $g1 (run integration/tools/g1/Build-BridgeG1.py)"}
$shipped=Join-Path (Split-Path -Parent $Game) 'Server\levels'
$levels=Join-Path $env:TEMP 'bom-g1-levels'
New-Item -ItemType Directory -Force -Path $levels|Out-Null
Get-ChildItem -LiteralPath $shipped -Filter '*.json'|ForEach-Object{Copy-Item -LiteralPath $_.FullName -Destination $levels -Force}
Copy-Item -LiteralPath $g1 -Destination (Join-Path $levels 'BridgeLevel.json') -Force
$inv=[Globalization.CultureInfo]::InvariantCulture
for($i=0;$i -lt $Clients;$i++){
 $log=Join-Path $env:TEMP ("bom-g1-player-$i-"+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')+'.log')
 $playerArgs=@('--bom-g1','--bom-g1-band',$Band.ToString($inv),'--bom-levels',('"'+$levels+'"'),'-screen-fullscreen','0','-screen-width','1280','-screen-height','720','-logFile',('"'+$log+'"'))
 Start-Process -FilePath $Game -ArgumentList $playerArgs -WorkingDirectory (Split-Path -Parent $Game)|Out-Null
 Write-Output "Window $($i+1): log $log"
}
Write-Output 'Host: ONLINE > HOST GAME > BRIDGE > START. Join (window 2): ONLINE > JOIN GAME > 127.0.0.1 + port > BRIDGE.'
