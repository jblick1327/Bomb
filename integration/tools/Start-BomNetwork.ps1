[CmdletBinding()]
param([ValidateRange(1,65535)][int]$Port=47380,[ValidateRange(1,2)][int]$Clients=2,[ValidateSet('Mono','IL2CPP')][string]$Backend='Mono',[ValidateSet('127.0.0.1','0.0.0.0')][string]$Bind='127.0.0.1')
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
$serverPath=Join-Path $integration 'build/M9-native/BOM-server.exe'
$playerPath=Join-Path $integration "build/M9-$Backend/BombPerformance.exe"
$layoutPath=Join-Path $integration 'fixtures/network-yard/yard.json'
foreach($path in @($serverPath,$playerPath,$layoutPath)){if(!(Test-Path -LiteralPath $path)){throw "Missing local build: $path"}}
$session=Join-Path $integration ('build/sessions/'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
$null=New-Item -ItemType Directory -Path $session -Force
$bytes=New-Object byte[] 24;$rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
$key=[Convert]::ToBase64String($bytes)
$server=$null;$players=@()
try{
 $server=Start-Process -FilePath $serverPath -ArgumentList @('--bind',$Bind,'--port',"$Port",'--layout',('"'+$layoutPath+'"'),'--host-token',$key) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $session 'server.log') -RedirectStandardError (Join-Path $session 'server-errors.log') -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(60)
 while(!((Get-Content (Join-Path $session 'server.log') -Raw -ErrorAction SilentlyContinue) -match 'BOM staging server listening')){
  if($server.HasExited){throw "Server could not start. Check $session"}
  if([DateTime]::UtcNow -gt $deadline){throw "Server startup timed out. Check $session"}
  Start-Sleep -Milliseconds 100
 }
 for($i=0;$i -lt $Clients;$i++){
  $arguments=@('--bom-auto-connect','--bom-port',"$Port",'-screen-fullscreen','0','-screen-width','1280','-screen-height','720','-logFile',('"'+(Join-Path $session "player-$i.log")+'"'))
  $old=$env:BOM_TEST_HOST_TOKEN
  try{
   if($i -eq 0){$env:BOM_TEST_HOST_TOKEN=$key}else{Remove-Item Env:BOM_TEST_HOST_TOKEN -ErrorAction SilentlyContinue}
   $players+=Start-Process -FilePath $playerPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $playerPath) -PassThru
  }finally{if($null -ne $old){$env:BOM_TEST_HOST_TOKEN=$old}else{Remove-Item Env:BOM_TEST_HOST_TOKEN -ErrorAction SilentlyContinue}}
 }
 Write-Output "Local server: 127.0.0.1:$Port. The first window is the host."
 Write-Output 'A/D or arrows move; Space jumps; Esc opens the menu. The host can select Elimination there.'
 Write-Output "Logs: $session"
 while(!$players[0].WaitForExit(1000)){if($server.HasExited){break}}
 if(!$server.WaitForExit(6500)){throw 'The host window closed before the server completed its shutdown.'}
}finally{
 # This utility owns only this exact server process; it never stops an Editor
 # or a pre-existing server. Other player windows retain their disconnect menu.
 if($server -ne $null -and !$server.HasExited){$server.Kill();$server.WaitForExit()}
}
