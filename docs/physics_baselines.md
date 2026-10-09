# Vehicle physics baselines & acceptance tests

Spec references: §5 (physics), §5.7 (acceptance tests), §18 (QA).

## Controller summary

`scripts/vehicles/vehicle_controller.gd` is a **custom raycast controller** on a
`RigidBody3D` (spec §5.1 — chosen over `VehicleBody3D` for direct control of the
tyre and weight-transfer model). Four downward raycasts act as wheels:

- **Suspension**: spring (`stiffness × compression`) + damper
  (`damping × compression_speed`) + anti-roll, applied along the body up axis at
  the contact point.
- **Tyres**: a slip-angle lateral force and a longitudinal drive/brake force,
  each capped by `grip × normal_load`, then clamped together by a **friction
  circle** so combined cornering + braking exceeds grip and the car slides.
- **Weight transfer is emergent**: braking/cornering pitch and roll the body,
  changing per-corner spring compression → normal load → available grip. Nothing
  is faked by writing position/rotation (spec §5.1).
- **Transmission** (`transmission.gd`): automatic, RPM/throttle based, with a
  shift cooldown to stop gear hunting; reverse engages only near standstill.
- **Assists** (spec §5.6): ABS caps brake force at the grip limit, traction
  control trims excess drive force, stability assist damps yaw rate. All three
  only modify forces within the same physics — Assisted > Standard > Expert.

All tuning lives in `VehicleData` (`scripts/vehicles/vehicle_data.gd`), surfaced
per car as a `.tres` (`data/vehicles/sedan_01.tres`).

## Units (spec §5.3)

Metres, seconds, kilograms, newtons, radians internally. HUD shows km/h
(`m/s × 3.6`). Forward = local **+Z**, up = **+Y**, right = **+X**.

## Starting calibration — `sedan_01`

These are **engineering starting values, not real-world specifications**
(spec §5.4, §5.7). Record a baseline on first run, then tune.

| Parameter | Value |
|---|---|
| Mass | 1250 kg |
| Drivetrain | FWD |
| Max drive force | 9000 N (scaled by gear + torque curve) |
| Brake force | 11000 N (0.6 front / 0.4 rear bias) |
| Max steer | 0.60 rad low speed → 28% at 45 m/s |
| Suspension | 32000 N/m, damping 3800, rest 0.45 m, travel 0.18 m |
| Lateral grip | 1.35 front / 1.40 rear |
| Longitudinal grip | 1.45 |
| Peak slip angle | 0.14 rad |
| Wet grip multiplier | 0.72 |
| Gears | 5 fwd (3.4/2.1/1.45/1.0/0.78), final 3.9 |

## Measured baseline (Godot 4.4.1 headless, automated harness)

Produced by `tests/vehicle_physics/acceptance_harness.tscn`. These are real
measured figures for `sedan_01`, not estimates:

| Metric | Result |
|---|---|
| 0–100 km/h | **8.17 s** |
| Top speed | **188.8 km/h** |
| Braking 50→0 km/h (dry) | **8.0 m** |
| Braking 50→0 km/h (wet) | **9.1 m** (correctly longer) |
| Handbrake peak yaw | **2.20 rad/s** (slides, no auto-spin) |
| Deterministic across identical runs | **yes** |

Bugs found and fixed via this harness (all verified in-engine):

1. **Top speed capped at 96 km/h** — the project's default linear damping (0.1)
   was *combining* with the body instead of being replaced, silently sapping
   drive force. Fixed by setting `linear_damp_mode = REPLACE` so the tyre/aero
   model is the only resistance. After the fix, measured accel matches the
   force model (`a ≈ (F_drive − F_drag) / m`).
2. **Car fell through the bridge deck** — the runtime road `ConcavePolygonShape3D`
   defaults to `backface_collision = false`, so downward wheel rays struck the
   back of road faces and passed through. Fixed with `backface_collision = true`.
3. **Severe slowdown on the bridge** — chassis `continuous_cd` sweeping against
   the 5k-face road trimesh every step. Disabled CCD (wheels are raycasts, which
   never tunnel).

## Acceptance tests (spec §5.7)

Run on `scenes/world/test_track.tscn`. Toggle the debug overlay with **F3** and
read speed/slip/load from it. Record each result and compare build-to-build.

1. **Idle** — car rests still on flat ground, no drift/vibration.
2. **Launch** — full throttle from rest tracks straight (no sideways launch).
3. **Top speed** — on the long lane, speed plateaus (drive force ≈ drag).
4. **Braking** — from 40/70/100 km/h at the `0 m` line; stopping distance grows
   with speed. Read distance off the lane markers (0/25/50/75/100 m).
5. **Constant-radius corner** — circle the skidpad pylons at rising speed; grip
   loss should come on progressively, not as a cliff.
6. **Brake while cornering** — the car runs wide (understeer) when combined
   demand exceeds the friction circle.
7. **Handbrake turn** — `Space` mid-corner breaks rear grip into a slide; it does
   **not** auto-spin.
8. **Wet vs dry** — press **F** to wet the road; braking and cornering grip drop.
9. **Crest** — drive over the ridge; suspension absorbs it without wild bounce.
10. **Barrier** — hit the yellow barrier; speed bleeds off with believable
    rotation, no launch into the sky.
11. **Frame-rate independence** — repeat key tests at capped 30 and 120 FPS
    (Project Settings → `application/run/max_fps` or `--max-fps`). Behaviour
    should match: physics runs at a fixed 60 Hz in `_physics_process`.
12. **Endurance** — drive ≥ 10 minutes; no drift, runaway velocity, or growing
    instability.

Set measurable target numbers **after** recording the first baseline. Do not
invent exact real-world stopping distances for a fictional car (spec §5.7).

## Headless smoke test

```bash
godot --headless --path . res://tests/vehicle_physics/physics_smoke_test.tscn
```

Asserts finite state, upright, on the floor, and that the car accelerates;
exits 0/1 for CI. It is a crash-net, not a feel test.
