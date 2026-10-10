"""Procedural 'Lagos Island' free-roam / race city: a 5+ km street loop (Marina
waterfront on the south, Broad Street, a Balogun-market S-bend on the north)
through a dense grid of city blocks, surrounded by lagoon. Writes a chunk in the
same format as the OSM maps so MapBuilder fills it with the Lagos house / plaza /
uncompleted-building models, props, people and moving traffic."""
import json, math, os, sys
import numpy as np
OUT = sys.argv[1] if len(sys.argv) > 1 else "data/map/island"
rng = np.random.default_rng(1861)
HW = 9.0
ELEV = 2.0
X1, Z1 = 1300.0, 800.0          # island half-extent (land)

# --- loop: rounded rectangle with a north S-bend (Balogun) and Marina curve ---
def loop_pts():
    pts = []
    for k in range(4000):
        t = 2 * math.pi * k / 4000
        x = 900 * np.sign(math.cos(t)) * abs(math.cos(t)) ** 0.25
        z = 520 * np.sign(math.sin(t)) * abs(math.sin(t)) ** 0.25
        if z > 300:      # Balogun S-bend
            z += 90 * math.sin(x / 140.0)
        if z < -300:     # Marina gently follows the waterfront
            z -= 40 * math.cos(x / 400.0)
        pts.append((x, z))
    return pts
pts = loop_pts()
res = [pts[0]]; acc = 0.0
for (ax, az), (bx, bz) in zip(pts, pts[1:] + pts[:1]):
    seg = math.hypot(bx - ax, bz - az); d = 0.0
    while acc + seg - d >= 6.0:
        d += 6.0 - acc; acc = 0.0
        t = d / seg; res.append((ax + (bx - ax) * t, az + (bz - az) * t))
    acc += seg - d
R = np.array(res)
samples = []; dist = 0.0
for i, (x, z) in enumerate(res):
    nx, nz = res[(i + 1) % len(res)]
    if i: dist += math.hypot(x - res[i - 1][0], z - res[i - 1][1])
    samples.append({"x": round(x, 3), "z": round(z, 3), "elev_m": ELEV, "on_bridge": False,
                    "dist_m": round(dist, 2), "heading_rad": math.atan2(nx - x, nz - z)})
samples.append(dict(samples[0], dist_m=round(dist + 6.0, 2)))

def road_d(px, pz):
    return np.sqrt(((R[None, :, 0] - px[:, None]) ** 2 + (R[None, :, 1] - pz[:, None]) ** 2).min(axis=1))

# --- city blocks on a street grid ---
BX, BZ, SW = 95.0, 80.0, 9.0     # block pitch x/z, street width
blds, streets = [], []
for gx in np.arange(-X1, X1 + 1, BX):
    streets.append({"w": SW, "pts": [[round(gx, 1), -Z1], [round(gx, 1), Z1]]})
for gz in np.arange(-Z1, Z1 + 1, BZ):
    streets.append({"w": SW, "pts": [[-X1, round(gz, 1)], [X1, round(gz, 1)]]})
lots = []
for bx0 in np.arange(-X1, X1, BX):
    for bz0 in np.arange(-Z1, Z1, BZ):
        x0, x1 = bx0 + SW / 2 + 2, bx0 + BX - SW / 2 - 2
        z0, z1 = bz0 + SW / 2 + 2, bz0 + BZ - SW / 2 - 2
        # two rows of lots, front to the street on each long side
        for (za, zb) in [(z0, (z0 + z1) / 2 - 1), ((z0 + z1) / 2 + 1, z1)]:
            x = x0
            while x < x1 - 8:
                w = float(rng.uniform(9, 24)); w = min(w, x1 - x)
                lots.append((x, za, x + w - 1.5, zb))
                x += w
L = np.array(lots)
cx = (L[:, 0] + L[:, 2]) / 2; cz = (L[:, 1] + L[:, 3]) / 2
dd = np.concatenate([road_d(cx[i:i + 2000], cz[i:i + 2000]) for i in range(0, len(cx), 2000)])
# corners must clear the road too
for (ix, iz) in [(0, 1), (2, 1), (0, 3), (2, 3)]:
    cd = np.concatenate([road_d(L[i:i + 2000, ix], L[i:i + 2000, iz]) for i in range(0, len(L), 2000)])
    dd = np.minimum(dd, cd + 0.0)
for (x0, z0, x1, z1), d, czz in zip(L, dd, cz):
    if d < HW + 5:
        continue
    if czz < -480 and rng.random() < 0.7:          # Marina: towers
        h = float(rng.uniform(35, 110))
    elif d < 150:
        h = float(rng.uniform(6, 12))
    else:
        h = float(rng.uniform(7, 30)) if rng.random() < 0.8 else float(rng.uniform(30, 60))
    blds.append({"pts": [[round(x0, 2), round(z0, 2)], [round(x1, 2), round(z0, 2)], [round(x1, 2), round(z1, 2)], [round(x0, 2), round(z1, 2)]],
                 "h": round(h, 1), "d": round(float(d), 1)})
cells = [[i, j] for i in range(int(-X1 // 50) - 1, int(X1 // 50) + 1) for j in range(int(-Z1 // 50) - 1, int(Z1 // 50) + 1)]
cps = []
for ci, frac in enumerate([0.12, 0.3, 0.5, 0.7, 0.97]):
    s = samples[int(frac * (len(samples) - 1))]
    cps.append({"index": ci, "x": s["x"], "z": s["z"], "y": ELEV, "heading_rad": s["heading_rad"], "dist_m": s["dist_m"]})
s0 = samples[3]
chunk = {"chunk_id": "lagos_island", "description": "Lagos Island street loop (procedural: Marina, Broad St, Balogun)",
         "approximate": True, "no_landmarks": True,
         "geo_origin": {"lat": 6.452, "lon": 3.39}, "bounds_local_m": {"min_x": -X1, "max_x": X1, "min_z": -Z1, "max_z": Z1},
         "road": {"half_width_m": HW, "barrier_height_m": 0.25, "lanes_per_direction": 2, "lane_width_m": 3.6,
                  "median_width_m": 1.0, "length_m": dist, "samples": samples},
         "bridge": {"deck_thickness_m": 1.2, "support_spacing_m": 40.0, "support_width_m": 2.0, "water_level_y": 0.0, "pier_foot_y": -6.0},
         "buildings": [], "osm_buildings": blds, "side_streets": streets,
         "land_cells": {"cell_m": 50.0, "cells": cells},
         "spawn": {"x": s0["x"], "y": ELEV + 0.5, "z": s0["z"], "heading_rad": s0["heading_rad"]},
         "checkpoints": cps, "source": {"type": "procedural", "license": "generated"}}
os.makedirs(OUT, exist_ok=True)
json.dump(chunk, open(os.path.join(OUT, "lagos_island.json"), "w"))
print("loop %.0f m, %d samples, %d buildings (%d near road), %d streets" % (dist, len(samples), len(blds), sum(1 for b in blds if b["d"] < 150), len(streets)))
