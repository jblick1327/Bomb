@echo off
rem Host PC, once: lets other Tailscale PCs reach the game server (UDP 47380) even when Windows marks the
rem Tailscale network as Public. Only tailnet addresses (100.64.0.0/10) are allowed. Asks for administrator rights.
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -Command "if (Get-NetFirewallRule -DisplayName 'BOM server (Tailscale)' -ErrorAction SilentlyContinue) { 'The rule is already there.' } else { New-NetFirewallRule -DisplayName 'BOM server (Tailscale)' -Direction Inbound -Protocol UDP -LocalPort 47380 -RemoteAddress 100.64.0.0/10 -Action Allow -Profile Any | Out-Null; 'Done: other Tailscale PCs can join this PC on port 47380.' }"
pause
