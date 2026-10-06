# Bomb

A side-view arena prototype: falling bombs cut through 3D ground, and touching a
blast kills the player. All movement and damage use XY; terrain is extruded along Z.
Boundaries are invisible and indestructible. The fixed camera tilts downward slightly.

## Start here

1. Open this folder with **Unity 6000.2.14f1** (Unity Hub reads `ProjectSettings/ProjectVersion.txt`).
2. Let Unity restore the pinned packages and import the assets.
3. Choose **Arena → Open Arena Scene**, then press Play.

| Input | Action |
| --- | --- |
| A/D, left/right arrows, gamepad left stick | Move |
| Space, W, up arrow, gamepad south button | Jump |
| B | Drop a bomb at a random horizontal position |
| R | Restart: restore ground, respawn, clear bombs and effects |

## Where to change things

The scene owns tuning. Select these objects in the Hierarchy:

| Object / component | Settings and responsibility | Code |
| --- | --- | --- |
| Arena / Arena Layout | Shared dimensions, ground fill, boundary geometry | [ArenaLayout](Assets/Game/Arena/ArenaLayout.cs) |
| Player / Player Controller | Speed, jump height, gravity, jump assistance | [ArenaPlayerController](Assets/Game/Player/ArenaPlayerController.cs) |
| Bomb System / Bomb Dropper | Crater shape and radius, lethal radius, drop and visuals | [BombDropper](Assets/Game/Bombs/BombDropper.cs) |
| Bomb System / Arena Session | Death and restart; scene references only | [ArenaSession](Assets/Game/Arena/ArenaSession.cs) |
| Main Camera / Arena Camera | Tilt and frame padding; fits the whole arena | [ArenaCamera](Assets/Game/Arena/ArenaCamera.cs) |
| Arena / Floor | Terrain mesh and collision; dimensions come from Arena Layout | [DestructibleGround](Assets/Game/Terrain/DestructibleGround.cs) |
| Arena HUD | Controls and death message; listens to session changes | [ArenaHud](Assets/Game/UI/ArenaHud.cs) |

Bomb Dropper creates each `FallingBomb`; its first collision calls `Explode`.
That carves the ground, checks the player's capsule against the **lethal radius**,
and creates `BombBlastVisual`. The ring grows to the lethal radius. **Crater radius**
controls the ground cut independently. Box uses it as a base half-size.

Inspector foldouts separate detail, drop, visuals, and scene references. Tooltips
explain less obvious settings. Code defaults apply to new components; the saved
scene values are the current gameplay tuning.

See [Gameplay reference](Docs/GameplayReference.md) for agreed turf, crater, and debris behavior.

## Project map

- `Assets/Game/`: our game. Runtime code is grouped by feature; `Editor/` contains
  Inspectors, setup, checks, and previews. `Scenes/`, `Materials/`, and `Geometry/`
  hold the game assets. `GroundMesh.asset` is the saved initial ground mesh.
- `Assets/Settings/`: rendering configuration and the template Input Actions asset.
  Gameplay currently reads Input System devices directly.
- `Assets/TextMesh Pro/`: imported font resources. `Assets/Samples/URP/`: retained
  template scene and tutorial, separate from the game.
- `Packages/` and `ProjectSettings/`: shared dependencies and Unity configuration.

## Contributing

Work in the relevant feature folder. Keep tuning on its owning component and
dimensions in Arena Layout. Its geometry lookup uses the existing Arena child
names; update those lookups if renaming boundary objects. Move assets in Unity so their `.meta` GUIDs
survive; commit assets with their `.meta` files. Keep editor tools under `Editor/`.

After a change, open the Arena scene, enter Play mode, and choose **Arena → Checks
→ Run All**. Read the Console result and try the affected gameplay. These checks
use the baseline arena tuning. See [Checks](Docs/Checks.md) for individual and stress runs.

**Arena → Rebuild Scene References** repairs the existing scene's wiring, resets
initial ground and player position, and saves the scene. Use it after layout or
wiring changes in Edit mode; it preserves gameplay tuning.

Git tracks source assets, packages, settings, and documentation. Generated folders
and local IDE settings are ignored. Use a branch per change and review the scene
diff alongside code. To enable Unity's scene/prefab merge driver after cloning,
run `unity vcs merge-setup` if the Unity CLI is installed.
