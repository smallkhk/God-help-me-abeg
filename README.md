# Lagos Street Racing

A street-driving and racing game set on **Third Mainland Bridge, Lagos**, built in
**Godot 4.4** (GDScript-first), Windows-first and offline-first. This repository
implements the foundation described in `lagos_master_spec_v2.md`: a believable
simcade vehicle controller and a regenerable, geographically-grounded bridge map.

> Status: **Milestones 0–4 foundation.** The driving physics and a driveable
> Third Mainland Bridge prototype with a timed checkpoint sprint are in place.
> **Validated headless on Godot 4.4.1**: clean import (0 errors), physics smoke
> test, an automated acceptance harness (0–100 in 8.2 s, 189 km/h top, dry/wet
> braking, deterministic) and a bridge drive test (car stays on the deck) all
> pass. Three bugs were caught and fixed in the process (see
> `docs/physics_baselines.md`). Still needs a human **visual** pass in the editor
> (shaders, lighting, camera feel) since headless has no GPU.

## Open & run

1. Install **Godot 4.4.x** (standard, not .NET — the project is pure GDScript).
2. Open `project.godot` in Godot.
3. The main scene is the **physics test track** (`scenes/world/test_track.tscn`).
   Press **F5** / Play.
4. To drive the bridge, open and run `scenes/world/maps/lagos_bridge/lagos_bridge.tscn`.

## Controls (spec §15)

| Action | Keyboard | Gamepad |
|---|---|---|
| Accelerate | `W` / `↑` | RT |
| Brake / reverse | `S` / `↓` | LT |
| Steer | `A` `D` / `←` `→` | Left stick |
| Handbrake | `Space` | A |
| Camera cycle | `C` | — |
| Look back | `Tab` | — |
| Restart | `R` | — |
| Pause | `Esc` | Back/Select |
| Toggle wet road | `F` | — |
| Debug overlay | `F3` | — |

On the bridge, press **W** to start the countdown for the Bridge Test Sprint.

## What's here

- **Vehicle physics** — custom raycast controller on `RigidBody3D`
  (`scripts/vehicles/vehicle_controller.gd`), data-driven via
  `VehicleData` resources (`data/vehicles/sedan_01.tres`). Suspension, slip-based
  tyres, a friction circle, emergent weight transfer, automatic transmission,
  assists (Assisted/Standard/Expert), wet grip.
- **Map pipeline** — `tools/lagos_map_pipeline/` (Python, offline) turns geo data
  into a chunk JSON; `scripts/world/map_builder.gd` (a Godot `@tool`) builds the
  road mesh, collision, bridge piers, lagoon and skyline from it.
- **Race** — Bridge Test Sprint with countdown, ordered checkpoints, timer,
  results and best-time save (`scripts/races/`, `scripts/save_manager.gd`).
- **Camera & HUD** — chase/hood/bumper camera, km/h speed, gear, RPM, timer,
  and an F3 debug overlay + 3D telemetry gizmo.

## Regenerating the map

```bash
python3 tools/lagos_map_pipeline/build_all.py
```

Edit `tools/lagos_map_pipeline/config.json` (or point it at a real OpenStreetMap
extract) and re-run to regenerate `data/map/lagos_bridge/*.json`. See
`docs/map_pipeline.md`. **The current alignment is a synthetic approximation,
not surveyed data** — see `docs/source_licenses.md`.

## Testing

See `docs/physics_baselines.md` for the full acceptance-test procedure (spec §5.7).
Headless smoke test:

```bash
godot --headless --path . res://tests/vehicle_physics/physics_smoke_test.tscn
```

## Documentation

- `docs/integration_report.md` — every file added and compatibility notes.
- `docs/physics_baselines.md` — vehicle tuning + acceptance tests.
- `docs/map_pipeline.md` — map generation pipeline.
- `docs/source_licenses.md` — data provenance & licensing obligations.
