"""Procedural 'Hills' track for Terrain3D.
Writes data/map/hills/heights.bin (float32, N x N, row = z) + hills_loop.json
(chunk in the same format as the city maps: road samples, checkpoints, spawn) plus
tree and grass scatter positions that sit exactly on the terrain."""
import json, math, os, sys
import numpy as np
OUT = sys.argv[1] if len(sys.argv) > 1 else "data/map/hills"
N, SP = 1024, 2.0                    # 1024 px * 2 m = 2048 m square
X0 = -N * SP / 2                     # world x/z of pixel 0
rng = np.random.default_rng(7)

def fbm(n, octaves=6, base=4):
    out = np.zeros((n, n))
    amp, freq = 1.0, base
    for _ in range(octaves):
        g = rng.standard_normal((freq + 1, freq + 1))
        # bicubic-ish upsample of random grid
        xs = np.linspace(0, freq, n)
        i0 = np.floor(xs).astype(int).clip(0, freq - 1); t = xs - i0
        t = t * t * (3 - 2 * t)
        a = g[i0][:, i0] * (1 - t)[None, :] + g[i0][:, i0 + 1] * t[None, :]
        b = g[i0 + 1][:, i0] * (1 - t)[None, :] + g[i0 + 1][:, i0 + 1] * t[None, :]
        out += amp * (a * (1 - t)[:, None] + b * t[:, None])
        amp *= 0.5; freq *= 2
    return out

H = fbm(N)
H = (H - H.min()) / (H.max() - H.min())
H = H ** 1.6 * 70.0 + 2.0             # 2..72 m hills, flatter valleys

def height_at(x, z):
    fx = (x - X0) / SP; fz = (z - X0) / SP
    i = int(np.clip(fx, 0, N - 2)); j = int(np.clip(fz, 0, N - 2)); tx = fx - i; tz = fz - j
    return (H[j, i] * (1 - tx) * (1 - tz) + H[j, i + 1] * tx * (1 - tz) +
            H[j + 1, i] * (1 - tx) * tz + H[j + 1, i + 1] * tx * tz)

# --- winding loop road ---
pts = []
for k in range(2400):
    th = 2 * math.pi * k / 2400
    r = 650 + 160 * math.sin(3 * th + 0.4) + 90 * math.sin(5 * th + 1.3) + 40 * math.sin(9 * th)
    pts.append((r * math.cos(th), r * math.sin(th)))
# resample every 6 m
res = [pts[0]]; acc = 0.0
for (ax, az), (bx, bz) in zip(pts, pts[1:] + pts[:1]):
    seg = math.hypot(bx - ax, bz - az); d = 0.0
    while acc + seg - d >= 6.0:
        d += 6.0 - acc; acc = 0.0
        t = d / seg; res.append((ax + (bx - ax) * t, az + (bz - az) * t))
    acc += seg - d
# road elevation: terrain height heavily smoothed (keeps grades driveable)
raw = np.array([height_at(x, z) for x, z in res])
k = 61; pad = np.concatenate([raw[-k:], raw, raw[:k]])
sm = np.convolve(pad, np.ones(k) / k, mode="same")[k:-k]
sm = np.convolve(np.concatenate([sm[-k:], sm, sm[:k]]), np.ones(k) / k, mode="same")[k:-k]
road_elev = sm + 0.3

HW = 12.1
# carve/fill terrain to the road (flat bed + smooth shoulders)
gx = X0 + np.arange(N) * SP
GX, GZ = np.meshgrid(gx, gx)
best_d = np.full((N, N), 1e9); best_e = np.zeros((N, N))
for (x, z), e in zip(res[::2], road_elev[::2]):
    i0 = max(int((x - X0) / SP) - 30, 0); i1 = min(int((x - X0) / SP) + 31, N)
    j0 = max(int((z - X0) / SP) - 30, 0); j1 = min(int((z - X0) / SP) + 31, N)
    d = np.hypot(GX[j0:j1, i0:i1] - x, GZ[j0:j1, i0:i1] - z)
    m = d < best_d[j0:j1, i0:i1]
    best_d[j0:j1, i0:i1][m] = d[m]; best_e[j0:j1, i0:i1][m] = e
w = np.clip((best_d - (HW + 3)) / 40.0, 0, 1); w = w * w * (3 - 2 * w)
H = (best_e - 0.25) * (1 - w) + H * w
H = H.astype(np.float32)

samples = []; dist = 0.0
for i, (x, z) in enumerate(res):
    nx, nz = res[(i + 1) % len(res)]
    if i: dist += math.hypot(x - res[i - 1][0], z - res[i - 1][1])
    samples.append({"x": round(x, 3), "z": round(z, 3), "elev_m": round(float(road_elev[i]), 3),
                    "on_bridge": False, "dist_m": round(dist, 2), "heading_rad": math.atan2(nx - x, nz - z)})
samples.append(dict(samples[0], dist_m=round(dist + 6.0, 2)))   # close the loop
cps = []
for ci, frac in enumerate([0.15, 0.35, 0.55, 0.75, 0.97]):
    s = samples[int(frac * (len(samples) - 1))]
    cps.append({"index": ci, "x": s["x"], "z": s["z"], "y": s["elev_m"], "heading_rad": s["heading_rad"], "dist_m": s["dist_m"]})
s0 = samples[3]
# trees + grass spots on the slopes (not on the road)
trees, grass = [], []
r2 = np.random.default_rng(11)
for _ in range(40000):
    x, z = r2.uniform(X0 + 20, -X0 - 20, 2)
    fx, fz = int((x - X0) / SP), int((z - X0) / SP)
    d = best_d[fz, fx]
    if d < HW + 6 or d > 260: continue
    y = float(height_at(x, z)) if False else float(H[fz, fx])
    if len(trees) < 1800 and r2.random() < 0.35:
        trees.append([round(x, 2), round(y, 2), round(z, 2)])
    if d < 120:
        grass.append([round(x, 2), round(y, 2), round(z, 2)])
os.makedirs(OUT, exist_ok=True)
H.tofile(os.path.join(OUT, "heights.bin"))
chunk = {"chunk_id": "hills_loop", "description": "Procedural hills loop (Terrain3D)", "approximate": True,
         "geo_origin": {"lat": 6.6, "lon": 3.5}, "bounds_local_m": [X0, X0, -X0, -X0],
         "terrain": {"heights": "res://data/map/hills/heights.bin", "size_px": N, "spacing": SP, "origin": X0},
         "road": {"half_width_m": HW, "barrier_height_m": 0.9, "lanes_per_direction": 3, "lane_width_m": 3.5,
                  "median_width_m": 1.2, "length_m": dist, "samples": samples},
         "bridge": {"deck_thickness_m": 1.2, "support_spacing_m": 40.0, "support_width_m": 2.0, "water_level_y": -50.0, "pier_foot_y": -60.0},
         "buildings": [], "osm_buildings": [], "land_cells": {"cell_m": 50.0, "cells": []},
         "spawn": {"x": s0["x"], "y": s0["elev_m"] + 0.5, "z": s0["z"], "heading_rad": s0["heading_rad"]},
         "checkpoints": cps, "trees": trees, "grass": grass[:6000],
         "source": {"type": "procedural", "license": "generated"}}
json.dump(chunk, open(os.path.join(OUT, "hills_loop.json"), "w"))
g = np.diff(road_elev) / 6.0
print("road %.0f m, %d samples, elev %.1f..%.1f m, max grade %.1f%%, trees %d, grass %d" %
      (dist, len(samples), road_elev.min(), road_elev.max(), 100 * abs(g).max(), len(trees), len(grass)))
