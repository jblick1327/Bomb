[CmdletBinding()]
param([switch]$Play,[ValidateRange(1,65535)][int]$Port=32000,[string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json'))
$ErrorActionPreference='Stop'
if(!$Play){throw 'Use -Play to open the interactive Unity native-client demo.'}
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
$server=if($config.PSObject.Properties.Name -contains 'ServerExecutable'){$config.ServerExecutable}else{Join-Path $config.OdinRoot 'build/BOM-server.exe'};$player=$config.UnitySlicePlayer
if(!(Test-Path -LiteralPath $server) -or !(Test-Path -LiteralPath $player)){throw 'Build the native server and Unity Mono slice before starting the demo.'}
$logs=Join-Path (Split-Path -Parent $PSScriptRoot) ('evidence/local/demo-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
New-Item -ItemType Directory -Path $logs -Force|Out-Null
$bytes=New-Object byte[] 24;$rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
$token=[Convert]::ToBase64String($bytes);$priorToken=$env:BOM_TEST_HOST_TOKEN;$ownedServer=$null;$ownedPlayer=$null
try {
 $ownedServer=Start-Process -FilePath $server -ArgumentList @('--port',"$Port",'--host-token',$token) -WorkingDirectory $config.OdinRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'server.log') -RedirectStandardError (Join-Path $logs 'server-errors.log')
 $env:BOM_TEST_HOST_TOKEN=$token
 $ownedPlayer=Start-Process -FilePath $player -ArgumentList @('--bom-port',"$Port",'-screen-fullscreen','0','-logFile',('"'+(Join-Path $logs 'unity.log')+'"')) -WindowStyle Normal -PassThru
 $env:BOM_TEST_HOST_TOKEN=$priorToken
 Write-Output 'Native server and Unity client running. A/D or arrows move, Space jumps, left-click blasts. Close the game to stop this demo.'
 $ownedPlayer.WaitForExit()
} finally {
 $env:BOM_TEST_HOST_TOKEN=$priorToken
 if($ownedServer -and !$ownedServer.HasExited){Stop-Process -Id $ownedServer.Id -Force}
}
