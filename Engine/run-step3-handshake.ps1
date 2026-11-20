# Windows PowerShell 5.1; run from BOM root with Odin on PATH.
# Loopback-only app Hello/roles regression, including intentional rejection.
param([int]$Port = 47380)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force build, 'evidence/step3-auth' | Out-Null
Write-Host 'Building step-3 application handshake...'
& odin build src '-out:build/BOM.exe'
if ($LASTEXITCODE -ne 0) { throw "Odin build failed: $LASTEXITCODE" }
$root = Join-Path $PSScriptRoot 'evidence/step3-auth'
$exe = Join-Path $PSScriptRoot 'build/BOM.exe'
$serverLog = Join-Path $root 'server.log'
$serverErr = Join-Path $root 'server.err'
$rejectLog = Join-Path $root 'rejected.log'
$rejectErr = Join-Path $root 'rejected.err'
$hostLog = Join-Path $root 'host.log'
$hostErr = Join-Path $root 'host.err'
# Test-only secret; never use this as a real Internet hosting token.
$token = 'test-only-not-for-public-use-2026'
$server = $null
try {
    $server = Start-Process -FilePath $exe -ArgumentList @('--server','--port',"$Port",'--seconds','25','--host-token',$token) -PassThru -RedirectStandardOutput $serverLog -RedirectStandardError $serverErr
    Start-Sleep -Seconds 1
    Write-Host 'Checking that an incompatible version is rejected...'
    $bad = Start-Process -FilePath $exe -ArgumentList @('--bot-client',"127.0.0.1:$Port",'--seconds','5','--bad-version') -PassThru -Wait -RedirectStandardOutput $rejectLog -RedirectStandardError $rejectErr
    $badOutput = (Get-Content $rejectLog -Raw -ErrorAction SilentlyContinue) + (Get-Content $rejectErr -Raw -ErrorAction SilentlyContinue)
    if ($badOutput -notmatch 'version mismatch') { throw 'Bad-version client did not receive explicit rejection' }
    Write-Host 'Checking token owner receives HOST role and a replicated scene...'
    $hostProcess = Start-Process -FilePath $exe -ArgumentList @('--bot-client',"127.0.0.1:$Port",'--seconds','7','--host-token',$token) -PassThru -Wait -RedirectStandardOutput $hostLog -RedirectStandardError $hostErr
    $hostText = Get-Content $hostLog -Raw
    if ($hostText -notmatch 'BOT done: frames=([1-9][0-9]*) structures=([1-9][0-9]*) errors=0') { throw 'Host client did not complete with frames and structure' }
    # A normal bot exits without sending an explicit Disconnect. Server detects
    # it via the existing 5-second transport timeout, then exits 5 seconds later.
    $server.WaitForExit(25000) | Out-Null
    if (-not $server.HasExited) { throw 'Server did not exit after host timed out' }
    $serverText = Get-Content $serverLog -Raw
    if ($serverText -notmatch 'HELLO REJECT client=[0-9]+ reason=version mismatch') { throw 'Server lacks version-rejection record' }
    if ($serverText -notmatch 'HELLO OK client=[0-9]+ role=HOST') { throw 'Server did not grant host role' }
    if ($serverText -notmatch 'HOST left; server will exit in 5s') { throw 'No host-left notice' }
    if ($serverText -notmatch 'SERVER host-left shutdown') { throw 'No host-left shutdown' }
    Write-Host 'PASS: wrong version rejected, authorized host joined, host-left shutdown completed.'
    Get-Content $serverLog | Where-Object { $_ -match 'HELLO|HOST|SERVER final' }
} finally {
    if ($null -ne $server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    Write-Host "Logs: $root"
}
