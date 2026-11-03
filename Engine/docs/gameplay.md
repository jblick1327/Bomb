# Gameplay and defaults

Current behavior reference. See the [README](../README.md) for setup and the [implementation](implementation.md) for solver details. Historical plans do not override these defaults.

The application opens in **Edit**, paused, with a clear building area above the destructible floor and an invulnerable capsule player. Choose Wood, Glass, Rubber or Stone in the bottom palette and drag rectangles into the world. Click **Test** (or Enter) to build and run the layout; walk, jump onto or push debris, aim outside a solid shape and click to blast. Ordinary gravity runs at a fixed 60 Hz with four Box2D substeps. The camera keeps the yard framed when the window resizes. Falling outside the yard returns the player to spawn.

The floor is authored as one 17-by-3 rectangle with a deterministic context, then pre-split at creation to cells no longer than 1 unit. Later damage still generates detail on demand. A connected ground section stays anchored while it retains an edge on the bottom support plane; sections cut free use ordinary dynamic physics. A thin indestructible base underneath spans beyond the playable edges and catches the player, bombs and rubble above the bottom of the screen. The fixed view includes the pit bottom. Aim just above the surface to excavate it; solid floor interiors follow the same invalid-origin rule as authored objects. Reset repeats the pre-split floor. Use this destructible-floor yard for subsequent destruction-feel comparisons.

| Control | Action |
| --- | --- |
| Left drag in Edit | Preview and place a rectangle using the selected material |
| Right click in Edit | Remove the authored object under the cursor |
| Edit / Test button or Enter | Start a fresh test / restore the undamaged edit layout |
| A / D or left / right arrows in Test | Move |
| Space in Test | Jump, with a 0.1 second jump buffer and coyote window |
| Left click in Test | One blast at a valid cursor position |
| Mouse wheel over the world in Test | Adjust blast radius and power |
| R / Reset button in Test | Rebuild the same authored layout and seed |
| Tab / Escape / Settings button | Open settings and pause; close to resume |
| F3 in Test | Toggle IDs, connections, counts and inspection tools |

The aiming circle shows the active blast radius. A red cross and message mark origins inside or on live logical outlines; those blasts are suppressed. UI clicks do not blast the world. The settings panel pauses physics and player actions without accumulating simulation time.

In Settings, switch **Manual blasts / Falling bombs** to choose the explosion source immediately, without resetting the yard. Falling bombs spawn at random horizontal positions across the yard every 1ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“2.5 seconds. Each is an ordinary circle body that collides with the floor, debris and player. Its one-second fuse starts on first landing on a supporting surface, including authored objects; airborne time and side contacts do not start the fuse. A red countdown ring marks a lit fuse. The body disappears when it explodes at its current position, using the current blast radius, with a brief expanding flash. Manual placement and its aiming circle are disabled in this mode. Returning to Manual clears pending bombs. Settings pauses drops, fuses and flashes along with physics. Reset clears bombs and repeats the applied seed's drop sequence, independently of destruction generation.

Mode and radius changes are immediate, including inside Settings. The **Outline width (px)** slider adjusts physical piece silhouettes and flexible broken-bond crack lines from 0 (no outline), through fractional pixel widths, to the original thick 2-pixel outline. The width starts at 2 and stays set across resets and Edit/Test transitions; drag previews and inspection IDs/links remain available independently. Objects use fixed palette presets; global material sliders do not override them. The initial setup uses manual blasts, seed 42, radius 5.0 and impulse scale 0.2. The independent ground uses Stone's Chunks recipe, strengths 35/20 and flexibility 0.

The authored layout is a small in-memory list of rectangle bounds, material and stable identity, separate from damaged geometry. Entering Test, R during Test, and returning to Edit rebuild the scene without changing that list. Separate objects collide without acquiring shared logical connections. Editing pauses physics, bombs and fuses. Dragging onto UI cancels placement. Rectangles must be at least 0.2 units wide/high, stay inside x [-7.5,8.5], y [0,4.8], and avoid existing rectangle interiors and the player's spawn footprint. Touching rectangle edges are allowed. There is no saving, loading, pinning, rotation or undo for authored layouts; application close discards them.

| Palette material | Breakup | Fragment / connection strength | Flexibility | Impact scale |
| --- | --- | ---: | ---: | ---: |
| Wood | Strips (`splinter` recipe) | 28 / 22 | 0 | 1 |
| Glass | Shards (`shatter` recipe), no boundary jitter | 16 / 12 | 0 | 1 |
| Rubber | Connected terminal grid | 45 / 90 | 0.5 | 0 |
| Stone | Chunks (`chunk` recipe) | 35 / 20 | 0 | 1.6 |

These provisional gameplay presets use the existing Material properties and shared solver. **Chunks / Strips / Shards** describe typical output, not strict geometric categories or toughness. Non-rubber objects pre-split their authored rectangle with the material recipe toward 1 unit in bounding extent, retaining cells where grain prevents a legal cut; future damage generates further detail on demand. Each object receives a deterministic context derived from seed 42 and its stable authored identity (in a separate namespace from the ground); deleting another object does not reseed it.

Rubber uses one construction setting, `RUBBER_CELL_SIZE = 0.4`: divide each rectangle into a uniform fitted grid whose cells are at most approximately that size. Each cell is an ordinary dynamic rigid body, joined to its grid neighbors by the existing soft welds. Cells have seed zero: they remain live until failure, without recursively replacing their deformation mesh. Links are only internal to that object. Rubber cannot be terrain-anchored because authored objects lie above the ground and never have reference edges on the bottom support plane.

Material limitations: this is not a continuous elastic or volume-preserving material model. Rubber bends/stretches at soft joints while its cells remain rigid; objects small enough for a single cell cannot bend internally; blasts can remove finite-strength cells and split the grid. Impact scale zero makes physical impacts and bond stress harmless to Rubber; soft joints still allow deformation. Wood/glass/stone contact damage uses the velocity change implied by approach speed and the connected-piece mass ratio, on the same scale as blasts. Static anchored ground takes no contact damage. Flat drops follow the [README threshold table](../README.md#physics-damage); rotation and connected meshes can differ. Strong blasts can erase most of a brittle object. The mass/density, friction, damping and center-applied blast impulse policies are unchanged.

With F3 enabled, every region outline is visible at the same slider width: right click selects, Delete or Ctrl+click directly removes a region, Shift+click or X near an anchor breaks a connection, J toggles links, V toggles the cosmetic surface, S saves and L loads `output/snapshot.json`. D and Space retain movement and jump in inspection mode. Diagnostic snapshots contain simulation geometry, not the authored editor layout.


Chunks and Strips cut bent, shallow-concave outlines directly. Cuts and shared seam bends must preserve simple outlines, area and the minimum fragment width (0.1 in the yard). Shards retain deliberate triangulation and straight seams. The resulting rims and Wood splits are coarser than historical captures; tiny internal hairline regions are no longer generated.

Fractional outlines below 1 px use a continuous 1 px stroke with proportional alpha. With outlines off, fill-coloured 1 px seals still close subpixel silhouette/crack gaps. Seals do not stroke seams inside a rigid piece, bonded flexible seams, or static/static seams and wider openings remain visible. Outline strokes are drawn last so seals cannot cover them.
