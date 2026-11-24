# Two-machine LAN test

Goal: one machine hosts the game server, a second machine joins over the local network, and both see the same yard,
a fracture, a round and a reconnect. Not yet run by anyone: this guide is the procedure for the first real run.

## What you need
- Two Windows 10/11 x64 PCs on the same network (wired or same Wi-Fi, no "guest/isolated" network).
- The release folder `BOM-Windows` copied to **both** machines (same build; check `manifest.json` hashes match).
- Windows PowerShell 5.1 (built in) or PowerShell 7. No Unity or Odin install is needed.

## 1. Host machine (machine A)
1. Allow the server through the firewall, once, in an **Administrator** PowerShell (adjust the path):
   ```powershell
   New-NetFirewallRule -DisplayName "BOM server (UDP 47380)" -Direction Inbound -Protocol UDP -LocalPort 47380 `
     -Program "C:\path\to\BOM-Windows\Server\BOM-server.exe" -Profile Private -Action Allow
   ```
   If Windows labels your network "Public", set it to Private (Settings > Network) or add `-Profile Any`.
2. Start the host: `./Launch-Bom.ps1 -Lan -Clients 1` (`-Bind 0.0.0.0` does the same as `-Lan`; add `-Backend IL2CPP` to test that build).
   The window that opens is the **host**. The console prints `LAN game on UDP port 47380 ... enter one of these addresses`;
   note the address that starts like your network (for example 192.168.x.x).

## 2. Guest machine (machine B)
1. Run `./Launch-Bom.ps1 -ClientOnly` (add `-Backend IL2CPP` to match, optional).
2. In the game, press **Esc**, enter machine A's address and port **47380**, and connect. Do not use host mode here.

## 3. What to do and observe
1. Both windows show the yard and both characters. Move on one machine and check the other shows it within about a
   quarter second, smoothly.
2. On the host, fire a blast at the stacked objects (host-only tool). Both screens must show the same pieces breaking and falling.
3. On the host, choose **Elimination** in the Esc menu. With at least two ready players a countdown of three seconds
   starts; play a round to the end. Both machines must show the same winner/draw and the round result.
4. On the guest, disconnect and reconnect from the menu; the yard and score must come back (the player rejoins as a spectator
   if a round is running).
5. On the host, restart the finished round; both screens must reset to the same yard.
6. Note anything that stutters, any frozen window, error message, or mismatch between the two screens, with the time it happened.

Pass: no disconnects you did not cause, both screens agree through steps 2-5, the guest connects first time.
If the guest cannot connect: check the address, that both are on the same subnet, that step 1 was done on A (try
temporarily turning off the firewall for Private networks to confirm it is the cause, then turn it back on and fix the rule).

## 4. Logs to send back
From **each** machine, zip the newest folder in `BOM-Windows\Logs\<timestamp>\`:
- Host: `server.log`, `server-errors.log`, `player-0.log`.
- Guest: `player-guest.log`.
Also send: the host's `ipconfig` output, which Windows network profile (Private/Public) was active, which backend you ran
(Mono/IL2CPP), and your notes from step 3 with times.

## 5. Clean up
Remove the firewall rule when done: `Remove-NetFirewallRule -DisplayName "BOM server (UDP 47380)"` (Administrator).
Closing the host window stops the server within about five seconds; guests then show the disconnect menu.
