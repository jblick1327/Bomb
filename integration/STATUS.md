# Integration checkpoint

M0–M8 passed. M9 is in progress. The full integration is not complete.

M8 native checkpoint: 57c05fd8f9de669e4c8410399c4667a4b75c45af; ABI 1.4 / protocol 6 / canonical topology 3.
Native library SHA-256: a7cd642cad8c2de06aaf3f17e6dfdc04082c3911d4a1ffdac216c7625ae8de25. Unity runtime SHA-256: 82933f616aa8884e4929372fb453b9d4d7c905e32df18d29e245040933fb51e5.
Original game 220, shared core 74 and ABI 19 tests pass; independent C/.NET checks
cover 23 layouts and 31 exports. Final real UDP and two-Unity yard/draw gates pass.
The exact final players agree with the Odin observer, retain results over reconnect,
restart with a new epoch/round, drive Claymate from native movement/jumps and avoid
duplicated effects. All expected final world hashes matched. See evidence/M8/summary.json.

Original Unity content: 605 protected files passed the last content check. Four
URP package metadata deletions predate this task and remain unrelated/unstaged.
Prior M0–M7 evidence and frozen M5/M6/M7 players/servers remain preserved.

M9 next: independent code review; full mixed-client/loss/reset/geometry regression;
bounded lifetimes and zero stable-path allocation; 500/1000-cell profiling with 200
moving entities; split costly mesh operations; current Mono/IL2CPP and symbols;
reproducible wrappers/package; final 30-minute real-process soak with at least ten
resets. The large original yard and dynamic prediction still have known performance
costs. Do not treat M8 correctness as passing those remaining performance gates.
