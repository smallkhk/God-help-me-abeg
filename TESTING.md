# How to test the game (beginner-friendly, Windows)

You don't need any coding to run this. Three steps: get the project, get Godot,
open and play.

## 1. Get the project onto your PC

Option A — download a ZIP (easiest):
1. Go to https://github.com/smallkhk/God-help-me-abeg
2. Click the green **Code** button → **Download ZIP**.
3. Unzip it somewhere easy, e.g. `Documents\God-help-me-abeg`.

Option B — if you have Git:
```
git clone https://github.com/smallkhk/God-help-me-abeg
```

## 2. Get Godot 4.4 (no installation — it's a single program)

1. Go to https://godotengine.org/download/windows
2. Download **Godot Engine 4.4.x — Standard** (NOT the “.NET/C#” one).
3. It downloads a ZIP. Unzip it. Inside is one file like
   `Godot_v4.4.2-stable_win64.exe`. Double-click it to run — there's nothing to
   install.

## 3. Open the project

1. In the window that opens (the Project Manager), click **Import**.
2. Click **Browse**, go into your unzipped `God-help-me-abeg` folder, and pick
   the file named **`project.godot`**. Click **Open**, then **Import & Edit**.
3. Godot opens the editor and spends a minute importing. Wait for the bottom
   progress bar to finish.

## 4. Play it

- **Physics test track** (the default): press **F5** (or the ▶ play button,
  top-right). You spawn on a flat track made for testing the car.
- **Third Mainland Bridge**: in the **FileSystem** panel (bottom-left), open
  `scenes/world/maps/lagos_bridge/lagos_bridge.tscn` by double-clicking it, then
  press **F6** (“Run Current Scene”). Press **W** to start the timed sprint.

### Controls
| Do | Keys |
|---|---|
| Accelerate / brake-reverse | **W** / **S** (or ↑ / ↓) |
| Steer | **A** / **D** (or ← / →) |
| Handbrake | **Space** |
| Change camera | **C** |
| Restart | **R** |
| Pause | **Esc** |
| Toggle wet road (grip drops) | **F** |
| Debug telemetry overlay | **F3** |

## 5. What to look for (acceptance checklist)

On the **test track**:
- [ ] Car sits still when you don't touch anything (no drifting/shaking).
- [ ] Accelerates straight, no weird sideways launch.
- [ ] Press **F3**: speed (km/h), gear, RPM, slip, FPS all update.
- [ ] Braking from high speed takes longer than from low speed.
- [ ] Hold **Space** mid-corner → the back slides, then recovers (no instant spin).
- [ ] Press **F** (wet) → it grips less and slides sooner. Press **F** again for dry.
- [ ] Drive over the ridge → suspension absorbs it, no crazy bounce.
- [ ] Hit the yellow barrier → it stops you, doesn't fling the car into the sky.

On the **bridge**:
- [ ] You're on a road over water with a sunset sky, lane lines, streetlights.
- [ ] Press **W**: a 3-2-1 countdown, then a timer starts.
- [ ] Drive through the glowing gates in order; the finish shows your time and
      saves your best.
- [ ] Other (AI) cars are driving along in the lanes.

If anything misbehaves, tell me exactly what you saw and I'll fix it.

## 6. (Optional) Run the automated tests yourself

These are the same checks I ran. Open **PowerShell** in the project folder
(Shift+Right-click the folder → “Open PowerShell window here”) and run, replacing
the path with wherever your Godot .exe is:

```
& "C:\path\to\Godot_v4.4.2-stable_win64.exe" --headless --path . res://tests/vehicle_physics/physics_smoke_test.tscn
& "C:\path\to\Godot_v4.4.2-stable_win64.exe" --headless --path . res://tests/vehicle_physics/acceptance_harness.tscn
& "C:\path\to\Godot_v4.4.2-stable_win64.exe" --headless --path . res://tests/map_validation/bridge_drive_test.tscn
& "C:\path\to\Godot_v4.4.2-stable_win64.exe" --headless --path . res://tests/race_flow/race_flow_test.tscn
& "C:\path\to\Godot_v4.4.2-stable_win64.exe" --headless --path . res://tests/map_validation/traffic_test.tscn
```

Each prints `PASS` or `FAIL` and exits. (The bridge/race/traffic ones take a
minute or two because they drive the full route.)
