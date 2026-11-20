# G-N5: client native update cost on the G1 Bridge collapse

Headless repro. A real `BOM-server.exe` runs the G1 Bridge layout. A native client drives the same
`bomcore` FFI entry points Unity calls (`bom_client_update`, then acquire and release a sample), over
loopback UDP at 60 fps. The client is the host and sends scripted blasts in the air pockets of the bays.

```powershell
odin build src/server -o:speed -out:build/BOM-server.exe
odin build benchmarks/client-update-g1 -o:speed -out:build/client-update-g1.exe
$layout='C:\Users\jblic\Desktop\Bomb-integration\integration\fixtures\levels-g1\BridgeLevel.json'
$token='g-n5-bench-host-token-0001'
Start-Process .\build\BOM-server.exe -ArgumentList '--port','47920','--layout',$layout,'--seconds','60','--host-token',$token
.\build\client-update-g1.exe 47920 $token 30 '5:-3.2,6.6|9:3.2,6.6|13:-9.7,6.6|17:9.7,6.6' out.csv
```

The client prints p50, p95, p99 and max of the per-call `bom_client_update` time, for all frames and for
the blast window. The blast window is the frames from 0.5 s before to 3 s after each revision change, as in
G1 section 6.3. It also writes one CSV row per frame.

Blast positions are air, not solid: a blast that starts inside solid is rejected. The four positions are
between the lower deck (top y = 5.25) and the middle girder (bottom y = 8.12), at x = ±3.2 and ±9.7.
The run uses the wall clock, so the collapse differs between runs. Compare pooled runs, not single runs.

## Prediction flips

The client also prints `prediction_flips` and `per_100s`: the frames where the own player leaves Predicting, which is
what the G2b Unity logs count as flips. Pass the Yard or Tower layout from `integration/fixtures/levels` to measure the
other maps; blasts in air near the spawn, for example Yard `'5:2,7.2|9:-8,7.2|13:5,7.2|17:-12,7.2'` and Tower
`'5:6,21.5|9:-7,21.5|13:8,21.5|17:-9,21.5'`. The native log lines `PREDICTION mode=...` give the same count with reasons.
