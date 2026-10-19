#!/usr/bin/env python3
"""Race chunk for an imported 3D map model (no generated road): the route traced
by model_route.py over the model's own road surfaces, scaled into game metres.
  python3 -I tools/lagos_map_pipeline/model_chunk.py path.npy out.json [raster_dir]
path.npy: [x, y, z] points in model units along the loop (start = first point)."""
import json, sys, numpy as np

P = np.load(sys.argv[1])
# optional: top-down road raster (model_route.py) to centre every point on its own surface
RASTER = sys.argv[3] if len(sys.argv) > 3 else ""
SCALE = 0.4                  # the model is built ~2.5x real size
STREET_Y = 5.0               # model height of the street grid -> game y 2.0
OX, OZ = float(np.mean(P[:, 0])), float(np.mean(P[:, 2]))
Q = np.c_[(P[:, 0] - OX) * SCALE, (P[:, 1] - STREET_Y) * SCALE + 2.0, (P[:, 2] - OZ) * SCALE]
# smooth the grid-cell path, then resample every 3 m (closed loop)
for _ in range(12):
    Q = (np.roll(Q, 1, 0) + 2 * Q + np.roll(Q, -1, 0)) / 4
if RASTER:
    top = np.load(RASTER + '/top.npy'); kind = np.load(RASTER + '/kind.npy')
    X0, Z0 = -1050, -5800
    def at(x, z):
        i, j = int(z - Z0), int(x - X0)
        return (kind[i, j] == 3, top[i, j]) if 0 <= i < top.shape[0] and 0 <= j < top.shape[1] else (False, 0.0)
    for _ in range(3):
        M = np.c_[Q[:, 0] / SCALE + OX, Q[:, 2] / SCALE + OZ]
        d = np.roll(M, -3, 0) - np.roll(M, 3, 0)
        d /= np.linalg.norm(d, axis=1)[:, None] + 1e-9
        n = np.c_[d[:, 1], -d[:, 0]]
        for k in range(len(M)):
            ok0, h0 = at(*M[k])
            if not ok0:
                continue
            lo = hi = 0.0
            for sgn in (-1, 1):
                o = 0.0
                while o < 40.0:
                    ok, h = at(*(M[k] + n[k] * sgn * (o + 1.0)))
                    if not ok or abs(h - h0) > 1.2:
                        break
                    o += 1.0
                if sgn < 0: lo = o
                else: hi = o
            if lo + hi < 60.0:            # narrow road (ramp, street): centre on it
                M[k] = M[k] + n[k] * (hi - lo) * 0.5
        Q[:, 0] = (M[:, 0] - OX) * SCALE; Q[:, 2] = (M[:, 1] - OZ) * SCALE
        Q = (np.roll(Q, 1, 0) + 2 * Q + np.roll(Q, -1, 0)) / 4
seg = np.linalg.norm(np.diff(np.vstack([Q, Q[:1]]), axis=0), axis=1)
cum = np.r_[0, np.cumsum(seg)]
L = cum[-1]
N = int(L / 3.0)
u = np.linspace(0, L, N, endpoint=False)
R = np.c_[[np.interp(u, cum, np.r_[Q[:, k], Q[0, k]]) for k in range(3)]].T
fwd = np.roll(R, -1, 0) - np.roll(R, 1, 0)
heading = np.arctan2(fwd[:, 0], fwd[:, 2])
samples = [{"x": round(float(R[i, 0]), 3), "z": round(float(R[i, 2]), 3), "elev_m": round(float(R[i, 1]), 3),
            "on_bridge": False, "dist_m": round(float(u[i]), 2), "heading_rad": round(float(heading[i]), 6)} for i in range(N)]
samples.append(dict(samples[0], dist_m=round(float(L), 2)))
cps = []
for k in range(1, 9):
    i = int(N * k / 8) % N if k < 8 else 0
    s = samples[i]
    cps.append({"x": s["x"], "y": s["elev_m"], "z": s["z"], "heading_rad": s["heading_rad"], "dist_m": round(float(L if k == 8 else u[i]), 2)})
sp = samples[int(30 / 3)]       # grid 30 m after the line... spawn at the line
sp = samples[0]
chunk = {
    "chunk_id": "nyc_i95", "description": "New York: Washington Heights / I-95 interchange (model by 99.Miles)",
    "approximate": False, "no_landmarks": True, "district": False, "loop": True, "ambient_traffic": False,
    "model": {"path": "res://assets/maps/nyc/i95.glb", "scale": SCALE, "offset": [-OX * SCALE, (2.0 - STREET_Y * SCALE), -OZ * SCALE],
              "no_collision": ["Trees_Sheet", "Water", "beams_transparent", "fence_transparent", "Bridge_Fence_Trim_Transparent"]},
    "road": {"half_width_m": 3.2, "barrier_height_m": 0.0, "lanes_per_direction": 2, "lane_width_m": 2.8,
             "median_width_m": -5.6, "length_m": round(float(L), 2), "samples": samples},
    "sections": [], "bridge": {"water_level_y": -50.0}, "buildings": [], "crossings": [],
    "start_line": {"dist_m": 0.0},
    "spawn": {"x": sp["x"], "y": sp["elev_m"] + 0.6, "z": sp["z"], "heading_rad": sp["heading_rad"]},
    "checkpoints": cps, "shortcuts": [],
    "source": {"type": "model", "license": "Sketchfab Free Standard - 'New York, Highway Interstate 95' by 99.Miles"},
}
json.dump(chunk, open(sys.argv[2], "w"), separators=(",", ":"))
print("loop %.0f m, %d samples, y %.1f..%.1f, offset %s" % (L, N, R[:, 1].min(), R[:, 1].max(), chunk["model"]["offset"]))
