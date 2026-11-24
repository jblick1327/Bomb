# Windows PowerShell 5.1. Real-UDP host-only upload and reset checks.
# This intentionally uses localhost until the full UI and safety review.
param([int]$Port = 47380, [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force build, 'evidence/step3-host-control' | Out-Null
if (-not $SkipBuild) {
    Write-Host 'Building BOM with host layout commands...'
    & odin build src '-out:build/BOM.exe'
    if ($LASTEXITCODE -ne 0) { throw "Odin build failed: $LASTEXITCODE" }
}
$root = Join-Path $PSScriptRoot 'evidence/step3-host-control'
$exe = Join-Path $PSScriptRoot 'build/BOM.exe'
$token = 'local-test-host-token-not-for-internet'
$serverProcess = $null
$guestProcess = $null
$hostProcess = $null
try {
    Write-Host 'Launching server and two real-UDP clients...'
    $serverProcess = Start-Process -FilePath $exe -ArgumentList @('--server','--port',"$Port",'--seconds','35','--host-token',$token) -PassThru -RedirectStandardOutput (Join-Path $root 'server.log') -RedirectStandardError (Join-Path $root 'server.err')
    Start-Sleep -Seconds 1
    # Guest intentionally attempts two unauthorized mutations.
    $guestProcess = Start-Process -FilePath $exe -ArgumentList @('--bot-client',"127.0.0.1:$Port",'--seconds','12','--upload-layout','src/presets/bridge.json','--host-reset') -PassThru -RedirectStandardOutput (Join-Path $root 'guest.log') -RedirectStandardError (Join-Path $root 'guest.err')
    Start-Sleep -Seconds 1
    # HOST sends another valid preset, then resets that world.
    $hostProcess = Start-Process -FilePath $exe -ArgumentList @('--bot-client',"127.0.0.1:$Port",'--seconds','12','--host-token',$token,'--upload-layout','src/presets/tower.json','--host-reset') -PassThru -RedirectStandardOutput (Join-Path $root 'host.log') -RedirectStandardError (Join-Path $root 'host.err')
    if (-not $guestProcess.WaitForExit(30000)) { throw 'Guest did not finish' }
    if (-not $hostProcess.WaitForExit(30000)) { throw 'Host did not finish' }
    if (-not $serverProcess.WaitForExit(30000)) { throw 'Server did not finish' }
    $serverText = Get-Content (Join-Path $root 'server.log') -Raw
    $guestText = Get-Content (Join-Path $root 'guest.log') -Raw
    $hostText = Get-Content (Join-Path $root 'host.log') -Raw
    if ($serverText -notmatch 'LAYOUT REJECT client=\d+ reason=host only') { throw 'Guest layout upload was not denied' }
    if ($serverText -notmatch 'COMMAND REJECT client=\d+ reason=host only') { throw 'Guest reset was not denied' }
    if ($serverText -notmatch 'LAYOUT OK client=\d+ epoch=\d+ objects=\d+') { throw 'Host layout was not accepted' }
    if ($serverText -notmatch 'COMMAND OK client=\d+ op=1 epoch=\d+') { throw 'Host reset was not applied' }
    if ($guestText -notmatch 'BOT done: frames=[1-9]\d* structures=[1-9]\d* errors=0') { throw 'Guest replica did not complete' }
    if ($hostText -notmatch 'BOT done: frames=[1-9]\d* structures=[1-9]\d* errors=0') { throw 'Host replica did not complete' }
    if ($serverText -notmatch 'SERVER final hashes=([1-9]\d*) mismatches=0 unrecorded=0') { throw 'Server structure hash verification failed' }
    if ($guestText -notmatch 'APP RESULT kind=199 status=REJECT reason=host only') { throw 'Guest did not receive layout rejection' }
    if ($hostText -notmatch 'APP RESULT kind=199 status=OK reason=') { throw 'Host did not receive layout acceptance' }
    Write-Host 'PASS: guest denied, host upload + reset accepted, both replicas synchronized, hashes matched.'
    Get-Content (Join-Path $root 'server.log') | Where-Object { $_ -match 'LAYOUT|COMMAND|SERVER final|HOST' }
} finally {
    foreach ($p in @($guestProcess,$hostProcess,$serverProcess)) {
        if ($null -ne $p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force }
    }
    Write-Host "Logs: $root"
}
