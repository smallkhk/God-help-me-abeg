# Importing your own track (Blender / OSM → drivable)

This is the drop-in slot for a track you make or source. You supply a 3D model
and a tiny config; the game bakes collision and wires up the car, camera, HUD and
race automatically — no code.

## What to export from Blender

- A **`.glb`** (glTF 2.0 binary).
- **Metres scale**, **Y-up** (Godot's convention; Blender export has a Y-up option).
- The **drivable surface as real geometry** (the car collides with the mesh you
  export — so the road must be actual faces, not just a texture on a plane).
- Keep it reasonable: a huge ultra-dense mesh makes collision heavy. Decimate
  scenery you won't drive on.
- Note which way is **forward** and roughly where **start** and **finish** are.

Prefer accurate real roads? You don't have to trace them — send me the area and I
pull the real road geometry from OpenStreetMap (as done for Third Mainland
Bridge); you then only beautify in Blender.

## Steps

1. Drop your `track.glb` into `assets/lagos/` (Godot auto-imports it as a scene).
2. Copy `data/map/sample_track_config.json` to e.g. `data/map/my_track.json` and
   fill in `spawn` and `checkpoints` (world metres, `heading_rad` = facing about
   +Y, 0 faces +Z). Order the checkpoints start → finish.
3. Open `scenes/world/maps/external_track.tscn` and set:
   - **track_scene** → your imported `track.glb`
   - **track_config_path** → `res://data/map/my_track.json`
4. Run that scene (F6). The car spawns, the mesh is solid, and the sprint runs
   through your checkpoints.

If you don't have exact checkpoint coordinates yet, leave `checkpoints` empty —
you can still free-drive the track; we add the race line afterwards.

## What happens under the hood

- `CollisionBaker` walks every mesh in your `.glb` and bakes one
  `ConcavePolygonShape3D` with `backface_collision = true` (so wheels never fall
  through, whatever the triangle winding) — spec §8.3 "collision follows the
  visible surface".
- `external_track.gd` instances your model, adds basic sun + sky (a track that
  ships its own lighting overrides this), spawns the garage-selected car, and
  starts a `RaceManager` fed with your checkpoints.

## Gotchas

- If the car falls through, the drivable surface wasn't exported as real faces,
  or it's far from the spawn point — check the config coordinates match the mesh.
- If it runs slow on a weak GPU, the mesh is too dense; decimate in Blender.
- Keep the track near the origin (within a few km) to avoid float precision
  issues (spec §8.5).
