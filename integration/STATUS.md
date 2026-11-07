# Integration checkpoint

M0–M5 passed. M6 is in progress; M7–M9 are pending. The full integration is not complete.

M5 uses native commit 9c6278f01fd9182bb859a33203a53a6984ba07d7, ABI 1.2 / protocol 4 / canonical 2. Both required 600-second static prediction profiles passed, with genuine local stepping on every measured frame and zero snaps or conservative intervals. The 100 ms / 60 FPS run measured p95 native response 17.11 ms and p99 correction 0.002 units; 200 ms / 30 ms jitter / 5% loss at measured 143.92 FPS measured 14.27 ms and 0.002 units. Actual Unity URP response p95 was 21.86 ms against 35.33 ms. Two-Unity Mono prediction on/off scenarios matched all 80/100 expected hashes, at timeScale zero. Moving/rotating contact, fracture-history invalidation and conservative recovery fixtures passed. See evidence/M5/summary.json.

M0–M4 evidence remains under each milestone directory: original yard/HUD audit and captures; byte-preserving native extraction; independent C/.NET ABI checks; ten-minute real UDP; Mono/IL2CPP live clients; geometry/pivot and Editor lifecycle checks. Original content verification covers 605 protected files. Four package metadata deletions predate this work and remain unstaged.

The source roots remain separate. source-lock.json identifies the shipped DLL; source patches reconstruct the native changes from the preserved ZIP import. Historical native evidence dirt is unrelated and must remain unstaged. Do not reset either repository.

M6 acceptance runs now pass on native commit f98dd0104fc51bb44206669f9660e3d433762dbb, ABI 1.3 / protocol 5 / canonical 3. Layout v4 constructs the actual yard with 16 active sources, 17 parts and 4,615 initial cells. Motion/damage policies, provenance, atomic catalogs, versioned configuration, bounds/spawns, source IDs above 2^53, standalone direct-reference registry, missing-art fallback, wrong-manifest rejection, late join/reset/reconnect and final C/.NET ABI checks pass. The full native suite passes 220 game, 27 transport, 51 shared and 18 ffi tests. The published 605-file content check passed in evidence/M0/Test-Content-20261107T124618188Z.json. See evidence/M6/summary.json.

The new yard scene and SDK use protocol 5. The separately preserved M5 interactive demo remains protocol 4. Test-UnityYard.ps1 builds/tests the authored yard; -MissingArt and -RejectManifest reproduce those standalone gates. Test-UnitySlice.ps1 now writes new validation builds under build/validation to protect the frozen M5 demo.

M7 source-mesh clipping/caps, M8 elimination and presentation infrastructure, and M9 hardening/performance/current IL2CPP/final soak remain required. Dynamic yard prediction currently falls back when moving collision history is unavailable and can make gross correction snaps; the passing M5 static profile does not imply dynamic-yard latency/correction acceptance. This remains active hardening work.
