# Integration report

Spec reference: §9.1 ("Report every changed file and explain any compatibility
risks"), §19 Milestones 0–4.

## Starting point

The repository was **empty** (an initialised git repo with no commits and no
files; the remote had no branches). Confirmed with the user that no prior Godot
project existed, so this is a **fresh foundation**, not an integration into an
existing game. The spec's "do not rebuild the existing game" rule (§9.1) has
nothing to preserve here; it will apply to all future changes.

## Testing status (updated — it HAS been run)

Godot **4.4.1** was downloaded into the build environment and the project was
run headless. Results:

- **Clean import**: all 15 scripts parse, all global classes register, 0 errors.
- **Physics smoke test** (`tests/vehicle_physics/physics_smoke_test.tscn`): PASS.
- **Acceptance harness** (`tests/vehicle_physics/acceptance_harness.tscn`): PASS —
  0–100 in 8.17 s, top 188.8 km/h, dry/wet braking 8.0/9.1 m, deterministic.
- **Bridge drive test** (`tests/map_validation/bridge_drive_test.tscn`): PASS —
  car drives on the generated deck, stays grounded, does not fall through.
- **Race-flow test** (`tests/race_flow/race_flow_test.tscn`): PASS — Bridge Test
  Sprint runs countdown → 5 checkpoints in order → finish; best time 109.25 s
  recorded and round-tripped through the save file.
- **Traffic test** (`tests/map_validation/traffic_test.tscn`): PASS — 6 AI
  traffic cars spawn, stay on the deck and drive their lanes (Milestone 6 start).
- **Map pipeline**: runs and regenerates a valid 5.1 km chunk.

Three real bugs were found by these tests and fixed (see
`docs/physics_baselines.md`): default-damping combine capping top speed, missing
`backface_collision` dropping the car through the road, and `continuous_cd`
making the bridge run slowly. Headless has no GPU, so **visual** polish (shaders,
lighting readability, camera feel, HUD layout) still needs a human pass in the
editor on Windows.

## Files added

### Project
- `project.godot` — Godot 4.4 config: InputMap (spec §15 actions), 60 Hz physics,
  forward+ renderer, window 1280×720. Main scene = the physics test track.
- `icon.svg`, `.gitignore`.

### Vehicle physics (Milestone 1)
- `scripts/vehicles/vehicle_data.gd` — `VehicleData` resource, all tunables (§5.4).
- `scripts/vehicles/vehicle_controller.gd` — raycast `RigidBody3D` controller (§5.1–5.3).
- `scripts/vehicles/transmission.gd` — automatic gearbox (§5.5).
- `scripts/vehicles/player_driver.gd` — InputMap → controller (kept separate for AI reuse).
- `scripts/vehicles/vehicle_debug.gd` — 3D telemetry gizmo (§5.3).
- `data/vehicles/sedan_01.tres` — starting car calibration.
- `scenes/vehicles/player/player_car.tscn` — car scene (body, 4 raycast wheels, collision).

### Camera, HUD, save
- `scripts/camera/chase_camera.gd` — chase/hood/bumper camera (§7).
- `scripts/ui/hud.gd` + `scenes/ui/hud/hud.tscn` — km/h, gear, RPM, timer, F3 debug (§7, §15).
- `scripts/save_manager.gd` — offline settings + best-time persistence (§16).

### Test track (Milestone 1)
- `scripts/world/test_track.gd` + `scenes/world/test_track.tscn` — flat track,
  braking lane with distance markers, crest, skidpad pylons, barrier (§5.7).

### Map pipeline (Milestones 2–4)
- `tools/lagos_map_pipeline/{geo,extract_osm,process_roads,generate_roads,generate_buildings,export_chunks,build_all}.py`
  + `config.json` — offline geo → chunk pipeline (§8).
- `data/map/lagos_bridge/tmb_south_prototype.json` — generated chunk (committed artifact).
- `scripts/world/map_loader.gd` — chunk JSON loader.
- `scripts/world/map_builder.gd` — `@tool` that builds road mesh/collision, piers,
  water, skyline from the chunk (§8.2–8.5).
- `scripts/world/bridge_world.gd` + `scenes/world/maps/lagos_bridge/lagos_bridge.tscn`.

### Race (Milestone 5 start)
- `scripts/races/checkpoint.gd` + `scenes/races/checkpoints/checkpoint_gate.tscn`.
- `scripts/races/race_manager.gd` — Bridge Test Sprint (§11).

### Tests & docs
- `tests/vehicle_physics/physics_smoke_test.{gd,tscn}` — headless crash-net (§18).
- `docs/physics_baselines.md`, `docs/map_pipeline.md`, `docs/source_licenses.md`,
  `README.md`, this report.

## Compatibility risks / things to verify in-editor

1. **Not run in Godot** — top risk. Expect to fix small API/typo issues on first
   open. Start with the headless smoke test, then the test track.
2. **`.tscn`/`.tres` hand-authored** — resource UIDs and `ext_resource` ids were
   written by hand. Godot should re-resolve them, but if a scene fails to load,
   check the editor's import log.
3. **Vehicle tuning is a starting point, not final** — values in `sedan_01.tres`
   must be dialled in via the §5.7 acceptance tests.
4. **Map alignment is synthetic/approximate** — see `docs/source_licenses.md`.
5. **Scale of the bridge chunk** (~5.1 km) — fine to drive, but the camera `far`
   plane and fog were set for it; adjust if you shorten/lengthen the route.
6. **No menus yet** — you launch scenes directly (spec §3.1 allows a dev launch
   shortcut before menus exist).

## Suggested next steps

- Open in Godot 4.4, run the smoke test, then the test track; record the §5.7
  baseline and tune `sedan_01.tres`.
- Drive `lagos_bridge.tscn`, run the sprint end-to-end, fix any mesh/collision
  seams (spec §8.3 checklist).
- Only then move to traffic (Milestone 6) and the fuller game (Milestone 7).
