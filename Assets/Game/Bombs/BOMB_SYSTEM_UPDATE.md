# Bomb system update for the actual current build

## Install

This archive contains Unity Assets-folder contents. Merge them into the existing project's Assets folder, replacing matching files and keeping the supplied .meta files. Let Unity finish compiling before entering Play mode. This is based on CurrentBuild.zip, not the earlier Current Build.zip upload.

YardLevel, BridgeLevel, TowerLevel, and their shared Bomb System prefab are configured. Scenes without bombs are unchanged.

## Bomb settings

- Timed Bomb Chance: 0.5 (50% of drops). Set to 0 for impact-only or 1 for timed-only.
- Timed Bomb Fuse: 3 seconds from the first solid impact. Further impacts never restart it.
- Impact Bomb Model and Timed Bomb Model accept whole model assets or visual prefabs with their meshes, materials, and children. Each has independent scale and rotation. Leaving the timed slot empty uses the impact model.
- The existing bomb model reference is retained. Gameplay physics use a separate sphere collider; colliders, rigidbodies, scripts and audio on the visual model do not control the bomb.
- Impact Explosion Scale: 0.8. Timed Explosion Scale: 1.3. These scale carving/destruction, debris cleanup, limb-damage range, one-shot range, and blast-ring radius together.
- Explosion Clip uses the existing bombExplosion.mp3. Countdown Clip uses the included looping bombCountdown.wav tick. Assign different clips in the Inspector if desired.
- Countdown audio starts at impact, follows the bomb, and stops when it explodes or is cleared. Explosion sound can finish after a round ends.

The build's collectible logic, shields, limb damage, player bursting, supported-block destruction, rubble materials, results icons, music, and lobby features were retained.

## Online play

The host chooses and broadcasts each bomb's type. Once a timed bomb lands, it sends countdown/position updates to clients. Clients show the countdown but apply no independent detonation; the host's explosion message supplies the type, blast-size multiplier, and explosion point. Bomb events include the round number to reject stale events.

All online participants must use this updated build because bomb-message payloads have changed. Item, lobby, player-state, graze, and death messages retain their existing formats.

## Existing asset packs

Some third-party bomb, collectible, and level assets are referenced but omitted from the supplied archive. These references are preserved; merge into the existing project with those packs installed. If a bomb model is unavailable, a built-in sphere is used.

## Unity checks to run

1. Open each level, temporarily force impact bombs, and check the smaller immediate blast.
2. Force timed bombs and check the three-second countdown, sound, flashing, and larger blast. Restore the 0.5 chance afterward.
3. Check shields, limb hits, close-range one-shot kills, unsupported blocks, collectibles, and restart.
4. In a host/client match, check that bomb types agree, the countdown does not restart on clients, both sides see the same host explosion, and countdown sounds stop during round cleanup.

C# syntax parsing, unchanged-method comparisons, scene/prefab serialization, asset-reference checks, packet-field consistency checks, and archive integrity were checked here. Unity compilation, gameplay, and live host/client networking still require testing in Unity.
