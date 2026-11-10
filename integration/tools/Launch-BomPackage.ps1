[CmdletBinding()]
param([ValidateSet('Mono','IL2CPP')][string]$Backend='Mono',[ValidateRange(1,2)][int]$Clients=2,[ValidateRange(1,65535)][int]$Port=47380,[ValidateSet('127.0.0.1','0.0.0.0')][string]$Bind='127.0.0.1')
$ErrorActionPreference='Stop'
$package=$PSScriptRoot
$serverPath=Join-Path $package 'Server/BOM-server.exe';$playerPath=Join-Path $package "$Backend/BombPerformance.exe";$layout=Join-Path $package 'yard.json'
foreach($path in @($serverPath,$playerPath,$layout)){if(!(Test-Path -LiteralPath $path)){throw "Missing package file: $path"}}
$session=Join-Path $package ('Logs/'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'));New-Item -ItemType Directory -Path $session -Force|Out-Null
$key=[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24));$server=$null;$players=@()
try{
 $server=Start-Process -FilePath $serverPath -ArgumentList @('--bind',$Bind,'--port',"$Port",'--layout',('"'+$layout+'"'),'--host-token',$key) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $session 'server.log') -RedirectStandardError (Join-Path $session 'server-errors.log') -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(90)
 while(!((Get-Content (Join-Path $session 'server.log') -Raw -ErrorAction SilentlyContinue) -match 'BOM staging server listening')){
  if($server.HasExited){throw "Server could not start. Check $session"};if([DateTime]::UtcNow -gt $deadline){throw "Server startup timed out. Check $session"};Start-Sleep -Milliseconds 100
 }
 for($i=0;$i -lt $Clients;$i++){
  $info=[Diagnostics.ProcessStartInfo]::new($playerPath);$info.UseShellExecute=$false;$info.WorkingDirectory=Split-Path -Parent $playerPath;$info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Normal
  foreach($arg in @('--bom-auto-connect','--bom-port',"$Port",'-screen-fullscreen','0','-screen-width','1280','-screen-height','720','-logFile',(Join-Path $session "player-$i.log"))){$info.ArgumentList.Add($arg)}
  $null=$info.Environment.Remove('BOM_TEST_HOST_TOKEN');if($i -eq 0){$info.Environment['BOM_TEST_HOST_TOKEN']=$key};$players+=[Diagnostics.Process]::Start($info)
 }
 Write-Output "Local game: 127.0.0.1:$Port. First window is host. Esc opens the menu. Logs: $session"
 while(!$players[0].WaitForExit(1000)){if($server.HasExited){break}}
 if(!$server.WaitForExit(6500)){throw 'The host closed before server shutdown completed.'}
}finally{if($server -ne $null -and !$server.HasExited){$server.Kill();$server.WaitForExit()}}
