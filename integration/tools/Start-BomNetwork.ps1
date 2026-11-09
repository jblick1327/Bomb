[CmdletBinding()]
param([ValidateRange(1,65535)][int]$Port=47380,[ValidateRange(1,2)][int]$Clients=2)
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
$serverPath=Join-Path $integration 'build/M8-native/BOM-server.exe'
$playerPath=Join-Path $integration 'build/Network-Mono/BombNetwork.exe'
$layoutPath=Join-Path $integration 'fixtures/network-yard/yard.json'
foreach($path in @($serverPath,$playerPath,$layoutPath)){if(!(Test-Path -LiteralPath $path)){throw "Missing local build: $path"}}
$session=Join-Path $integration ('build/sessions/'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
$null=New-Item -ItemType Directory -Path $session -Force
$key=[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
$server=$null;$players=@()
try{
 $server=Start-Process -FilePath $serverPath -ArgumentList @('--port',"$Port",'--layout',('"'+$layoutPath+'"'),'--host-token',$key) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $session 'server.log') -RedirectStandardError (Join-Path $session 'server-errors.log') -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(60)
 while(!((Get-Content (Join-Path $session 'server.log') -Raw -ErrorAction SilentlyContinue) -match 'BOM staging server listening')){
  if($server.HasExited){throw "Server could not start. Check $session"}
  if([DateTime]::UtcNow -gt $deadline){throw "Server startup timed out. Check $session"}
  Start-Sleep -Milliseconds 100
 }
 for($i=0;$i -lt $Clients;$i++){
  $info=[Diagnostics.ProcessStartInfo]::new($playerPath);$info.UseShellExecute=$false;$info.WorkingDirectory=Split-Path -Parent $playerPath
  $info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Normal
  $info.ArgumentList.Add('--bom-auto-connect');$info.ArgumentList.Add('--bom-port');$info.ArgumentList.Add("$Port")
  $info.ArgumentList.Add('-screen-fullscreen');$info.ArgumentList.Add('0');$info.ArgumentList.Add('-screen-width');$info.ArgumentList.Add('1280');$info.ArgumentList.Add('-screen-height');$info.ArgumentList.Add('720')
  $info.ArgumentList.Add('-logFile');$info.ArgumentList.Add((Join-Path $session "player-$i.log"))
  $null=$info.Environment.Remove('BOM_TEST_HOST_TOKEN');if($i -eq 0){$info.Environment['BOM_TEST_HOST_TOKEN']=$key}
  $players+=[Diagnostics.Process]::Start($info)
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
