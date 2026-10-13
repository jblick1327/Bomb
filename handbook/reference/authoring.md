Blender supplies source models; Unity owns review, reusable pieces, level composition and local destruction tests. The accepted scope is `ASSET-001` to `ASSET-009` and `CON-015`.

| Designer action | Required behaviour |
|---|---|
| Import | One source import is one initial physical piece, including multiple meshes/material slots. Import separate behaving parts individually and connect them afterward. |
| Review/correct | Present the proposed profile/extrusion/settings immediately. Support concavity, holes, graphical/exact corrections and explicit approval. Invalid/disconnected proposals require correction. |
| Choose properties | Material, destruction and grab defaults are independent. Placements inherit per field; overrides show their source and reset independently. Appearance is separate. |
| Render/cut | Use uniform current-profile extrusion from the outset. Thickness is visual. Preserve surviving outline and face samples; original sides and new cuts have separate appearance. |
| Place/save/reimport | Save levels/assemblies with references/overrides intact. Keep manual corrections and pending choices until explicitly replaced; revalidate affected bonds. |
| Connect | Only nonzero shared gameplay boundaries form authored rigid bonds. Review extent/strength and preview alignment. New creation and saved editing are distinct operations. |
| Test/recover | Derive managed machinery automatically. Compile/validate, run actual destruction from captured configuration, reset without changing authored assets, and reconstruct current state/definitions without replay. |

The [authoring guide](https://github.com/jblick1327/Bomb/blob/gh-pages/handbook/guides/unity-authoring-v1.md) describes the current tool. FBX conversion, asset classes, numeric precision and the shared exchange representation remain implementation choices. Character, live-bomb, hold and multiplayer behaviour require separate integrated verification.
