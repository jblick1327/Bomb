# First use: author a destructible structure

Workflow guide for the reviewed v4 Unity tool. Handbook 1.8.0 / Architecture v0.16 (`ASSET-001` to `ASSET-009`, `CON-015`) owns current requirements. UI labels and supported FBX/numeric conventions describe this implementation; they do not freeze the Unity/Odin schema.

Open **BOM > Authoring workspace**. The numbered tabs follow the normal workflow. To explore a finished example first, open `Assets/BOM/Fixtures/ReferenceLevel.unity`.

## 1. Import and edit a piece

1. Export a static FBX from Blender and drag it into Unity's **Project** window. Drag the imported model into **Model (FBX)** in the workspace. An outline is proposed automatically; no existing approved piece is changed.
2. Check **Projection plane**: XY is the front view, XZ the top view, and YZ the side view. Choose the view that gives the intended solid silhouette. All displayed profile coordinates are in metres.
3. Edit the flat outline: drag cyan outer points or orange hole points. Double-click an edge to insert a point; select a point and press Delete or use **Remove selected point** to remove it. A contour always retains at least three points. Click empty space to clear selection.
4. Use **Add hole** to create an enclosed hole in solid material. Use **Contour** to choose a hole and **Remove selected hole** to remove it. Red outlines are disconnected proposed regions; correct the retained outline and explicitly discard unwanted regions before approval.
5. Scroll over the outline to zoom, middle-drag to pan, and use **Fit outline** to restore framing. Optional grid snapping uses the displayed grid spacing. Select a point to enter an exact position. Escape cancels an active drag; Ctrl+Z / Ctrl+Y undo and redo draft edits.
6. Choose a **Gameplay material**, or use **Create material...** and edit its initial density/resistance in the Inspector. For destructible pieces, choose or create a **Destruction response** as well. These editable initial values are not calibrated game tuning.
7. Review the 3D appearance preview, thickness, colours and optional face image. **Fit image to outline** gives a simple bounds-fitted planar mapping. Import proposes the first source material; it does not reproduce every material slot or arbitrary source UV seams.
8. When validation says the outline and settings are ready, use **Approve and continue to placement** and choose a new asset path. Existing approved pieces receive an explicit new version instead. Invalid data cannot be approved.

The source settings, exact contour coordinate lists and texture mapping vectors are under **Advanced**. Source conversion changes refresh an unedited projection automatically. If you have corrected the outline manually, it stays intact and approval is blocked until you explicitly **Update projection**; replacing those edits requires confirmation. Colours, material, response and other pending selections survive regeneration.

Advanced coordinate lists stay synchronized with canvas movement, insertion, deletion and Escape cancellation. The numeric fields are disabled only while a canvas drag is active; release the drag before typing exact coordinates. If the initial projection is edge-on and fails, you can still choose gameplay definitions and edit appearance while correcting the plane. Explicit choices survive repair; untouched appearance settings are inferred when the first usable outline is proposed.

**Cancel proposal** restores the last approved draft. Closing a window with a pending draft prompts Save / Discard / Cancel; Save approves only valid data, Discard retains the last approved asset, and Cancel keeps editing. A new unapproved draft has no saved piece yet.

## 2. Place pieces and choose fixed supports

Select a **Level**, or use **Create level authoring group**. Select the approved piece and use **Place piece**. Each placement is a separate physical body.

Use Unity's Scene handles to move, rotate about Z, or apply positive X/Y scale. Z position must be zero, Z scale must be one, and parent transforms must not introduce shear or reflection.

Select placements in the Scene or Hierarchy and use **Make selected pieces fixed supports** for pieces that should not move. **Make selected pieces movable** reverses that choice. Material, destruction and grab eligibility have independent placement overrides and reset buttons in the placement Inspector. Save reusable groups as ordinary Unity prefabs.

## 3. Connect a structure

Select two placements and use **Use two selected pieces**, then **Propose shared-boundary bond**. They must share an edge: gaps, point-only contact and solid overlap are not attachments. **Preview alignment of parallel boundaries** proposes a translation without applying it yet.

Review the highlighted attachment, strength and optional attachment-loss rule, then **Confirm connection**. Cancel leaves the transforms and saved bonds unchanged. Confirm returns to creation mode; editing an existing bond requires its explicit Inspector review action.

## 4. Playtest

Choose or **Create preset and add to level...** in Playtest. A shared preset has a name, radius, reach budget and fragment impulse speed. Its initial values are editable in the Inspector. At least one valid preset and one approved placement are required before starting.

Validate the level, then **Enter Play mode**. The level starts its local simulation automatically. Select the named captured preset and Shift-click exterior air in Scene view, or enter an XY origin and use **Run explosion**. Blasts remove material, create physical fragments and remap surviving bonds and fixed supports.

**Reset to last captured start** restores the frozen starting level; approved assets are not damaged. **Start / capture a new initial configuration** recompiles current authoring inputs. Changing a preset asset or reordering authoring presets does not change the running world's captured presets.

The snapshot tools remain under **Advanced**. This is local authoring/playtesting, not multiplayer transport or a complete bomb/fuse/player-damage system. Exterior-only blast origins and numerical complexity/precision refusals remain explicit restrictions.
