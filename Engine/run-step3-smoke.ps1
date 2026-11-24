# Runs on the game's Windows machine where Odin is installed.
# Staging loopback test only: no public hosting, GUI, or roles implemented yet.
param([int]$Seconds = 30, [int]$Port = 47380, [switch]$SmokeOnly)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force build, 'evidence/step3-staging' | Out-Null
if (-not $SmokeOnly) {
  Write-Host 'Building BOM with staging real sockets...'
  & odin build src '-out:build/BOM.exe'
  if ($LASTEXITCODE -ne 0) { throw "Odin build failed: $LASTEXITCODE" }
  Write-Host 'Running parser and existing tests...'
  & odin test src
  if ($LASTEXITCODE -ne 0) { throw "Odin tests failed: $LASTEXITCODE" }
} elseif (-not (Test-Path (Join-Path $PSScriptRoot 'build/BOM.exe'))) {
  throw 'SmokeOnly requires an existing build/BOM.exe'
}
Write-Host 'Starting the headless UDP process on localhost...'
$serverLog = Join-Path $PSScriptRoot 'evidence/step3-staging/server.log'
$serverErr = Join-Path $PSScriptRoot 'evidence/step3-staging/server.err'
$guiLog = Join-Path $PSScriptRoot 'evidence/step3-staging/gui.log'
$guiErr = Join-Path $PSScriptRoot 'evidence/step3-staging/gui.err'
$botLog = Join-Path $PSScriptRoot 'evidence/step3-staging/bot.log'
$botErr = Join-Path $PSScriptRoot 'evidence/step3-staging/bot.err'
$server = Start-Process -FilePath (Join-Path $PSScriptRoot 'build/BOM.exe') -ArgumentList @('--server','--port',"$Port",'--seconds',"$($Seconds + 8)") -PassThru -RedirectStandardOutput $serverLog -RedirectStandardError $serverErr
try {
  Start-Sleep -Seconds 1
  $gui = Start-Process -FilePath (Join-Path $PSScriptRoot 'build/BOM.exe') -ArgumentList @('--hidden-client',"127.0.0.1:$Port",'--seconds',"$Seconds") -PassThru -RedirectStandardOutput $guiLog -RedirectStandardError $guiErr
  $bot = Start-Process -FilePath (Join-Path $PSScriptRoot 'build/BOM.exe') -ArgumentList @('--bot-client',"127.0.0.1:$Port",'--seconds',"$Seconds") -Wait -PassThru -RedirectStandardOutput $botLog -RedirectStandardError $botErr
  Write-Host "Bot exit code: $($bot.ExitCode)"
  Get-Content $botLog
  $gui.WaitForExit(15000) | Out-Null
  if (-not $gui.HasExited) { throw 'Hidden-window client did not exit' }
  # Start-Process -PassThru without -Wait sometimes yields a missing ExitCode
  # on Windows PowerShell 5.1. Use an explicit completion marker as well.
  $gui.Refresh()
  $guiExitCode = $gui.ExitCode
  if ($null -eq $guiExitCode) {
    Write-Host 'Hidden GUI exit code unavailable; checking completion log'
  } else {
    Write-Host "Hidden GUI exit code: $guiExitCode"
  }
  $guiLines = @(Get-Content $guiLog)
  $guiLines | ForEach-Object { Write-Host $_ }
  $guiDone = $guiLines | Where-Object { $_ -match '^BOT done: frames=\d+ structures=\d+ errors=\d+$' } | Select-Object -Last 1
  if ($null -eq $guiDone) { throw 'Hidden-window client did not report a completed smoke test' }
  if ($guiDone -match '^BOT done: frames=(\d+) structures=(\d+) errors=(\d+)$') {
    $guiFrames = [int]$Matches[1]
    $guiStructures = [int]$Matches[2]
    $guiErrors = [int]$Matches[3]
  } else { throw 'Malformed hidden-window completion summary' }
  if ($guiFrames -le 0 -or $guiStructures -le 0 -or $guiErrors -ne 0) {
    throw 'Hidden-window client reported no frames/structures or errors'
  }
  if ($null -ne $guiExitCode -and $guiExitCode -ne 0) { throw 'Hidden-window client exited with an error' }
  if ($bot.ExitCode -ne 0) { throw 'Real-socket bot smoke failed' }
  $server.WaitForExit(15000) | Out-Null
  if (-not $server.HasExited) { throw 'Server did not exit after --seconds' }
  $server.Refresh()
  if ($null -ne $server.ExitCode -and $server.ExitCode -ne 0) { throw 'Staging server exit code nonzero' }
  $report = (Get-Content $serverLog | Where-Object { $_ -match '^SERVER final hashes=(\d+) mismatches=(\d+) unrecorded=(\d+)' } | Select-Object -Last 1)
  if (-not $report) { throw 'Server did not report final canonical hash counts' }
  if ($report -match 'hashes=(\d+) mismatches=(\d+) unrecorded=(\d+)') {
    $hashCount = [int]$Matches[1]
    $hashMismatch = [int]$Matches[2]
    $hashUnrecorded = [int]$Matches[3]
  } else { throw 'Bad hash report' }
  Write-Host $report
  if ($hashCount -eq 0 -or $hashMismatch -ne 0 -or $hashUnrecorded -ne 0) { throw 'Canonical hash check failed' }
} finally {
  if ($null -ne $gui -and -not $gui.HasExited) { Stop-Process -Id $gui.Id -Force }
  if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
  Write-Host "Logs: $serverLog, $serverErr, $guiLog, $guiErr, $botLog, $botErr"
}
