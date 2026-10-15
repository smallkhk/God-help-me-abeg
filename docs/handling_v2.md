# Handling v2: audit, lab results, proposal

Status: **v2 is OFF in the game.** It only runs in the handling lab
(`VehicleController.handling_v2`, set by the lab with `V2=1`). Turning it on in
the game is a one-line change once approved.

## 1. Existing controller (`scripts/vehicles/vehicle_controller.gd`)

A custom `RigidBody3D` raycast vehicle (not Godot's `VehicleBody3D`):

| Part | How it works |
|---|---|
| Suspension | 4 ray "wheels", spring + damper + anti-roll bar per axle (`ARB_SCALE` x3) |
| Tyres | Pacejka lateral force from slip angle, Pacejka longitudinal force from slip ratio of a simulated spinning wheel, load sensitivity, friction circle |
| Engine / gears | drive force x torque curve x gear ratio, 5-speed automatic with shift cooldown, reverse via brake |
| Brakes | brake torque on the wheel, front/rear bias, ABS (eases torque when locking), handbrake on the rear axle |
| Assists | traction control, ABS, yaw stability assist (Assisted / Standard / Expert) |
| Aero | drag ~ v², optional downforce, anti-launch when airborne |
| Nitro | extra drive force while held (a force, not a velocity change) |
| AI | rivals drive the same controller through `set_driver_input` (same physics); street traffic is kinematic (`AnimatableBody3D`) |
| Tick | 60 Hz `_physics_process`, `apply_force` only |

The architecture is sound and fit for simcade handling: it doesn't need a
rewrite. The handling problems come from quick fixes and two real bugs:

1. **Centre of mass at road level.** `center_of_mass_y = -0.4` puts the CoM
   ~2 cm *below* the tyre contact plane, so braking, accelerating and
   cornering move almost no weight between the tyres (and a handbrake even
   moved it backwards). The car feels glued and inert.
2. **Brake torque applied after the wheel solve.** Any brake torque, even
   light engine braking on lift-off, left a small artificial skid every step
   that the tyre model turned into near-maximum braking force (front tyres
   braking with ~3,600-4,000 N on lift-off instead of ~600 N). Results:
   29 m stops, strong lift-off deceleration, front tyres saturated in corners.
   The Golf and the family car needed 113-127 m to stop.
3. `GRIP_BONUS` +30 % grip on every car on top of their data.
4. A fixed "glue" downforce on every car.
5. Steering lock at speed capped to ~4 degrees, so the car can't use its
   grip (skidpad 0.59 g for every car).
6. The stability assist cancels any slide immediately (handbrake slides
   recover in 0.4 s).

## 2. Handling v2 (all behind `handling_v2`)

- Real CoM height above the contact plane: `cg_height_m` per car (sedans
  0.52 m default, SUVs/pickups 0.58-0.60, sports 0.42-0.47, keke 0.50).
- Brake and engine-braking torque inside the implicit wheel solve (wheels can
  lock, can't over-brake).
- Street-tyre grip: data grip x 0.70 (lateral) / 0.82 (longitudinal), so each
  car keeps its relative grip.
- No fixed glue downforce (only the car's own `downforce_coefficient`).
- Grip-limited steering lock: the kinematic angle for the car's cornering limit
  at that speed plus the front tyre's peak slip; full lock during a
  handbrake slide; calmer steering speed at high speed.
- Drift window (1.4 s after the handbrake): stability assist and traction
  control step back, faster steering for the flick, rear grip under handbrake
  x0.6; countersteering reduces the assist instead of fighting the driver.
- Brakes always able to give ~0.9 g for the car's weight.
- Drive force scale 0.85 instead of 0.75.
- Unchanged: suspension, tyre curves, gearbox, nitro, ABS, AI, controls.

## 3. Lab results (headless, 60 Hz, flat asphalt)

`godot --headless --fixed-fps 60 --path . res://tests/vehicle_physics/handling_lab.tscn`
(`V2=1` for v2, `CARS=id,id` to pick cars). Interactive: open the scene, F6.

| Car | Version | 0-100 s | Top km/h | 100-0 m | Skidpad g | Step t90 s | Handbrake slip / turn / recover |
|---|---|---|---|---|---|---|---|
| Corolla (FWD) | now | 10.7 | 167 | 29.2 | 0.59 | 0.10 | 15° / 54° / 0.4 s |
| Corolla (FWD) | v2 | 11.0 | 170 | 38.0 | 0.78 | 0.18 | 31° / 101° / 1.9 s |
| Golf 3 (FWD) | now | 9.7 | 166 | **127** | 0.59 | 0.10 | 14° / 57° / 0.4 s |
| Golf 3 (FWD) | v2 | 11.1 | 160 | 35.8 | 0.83 | 0.18 | 29° / 97° / 1.8 s |
| Skyline (RWD) | now | 6.1 | 217 | 29.4 | 0.59 | 0.10 | 28° / 114° / 0.8 s |
| Skyline (RWD) | v2 | 6.7 | 208 | 39.7 | 0.83 | 0.20 | 34° / 88° / 1.7 s |
| G-Wagon (AWD) | now | 8.8 | 200 | 30.0 | 0.59 | 0.10 | 31° / 114° / 0.9 s |
| G-Wagon (AWD) | v2 | 9.4 | 196 | 42.5 | 0.64 | 0.17 | 31° / 64° / 1.8 s |
| Land Cruiser | v2 | 13.5 | 149 | 39.3 | 0.68 | 0.17 | 36° / 77° / 1.9 s |
| Keke | v2 | - | 83 | - | 0.55 | 0.17 | 24° / 54° / 1.5 s |

Real-world reference (approx.): sedans 0-100 9-11 s, 100-0 37-42 m, skidpad
0.78-0.85 g; SUVs 0.65-0.75 g, 40-45 m; yaw response ~0.2-0.3 s.

Controller cost: ~130-145 µs per car per physics step on the build machine,
the same for both versions.

Bump (12 cm at 80 km/h): no wheel leaves the ground, < 1° pitch, settles in
~0.5 s, both versions.

## 4. Not done yet / known limits

- Not driven by a person yet: these are scripted tests. Feel (steering on
  touch, drift control) needs playing in the lab and on the Island map.
- AI rivals use the same physics; their braking points / corner speeds were
  tuned on the old grip and need re-checking with v2 on.
- Surface grip (dirt, kerbs) and wetness use the existing wet multiplier only.
- The camera is unchanged.
- Per-car engine data is calibrated, not manufacturer-exact.
