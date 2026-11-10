[CmdletBinding()]
param(
 [ValidateSet('Mono','IL2CPP')][string]$Backend='Mono',
 [ValidateRange(1,2)][int]$Clients=2,
 [ValidateRange(1,65535)][int]$Port=47380,
 [ValidateSet('127.0.0.1','0.0.0.0')][string]$Bind='127.0.0.1',
 # LAN host: bind every interface and show the addresses other machines type into the connection menu.
 [switch]$Lan,
 # LAN guest: start only a game window; type the host machine's address and port in its menu. No server runs here.
 [switch]$ClientOnly
)
# Works in Windows PowerShell 5.1 and PowerShell 7: no ProcessStartInfo.ArgumentList, no static GetBytes(int),
# no Path.GetRelativePath.
$ErrorActionPreference='Stop'
$package=$PSScriptRoot
$serverPath=Join-Path $package 'Server/BOM-server.exe';$playerPath=Join-Path $package "$Backend/BombPerformance.exe";$layout=Join-Path $package 'yard.json'
$required=if($ClientOnly){@($playerPath)}else{@($serverPath,$playerPath,$layout)}
foreach($path in $required){if(!(Test-Path -LiteralPath $path)){throw "Missing package file: $path"}}
if($Lan -and $ClientOnly){throw 'Use -Lan on the host machine and -ClientOnly on the other machine, not both.'}
if($Lan){$Bind='0.0.0.0'}
$session=Join-Path $package ('Logs/'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'));New-Item -ItemType Directory -Path $session -Force|Out-Null
function New-HostKey{$bytes=New-Object byte[] 24;$rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($bytes)}finally{$rng.Dispose()};[Convert]::ToBase64String($bytes)}
function Start-Player([string]$name,[bool]$isHost,[string]$key,[bool]$autoConnect){
 $arguments=@('--bom-port',"$Port",'-screen-fullscreen','0','-screen-width','1280','-screen-height','720','-logFile',('"'+(Join-Path $session "$name.log")+'"'))
 if($autoConnect){$arguments=@('--bom-auto-connect')+$arguments}
 $old=$env:BOM_TEST_HOST_TOKEN
 try{
  if($isHost){$env:BOM_TEST_HOST_TOKEN=$key}else{Remove-Item Env:BOM_TEST_HOST_TOKEN -ErrorAction SilentlyContinue}
  Start-Process -FilePath $playerPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $playerPath) -PassThru
 }finally{if($null -ne $old){$env:BOM_TEST_HOST_TOKEN=$old}else{Remove-Item Env:BOM_TEST_HOST_TOKEN -ErrorAction SilentlyContinue}}
}
if($ClientOnly){
 $guest=Start-Player 'player-guest' $false '' $false
 Write-Output "Game window started ($Backend). In its connection menu enter the host machine's address and port $Port, then connect."
 Write-Output "Logs: $session"
 $guest.WaitForExit()
 return
}
$key=New-HostKey;$server=$null;$players=@()
try{
 $server=Start-Process -FilePath $serverPath -ArgumentList @('--bind',$Bind,'--port',"$Port",'--layout',('"'+$layout+'"'),'--host-token',$key) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $session 'server.log') -RedirectStandardError (Join-Path $session 'server-errors.log') -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(90)
 while(!((Get-Content (Join-Path $session 'server.log') -Raw -ErrorAction SilentlyContinue) -match 'BOM staging server listening')){
  if($server.HasExited){throw "Server could not start. Check $session"};if([DateTime]::UtcNow -gt $deadline){throw "Server startup timed out. Check $session"};Start-Sleep -Milliseconds 100
 }
 for($i=0;$i -lt $Clients;$i++){$players+=Start-Player "player-$i" ($i -eq 0) $key $true}
 if($Lan){
  $addresses=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue|Where-Object{$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*'}|ForEach-Object{$_.IPAddress})
  Write-Output "LAN game on UDP port $Port. Other machines: run ./Launch-Bom.ps1 -ClientOnly, then enter one of these addresses in the menu: $($addresses -join ', ')"
  Write-Output "If they cannot connect, allow BOM-server.exe through Windows Firewall (Private networks) on this machine."
 }
 Write-Output "Game: $Bind`:$Port. First window is host. Esc opens the menu. Logs: $session"
 while(!$players[0].WaitForExit(1000)){if($server.HasExited){break}}
 if(!$server.WaitForExit(6500)){throw 'The host closed before server shutdown completed.'}
}finally{if($server -ne $null -and !$server.HasExited){$server.Kill();$server.WaitForExit()}}
