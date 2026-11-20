[CmdletBinding()]
param(
 [ValidateSet('Mono','IL2CPP')][string]$Backend='Mono',
 [ValidateRange(1,4)][int]$Clients=2,
 [ValidateRange(1,65535)][int]$Port=47380,
 # Show the "run it on the host PC / the other PC" LAN instructions with this PC's addresses.
 [switch]$Lan,
 # One game window only (the other PC of a LAN game). Same as -Clients 1.
 [switch]$ClientOnly
)
# Works in Windows PowerShell 5.1 and PowerShell 7: no ProcessStartInfo.ArgumentList, no Path.GetRelativePath.
# F4: the package ships the front-door game. This opens $Clients windows of Bomb.exe at Darryn's main menu. The game starts and
# stops its own BOM-server.exe (ONLINE > HOST GAME > START; the other window uses JOIN GAME), so nothing else runs here.
$ErrorActionPreference='Stop'
$package=$PSScriptRoot;$playerPath=Join-Path $package "$Backend/Bomb.exe"
foreach($path in @($playerPath,(Join-Path $package "$Backend/Server/BOM-server.exe"))){if(!(Test-Path -LiteralPath $path)){throw "Missing package file: $path"}}
if($ClientOnly){$Clients=1}
$session=Join-Path $package ('Logs/'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'));New-Item -ItemType Directory -Path $session -Force|Out-Null
$players=@()
for($i=0;$i -lt $Clients;$i++){
 $arguments=@('--bom-port',"$Port",'-screen-fullscreen','0','-screen-width','1280','-screen-height','720','-logFile',('"'+(Join-Path $session "player-$i.log")+'"'))
 $players+=Start-Process -FilePath $playerPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $playerPath) -PassThru
}
Write-Output "Started $Clients $Backend game window(s). Logs: $session"
Write-Output "Window 1: ONLINE > HOST GAME > pick a level > START. Window 2: ONLINE > JOIN GAME (127.0.0.1, port $Port unless the host window says otherwise) > JOIN."
if($Lan){
 $addresses=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue|Where-Object{$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*'}|ForEach-Object{$_.IPAddress})
 Write-Output "LAN: choose 'LAN / direct IP' in HOST GAME. Other PCs run Launch-Bom.ps1 -ClientOnly, then JOIN GAME with one of: $($addresses -join ', ') and the port above."
 Write-Output "Windows may ask to allow BOM-server.exe: tick Private networks, then Allow."
}
# Wait for every window; the game stops its own server when its host leaves or quits (and a job object ends it if the game crashes).
foreach($player in $players){$player.WaitForExit()}
