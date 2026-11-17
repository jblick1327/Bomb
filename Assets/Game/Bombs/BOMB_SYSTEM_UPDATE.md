# Bomb system update

## Install

This archive contains the contents of a Unity Assets folder. Merge its contents into the existing project's Assets folder and replace matching files. Preserve the existing .meta files supplied in the archive. Let Unity recompile before entering Play mode.

## Scenes configured

- YardLevel (Bomb System prefab and explicit scene overrides)
- BridgeLevel
- TowerLevel
- Unused/Arena
- _Recovery/0, if that recovery scene is opened

Scenes without a BombDropper were left unchanged. The shared Bomb System prefab was also updated for future instances.

## Defaults

- Each drop has a 50% chance of being an impact bomb or a timed bomb.
- Impact bombs explode on the first solid collision, except rubble.
- Timed bombs start a three-second fuse on that collision. Later collisions do not restart it.
- Impact blast radii are 0.8 times the scene's existing base radii; timed blast radii are 1.3 times the base radii. This includes craters, player damage, destruction, debris cleanup, and blast-ring size.
- The existing bomb model reference is retained as Impact Bomb Model. Timed Bomb Model can be assigned independently; leaving it empty uses the impact model.
- Drag a model asset or visual prefab into each model slot to retain its meshes, children, and materials. The system fits it to Bomb Radius and provides independent visual scale and rotation controls. Gameplay uses the bomb root's sphere collider.
- Explosion Clip uses the included bombExplosion.mp3. The included bombCountdown.wav is a one-second looping tick, played at the timed bomb during its fuse. Either clip can be replaced in the Inspector.
- Countdown audio stops on detonation or round cleanup. Explosion audio can finish after the round ends.

Collectible drops, power-ups, shields, multiplayer damage resolution, timers, existing scene references, and shared music/UI audio were retained from the uploaded build.

## Existing external assets

The supplied archive references third-party bomb/collectible models and level assets that are not included in the archive. Their existing references have been preserved. Merge this update into the existing project with those asset packs installed. If a bomb model cannot be resolved, the bomb uses the built-in sphere visual.

## Check in Unity

1. Open each gameplay scene and select Bomb System / Bomb Dropper.
2. Temporarily set Timed Bomb Chance to 0 to verify immediate impact explosions and the smaller blast.
3. Set it to 1 to verify countdown sound, flashing, and the larger delayed explosion; restore 0.5 afterward.
4. Confirm collectibles, invincibility, multiple simultaneous player deaths, and restart still behave as expected.

Validation performed here: C# syntax parsing, scene/prefab serialization and bomb-setting checks, unchanged collectible-method comparison, existing reference preservation, and ZIP integrity. A Unity editor/runtime was not available for compilation or playtesting.
