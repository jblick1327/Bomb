# Bomb + Odin: start here

This repo now has the Odin engine in it. Physics, destruction, bombs, players and online play run in Odin;
Unity draws what Odin sends and passes on your input. Darryn's levels, art, menus, shop and offline mode are
still here and work as before. This page is the short version; ask J about anything it doesn't answer.

## Play it
1. Open the repo folder in **Unity 6000.2.14f1**, open `Assets/Game/Scenes/MainMenuScene.unity` and press Play.
2. **Play** (offline) is Darryn's local mode. It still uses Unity physics, not Odin, for now.
3. **Online → Host** starts an Odin game on Classic Yard, Yard, Bridge or Tower. It runs `Server/BOM-server.exe`
   for you; nothing else needs installing. It starts an Elimination round, and the host starts each new round.
   - *This PC only* is for testing on one machine. *LAN / direct IP* lets others join; the Esc menu shows the
     address to give them. The first time, Windows asks about BOM-server: tick **Private networks** and press Allow.
4. **Online → Join**: type the host's address and port and pick the same level as the host.
   Over the internet the host has to forward the UDP port on their router (there is no relay yet).

Builds for testers come as a package from J (`BOM-Windows-<date>`, with Mono and IL2CPP builds). Building the online
game yourself is not one click yet: Unity's normal Build doesn't include the online scenes or the server.

## What's where
| folder | what it is |
|---|---|
| `Assets/Game/` | Darryn's game: levels, art, menus, shop, offline mode. |
| `Assets/BOMIntegration/` | The Unity side of Odin: drawing the world, the online menus, HUD and results, input. |
| `Assets/BOMIntegration/Plugins/x86_64/bomcore.dll` | The Odin engine as Unity loads it. |
| `Server/BOM-server.exe` | The Odin game server (see `Server/README.md`). Built together with `bomcore.dll`. |
| `Engine/` | Odin source: physics, destruction, rules, netcode, server. Written in Odin (odin-lang.org). |
| `integration/` | Tools, checks, level files, design notes. `integration/ALPHA-SYNC.md` has every task and decision. |
| `integration/fixtures/materials.json` | Destruction values per material (toughness, blast resistance, colour...). |

## What changed for you
- Online play goes through Odin. The NGO/Relay code (`Assets/Game/Online`) and the netcode and multiplayer packages
  are gone. `Assets/BOMIntegration/Game/OnlineMatch.cs` stands in for the old `OnlineMatch`, so your scripts that ask
  "is an online match running?" get "no" and take their offline path.
- Kept from "Online v0.2": the Game Over panel, the HUD fix, the coin and wallet split, game over on touching a Bound,
  RemotePlayerSmoother and ModelSnapshot.
- `WebGLBuild3` is gone; the engine doesn't run in a browser.
- Online rounds pay into the shop wallet (10 per bomb faced + 1 per second, the same formula as offline).
- Online, everyone appears in their slot colour (blue, red, yellow, green); chosen characters aren't sent yet.

## Please don't
- Replace `bomcore.dll` or `BOM-server.exe` on their own. They are built from the same `Engine/` commit and the game
  checks the DLL's identity at start; a mismatch stops it.
- Change how things break or move by editing Unity physics on the online levels: online, Odin decides that.
  Tell J what you want to change (it's usually a number in `materials.json` or in `Engine/`).
- Edit or regenerate `.meta` files of existing assets.

## Changing things
- **A level's layout:** edit Darryn's level scene as usual; the Odin version of it (`integration/fixtures/levels/`) is
  re-exported from the scene with `BomArenaBoundaryBuilder.ExportAll`, then checked. For now ask J to run that.
- **Destruction feel:** change a number in `integration/fixtures/materials.json` (allowed ranges are in its note),
  re-export, and check that the level still stands at round start.
- **New bombs and characters:** they go into Odin first (J and the bomb artist), then Unity draws them.

## Known issues
If you hit one of these, note the level, whose player, and same PC or LAN; a clip or screenshot helps most.
- **Movement prediction is still choppy at times**: your own player can stutter or snap back, most on the Tower.
  It's better than it was (the 2026-11-24 fixes draw your player between server ticks and keep controls live through
  resets). It looks worse in Unity's Play mode than in a built game, so judge it in a build.
- **Glue resists bending too much**: a piece can stay stuck out at a right angle from a piece that has just broken
  off, like a shelf. Planned fix: give glue a bending (shear/moment) limit in the engine, so overhanging pieces snap
  under their own weight while load-bearing joints stay strong. It has to keep the Bridge and Tower standing at round start.
- **Seams sometimes crack before any bomb lands**, with players standing on a level (mostly the Bridge). Rare and varies
  run to run; we think players' weight sets it off.
- **The first blast can hitch** for a frame when two game windows run on the same PC.
- **Fixed 2026-11-24, tell J if you still see them:** the ground blowing apart after many blasts, the game getting
  slower as rubble piles up, and online play stalling during a long Unity frame.
- **Not yet tried between two real PCs on a LAN.** Everything so far ran on one machine.
- **After opening the project, git shows 4 deleted `PT_Nature_Free_URP_*.unitypackage.meta` files** (and sometimes a
  changed `Bedrock.mat`). Unity removes metas whose `.unitypackage` isn't in the repo. Discard those changes; don't commit them.

## Not done yet
Offline Play on Odin (one rule set everywhere), a solo/survival mode with bots, playing over the internet without
port forwarding, sending chosen characters online, the shadow colour fix, and the new bombs. The game feel has only
been checked by machines so far: that's what the team playtest is for.
