# Integration checkpoint

M0–M5 passed. M6 is in progress; M7–M9 are pending. The full integration is not complete.

M5 uses native commit 9c6278f01fd9182bb859a33203a53a6984ba07d7, ABI 1.2 / protocol 4 / canonical 2. Both required 600-second static prediction profiles passed, with genuine local stepping on every measured frame and zero snaps or conservative intervals. The 100 ms / 60 FPS run measured p95 native response 17.11 ms and p99 correction 0.002 units; 200 ms / 30 ms jitter / 5% loss at measured 143.92 FPS measured 14.27 ms and 0.002 units. Actual Unity URP response p95 was 21.86 ms against 35.33 ms. Two-Unity Mono prediction on/off scenarios matched all 80/100 expected hashes, at timeScale zero. Moving/rotating contact, fracture-history invalidation and conservative recovery fixtures passed. See evidence/M5/summary.json.

M0–M4 evidence remains under each milestone directory: original yard/HUD audit and captures; byte-preserving native extraction; independent C/.NET ABI checks; ten-minute real UDP; Mono/IL2CPP live clients; geometry/pivot and Editor lifecycle checks. Original content verification covers 605 protected files. Four package metadata deletions predate this work and remain unstaged.

The source roots remain separate. source-lock.json identifies the shipped DLL; source patches reconstruct the native changes from the preserved ZIP import. Historical native evidence dirt is unrelated and must remain unstaged. Do not reset either repository.

M6 foundation: exact-u64 authoring registry, prefab/duplicate/reopen tests, unreadable mesh preprocessing and mirrored affine transform validation passed in the disposable Editor. A bounded native v4 decoder validates identifiers, bounds, spawn/bomb data, materials, concave/compound geometry and anchors; it is not yet wired into application loading. Authoritative provenance, physics/damage policy, reliable catalog and exported yard remain required work. The current demo stays on the frozen protocol-4 server/client until the coordinated M6 wire/ABI migration passes.
