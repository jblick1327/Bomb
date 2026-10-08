# Gameplay reference

## Turf, dirt, and blast effects

- Keep `Grass_Mesh` as a separate scene object from dirt.
- Give turf full depth along Z and carve it as a closed extruded polygon mesh, like the rock destructible effect. Avoid triangle clipping that leaves cracks or removes the depth dimension.
- Keep the turf renderer and mesh collider on the same generated mesh. Drop tiny turf polygons so visible pieces remain collidable.
- Keep the dirt crater profile independent from the turf mesh. The deeper crater and a flat floor wide enough for the player to stand on are preferred.
- Remove existing rubble and rock fragments caught inside a later blast radius.
