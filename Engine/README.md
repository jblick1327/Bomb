# Odin destruction sandbox



A playable destruction yard built with Odin's bundled Box2D, raylib and raygui libraries. Draw rectangles from a layout-owned palette of four built-ins and up to four custom materials, test the layout, and explore its destruction with blasts or falling bombs.



## Run



Requires Odin on `PATH`, with compiled `vendor:box2d` and `vendor:raylib` libraries. Previously tested on Windows with Odin `dev-2026-05-nightly:ea5175d`.



```powershell

.\scripts\bom.ps1              # Run the sandbox

.\scripts\bom.ps1 Build        # Build an optimized executable

.\scripts\bom.ps1 Test         # Run the test suite

.\scripts\bom.ps1 Smoke        # Capture a hidden-window smoke test

.\scripts\bom.ps1 SmokeInput   # Exercise native input and widgets

.\scripts\bom.ps1 Soak         # Run the headless longevity check

```



The helper runs from the project root and creates `build/` and `output/`. Direct launches should also use the project root as their working directory.



## Play



The application starts paused in **Edit**, restoring `layouts/autosave.json` when valid. Choose Wood, Glass, Rubber or Stone (keys 1–4), then drag rectangles snapped to a 0.1-unit grid. The preview shows dimensions and any placement problem. Click **Test** or press Enter to simulate. **Layouts** opens the five embedded presets and saved layouts; Ctrl+S saves the next free `layouts/layout-NNN.json`. Drop a layout JSON file in either mode to load it. Authored changes autosave. F3 S/L independently saves and loads v4 World snapshots (v3 still loads) in `output/`. Settings include falling bombs, blast radius and outlines.



| Control | Action |

| --- | --- |

| Left drag in Edit | Preview and place a rectangle using the selected material |

| 1–4 in Edit | Select Wood / Glass / Rubber / Stone |

| Layouts / Ctrl+S in Edit | Presets and saved files / save current layout |

| Drop a layout .json | Load the first JSON file and return to Edit |

| M / Mortar toggle in Edit | Mark newly placed objects for breakable joints to touching objects and the floor |

| Right click in Edit | Remove the authored object under the cursor |

| Edit / Test button or Enter | Start a fresh test / restore the undamaged edit layout |

| A / D or left / right arrows in Test | Move |

| Space in Test | Jump, with a 0.1 second jump buffer and coyote window |

| Left click in Test | One blast at a valid cursor position |

| Mouse wheel over the world in Test | Adjust blast radius and power |

| R / Reset button in Test | Rebuild the same authored layout and seed |

| Tab / Escape / Settings button | Open settings and pause; close to resume |

| F3 in Test | Show every region outline, IDs, connections and inspection tools |



See [gameplay and defaults](docs/gameplay.md) for material presets, placement limits, inspection controls.





## Physics damage



Blasts and impacts can fracture the authored objects. See the [technical reference](docs/technical-reference.md#physics-damage) for the current damage rules and measured thresholds, and the [implementation guide](docs/implementation.md) for the source map and simulation details.



## Verification and cleanup



See [verification details](docs/verification.md) for coverage, output names and graphics requirements. [Historical evidence](evidence/README.md) contains preserved reports, captures and source snapshots.



```powershell

.\scripts\clean.ps1           # Preview generated build/ and output/ files

.\scripts\clean.ps1 -Apply    # Remove those directories

```



Move any snapshots or captures you want to retain into `evidence/` before cleaning. New evidence belongs with its report and related files; `build/` and `output/` are ignored by Git.



## Project layout



- [src/](src/) ? game code and tests in one Odin package.

- [scripts/](scripts/) ? run, build, test and cleanup helpers.

- [docs/](docs/) ? gameplay, implementation, verification, technical reference and historical plans.

- [benchmarks/recursive-blast-bench/](benchmarks/recursive-blast-bench/) ? standalone benchmark and recorded inputs.

- [evidence/](evidence/README.md) ? historical reports, captures and unique archives.



Mortar force breaking aggregates weld reactions across each body-pair seam. The seam keeps one `damage` value (seconds of excess capacity), saved on all member connections: each tick with ratio r >= 1 adds (r - 1) / 60, any tick below capacity resets it to 0, and the seam snaps when damage reaches `SEAM_TOUGHNESS = 0.4` s. Violent impacts therefore break a seam immediately while a one-tick constraint transient (for example a blast velocity resolved across a weld chain) does not; there is no tick count and no `r >= 2` shortcut. Snapshots store optional `damage`; a legacy `overload_ticks` is ignored on load. The blast rule (minimum connection strength at the seam midpoint) is unchanged. Reproduce calibration with `--calibrate-mortar` and the seed study with `--mortar-seeds`.



Material-library validation, fixture choices and Wood thickness measurements are in [report.md](report.md). Blast cover uses the previous default path; the COVER_SHORTCUTS compile switch has been removed.



Layouts save as canonical version 3 with custom materials, rotated rectangles/wedges and glue links. Version 1 and 2 layouts still load with their original authored state. Built-ins remain fixed; Wood now explicitly uses strip thickness 0.2. A World snapshot without strip_thickness retains the legacy 0.3 behavior. Use `--smoke-materials` for the native editor verification and three PNG captures.



Material fills now use a repeating procedural RGBA texture in build-time rest coordinates. Interface text uses embedded Inter Regular and SemiBold, with four DPI-aware font atlases; the SIL OFL licence is in `src/assets/fonts/OFL.txt`. See `report.md` for native pixel checks, unchanged simulation/layout bytes, frame timings and the screenshot pairs.

Build verification with `odin build src -o:speed -define:BOM_FRAME_BENCH=true -out:build/BOM.exe`. Use `--check-textures`, `--smoke-msaa`, `--capture-ui evidence/textures-ui/after`, `--capture-textures`, and `--bench-frames`. `SmokeInput` and `SmokeMaterials` also exercise the new controls.

Rotation, wedges and glue: in Edit, Q/E adjusts the next placement by 15 degrees, T switches Rect/Wedge, and G selects the glue tool. Click one object, then another or the floor; repeat a pair to unlink it. Escape or right-click cancels glue selection. Angled shapes and wedges within 0.3 m of a surface snap into contact when that placement is clear. Glue requires touching surfaces (within 0.001 m), and may fill a crevice up to 0.2 m. Delete an object to remove its links. `--check-shapes` runs the native editor, textured MSAA checks and demo captures under `evidence/rotation-glue/`.

Glue follow-up diagnostics: `--diagnose-demo` logs the original demo per tick (0-30), including seam body pairs, force ratios, per-seam damage, failure paths and brace displacement. It also prints `LIVE` lines at ticks 20 and 120. Optional SEAM_DIAG_NO_CONTACTS / SEAM_DIAG_ZERO_VELOCITY are diagnostic controls only. `--check-glue-followup` checks 4x MSAA, cream coverage and continuous ridge rendering, and writes the 600-tick / 20-tick (original blast (-3.8,0.5), radius 4) / ridge PNGs to `evidence/seam-toughness/`. Simulation, strengths and joint/contact settings remain unchanged.
