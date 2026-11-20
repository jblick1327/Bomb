# Next step: a playable destruction sandbox

> **Historical / superseded:** This plan records an earlier UI milestone. [README.md](../../README.md) is authoritative for the current playable UI and behavior; original instructions below do not override later decisions, including breakup labels, defaults and the destructible floor.

Make the local Odin lab comfortable to play with: one small side-view test yard, one movable character, the existing click-to-blast action, a quick reset and a compact settings panel. This is the next user-facing milestone for the rewrite.

The reference was a brief look at the original [Bomb README](https://github.com/jblick1327/Bomb/blob/main/README.md) and repository layout. Its move/jump/bomb/reset loop supplies context. The implementation baseline here is the Odin prototype already shared in this conversation; this plan does not involve migrating the Unity project.

The loop should be: launch, walk and jump around, preview and trigger a blast, interact with the fragments, then press R to try again with the same setup.

**What the first version should feel like**

- The application opens directly into the yard, ready to play.
- A simple capsule or rectangle clearly marks the character. It collides with the floor and destruction geometry, can stand on fragments and can push loose pieces.
- A fixed camera comfortably frames the whole small yard. Resizing the window preserves that framing; flying fragments do not move or zoom the camera.
- The blast preview makes the effect's location and radius clear before clicking.
- A short control hint and small settings/reset buttons leave most of the window available for the world.
- The player is invulnerable during experimentation and returns to spawn after falling outside the yard.

**Controls**

| Input | Normal play |
| --- | --- |
| A/D or left/right arrows | Move |
| Space | Jump |
| Left click in the world | Trigger one blast at a valid cursor position |
| Mouse wheel over the world | Adjust blast radius |
| R | Reset the yard with the current applied settings |
| Tab or Escape | Open the settings panel and pause; close it to resume |
| F3 | Toggle inspection tools and diagnostics |

Use a hint such as “A/D Move · Space Jump · Click Blast · R Reset” along one edge, with “Tab Settings” on the settings button. Put the complete controls in the panel. Keep the existing subdivision IDs, connection lines, counts and manual removal tools behind F3. Use Delete for selected-subdivision removal so D always remains movement.

Configure the window library so Escape opens or closes the panel instead of exiting the application.

**The yard and player**

Build one fixed scene: a static floor, a spawn point on the left and a small destructible stepped wall or tower to the right. Use the existing generator and model to create the structure. Keep enough clear floor space to approach the wall and move around the debris.

Use ordinary world gravity for this scene. Tune its starting material strengths and blast scale so the structure rests stably on the floor and responds clearly to deliberate actions. Leave the physics adapter's zero-gravity test fixtures available for existing tests.

Give the player one Box2D body with a capsule or simple rectangular collider and fixed rotation. Keep its small controller state separate from destruction subdivisions: structural failure passes should not replace or remove the player. Reuse contact information to determine support. Control horizontal movement and jumping while Box2D handles vertical motion and collision. A short jump buffer and coyote window, initially around 0.1 seconds each, are enough jump assistance for this version.

Put the movement constants together: speed, acceleration, jump speed and the two jump-assistance times. Resetting or respawning clears grounded state and jump timers. The player uses the same world as the fragments, so jumping onto and pushing debris exercises the actual simulation.

**Aiming and interaction feedback**

Draw a small cursor marker and a thin circle showing the current blast radius. Fire once per mouse press. Keep the model's outside-origin assumption: when the cursor is inside live destruction geometry, show an invalid marker and suppress the blast. A short message such as “Aim outside the solid shape” explains the blocked action. Use the logical posed outlines for this test.

Give UI and inspection actions priority over world actions. A click on any button, slider or panel must never also trigger a blast. Mouse-wheel input over the panel belongs to the panel. While the panel is open, player and world actions are suspended. Clear pending jump/blast input on opening it, and resume without accumulating paused time into a physics catch-up burst.

Keep feedback brief: a small temporary message for reset, invalid aim or settings applied. Let the geometry and motion show successful destruction.

**One compact settings panel**

Open a panel that pauses the simulation and contains Resume, Apply & Reset and the following existing settings:

| Control | Behavior |
| --- | --- |
| Blast radius | The same value adjusted by the mouse wheel. |
| Breakup pattern: Chunk / Splinter / Shatter | Set generation count, aspect ratio and triangulation through the existing presets. Keep strength and flexibility independent. |
| Fragment strength | Edit the existing subdivision-strength value. |
| Connection strength | Edit the existing connection-strength value. |
| Flexibility | Edit the existing softness value. |
| Generate children | On uses the current nonzero seed; off uses seed zero. Existing geometry remains live until it fails. |

The strength and flexibility fields can sit in one collapsed Tuning section. Reuse UI widgets already available in the project; a few fixed controls are sufficient. Use plain labels rather than component or storage terminology.

Store these selections in one small settings record. Radius updates the preview immediately. Stage the other edits until Apply & Reset, which rebuilds the yard and resumes play. This gives material and joint changes a clear moment to take effect. R resets the last applied setup, including its seed; it does not silently generate a different experiment. Keep detailed recipe editing and seed randomization for a later need.

**Implementation order**

1. **Check the starting behavior.** Fix the known generation case that returns an unchanged single replacement when splitting cannot proceed. Use the existing direct-removal outcome for that failed subdivision. Settle the radius-to-load curve: the current normalized curve caps direct load at 10; a fixed multiplier times `max(0, radius - distance)` supports the intended radius/power relationship. Keep these as focused changes and add the small-generation regression case.

2. **Build the yard, player and shared reset.** Add the floor, gravity, player controller and fixed framing. Implement one reset function that recreates the scene and player, clears remnants and pending inputs, and restores the spawn. Preserve the applied settings. Verify movement, support on fragments and repeatable reset before changing the interface.

3. **Add the normal play input route.** Map movement, jump, blast, radius and reset. Add the blast preview and invalid-position feedback. Resolve Space/D conflicts and ensure the player can no longer accidentally invoke the old debug shortcuts.

4. **Replace the large debug text with the compact HUD and panel.** Route input through the panel first, stage settings edits, and implement pause/resume and Apply & Reset. Put the original inspection affordances behind F3. Keep the main application loop straightforward.

5. **Play through the complete loop and tune it.** Adjust movement, jump timing, starting material values, radius and framing by playing. Prioritize clear feedback, reliable controls and rapid repeat attempts.

A modest code split is enough: one player module, a small yard/reset helper and changes to the existing application/view loop. The destruction passes remain the shared simulation path. This milestone is local; player replication and changes to the snapshot protocol are outside its implementation scope.

**Completion checks**

- On launch, the player and target are visible and the essential controls are discoverable without reading the README.
- Movement, jumping, landing on debris and pushing fragments work. Holding jump does not produce repeated airborne jumps.
- The starting structure remains stable under ordinary gravity and routine contact.
- Previewed blast radius matches the applied radius. UI clicks and invalid origins cause no world blast.
- R works after an explosion, while fragments are moving, and after player respawn. It restores one player and a clean yard with the same applied settings and seed.
- The settings panel pauses physics, fading and player actions. Closing it produces no jump, blast or simulation catch-up from menu input.
- Apply & Reset applies breakup pattern, strengths, flexibility and generation eligibility together. Selecting a breakup pattern does not unexpectedly change strength or flexibility.
- Normal play has a small HUD; inspection details appear when F3 is requested. D and Space keep their normal play meanings.
- Existing behavior tests still pass. Add focused automated checks where practical for reset, input consumption and the no-progress generation fix; verify feel and visual clarity by playing the application.

The first checkpoint is the player moving and jumping around the fixed yard with a reliable R reset. Once that works, finish the preview, compact panel and input routing in the same milestone.
