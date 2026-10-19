#!/usr/bin/env python3
"""Race chunk for an imported 3D map model (no generated road): the loop traced
by model_route.py over the model's own road surfaces, placed in game metres.
  python3 -I model_chunk.py --path <dir>/path.npy --raster <dir> --out data/map/x/x.json \\
      --model res://assets/maps/x/x.glb --model-scale 0.01 --path-scale 1.0 --street-y -1.4 \\
      --id x --desc "..." --license "..." [--no-collision a,b] [--hide c,d]
path.npy / raster units: --path-scale converts them to game metres; --model-scale
does the same for the glb itself (e.g. 0.01 for a centimetre model)."""
import argparse, json, os, numpy as np

ap = argparse.ArgumentParser()
for a, d in [("--path", None), ("--out", None), ("--raster", ""), ("--model", None), ("--model-scale", "1"),
             ("--path-scale", "1"), ("--street-y", "0"), ("--id", "model"), ("--desc", ""), ("--license", ""),
             ("--no-collision", ""), ("--hide", ""), ("--hw", "3.2"), ("--surround", "0"), ("--recentre", "1")]:
    ap.add_argument(a, default=d, required=d is None)
A = ap.parse_args()
P = np.load(A.path)
SCALE = float(A.path_scale); STREET_Y = float(A.street_y)
OX, OZ = float(np.mean(P[:, 0])), float(np.mean(P[:, 2]))
to_game = lambda x, y, z: ((x - OX) * SCALE, (y - STREET_Y) * SCALE + 2.0, (z - OZ) * SCALE)
Q = np.c_[[to_game(*p) for p in P]]
for _ in range(12):
    Q = (np.roll(Q, 1, 0) + 2 * Q + np.roll(Q, -1, 0)) / 4
# centre every point on its own road surface (narrow roads / ramps)
if A.raster and A.recentre == "1":
    top = np.load(A.raster + '/top.npy'); kind = np.load(A.raster + '/kind.npy')
    g = json.load(open(A.raster + '/grid.json')) if os.path.exists(A.raster + '/grid.json') else {"X0": -1050, "Z0": -5800, "R": 1.0}
    X0, Z0, R = g["X0"], g["Z0"], g["R"]
    def at(x, z):
        i, j = int((z - Z0) / R), int((x - X0) / R)
        return (kind[i, j] == 3, top[i, j]) if 0 <= i < top.shape[0] and 0 <= j < top.shape[1] else (False, 0.0)
    for _ in range(3):
        M = np.c_[Q[:, 0] / SCALE + OX, Q[:, 2] / SCALE + OZ]
        d = np.roll(M, -3, 0) - np.roll(M, 3, 0)
        d /= np.linalg.norm(d, axis=1)[:, None] + 1e-9
        n = np.c_[d[:, 1], -d[:, 0]]
        stepu = R
        for k in range(len(M)):
            ok0, h0 = at(*M[k])
            if not ok0:
                continue
            ext = []
            for sgn in (-1, 1):
                o = 0.0
                while o < 40.0 / SCALE:
                    ok, h = at(*(M[k] + n[k] * sgn * (o + stepu)))
                    if not ok or abs(h - h0) > 1.2 / SCALE:
                        break
                    o += stepu
                ext.append(o)
            if ext[0] + ext[1] < 60.0 / SCALE:
                M[k] = M[k] + n[k] * (ext[1] - ext[0]) * 0.5
        Q[:, 0] = (M[:, 0] - OX) * SCALE; Q[:, 2] = (M[:, 1] - OZ) * SCALE
        Q = (np.roll(Q, 1, 0) + 2 * Q + np.roll(Q, -1, 0)) / 4
seg = np.linalg.norm(np.diff(np.vstack([Q, Q[:1]]), axis=0), axis=1)
cum = np.r_[0, np.cumsum(seg)]
L = cum[-1]
N = int(L / 3.0)
u = np.linspace(0, L, N, endpoint=False)
Rr = np.c_[[np.interp(u, cum, np.r_[Q[:, k], Q[0, k]]) for k in range(3)]].T
fwd = np.roll(Rr, -1, 0) - np.roll(Rr, 1, 0)
heading = np.arctan2(fwd[:, 0], fwd[:, 2])
samples = [{"x": round(float(Rr[i, 0]), 3), "z": round(float(Rr[i, 2]), 3), "elev_m": round(float(Rr[i, 1]), 3),
            "on_bridge": False, "dist_m": round(float(u[i]), 2), "heading_rad": round(float(heading[i]), 6)} for i in range(N)]
samples.append(dict(samples[0], dist_m=round(float(L), 2)))
cps = []
for k in range(1, 9):
    i = int(N * k / 8) % N if k < 8 else 0
    s = samples[i]
    cps.append({"x": s["x"], "y": s["elev_m"], "z": s["z"], "heading_rad": s["heading_rad"], "dist_m": round(float(L if k == 8 else u[i]), 2)})
sp = samples[0]
hw = float(A.hw)
ms = float(A.model_scale)
chunk = {
    "chunk_id": A.id, "description": A.desc,
    "approximate": False, "no_landmarks": True, "district": False, "loop": True, "ambient_traffic": False,
    "model": {"path": A.model, "scale": ms,
              # glb space -> game: scale, then shift so the loop is centred and streets sit at y = 2
              "offset": [-OX * SCALE, 2.0 - STREET_Y * SCALE, -OZ * SCALE],
              "no_collision": [s for s in A.no_collision.split(",") if s], "hide": [s for s in A.hide.split(",") if s]},
    "road": {"half_width_m": hw, "barrier_height_m": 0.0, "lanes_per_direction": 2, "lane_width_m": hw - 0.4,
             "median_width_m": -2 * (hw - 0.4), "length_m": round(float(L), 2), "samples": samples},
    "sections": [], "bridge": {"water_level_y": -50.0}, "buildings": [], "crossings": [],
    "start_line": {"dist_m": 0.0},
    "spawn": {"x": sp["x"], "y": sp["elev_m"] + 0.6, "z": sp["z"], "heading_rad": sp["heading_rad"]},
    "checkpoints": cps, "shortcuts": [],
    "source": {"type": "model", "license": A.license},
}
# --surround R: the model is one district with nothing round it. Fill the empty
# land (no model geometry under the lot or within 4 m of it) out to R metres
# with plain city blocks: a near row of mid-rise, taller towers further out.
if float(A.surround) > 0 and A.raster:
    top = np.load(A.raster + '/top.npy'); kind = np.load(A.raster + '/kind.npy')
    g = json.load(open(A.raster + '/grid.json')); X0, Z0, R = g["X0"], g["Z0"], g["R"]
    # model footprint grown by 4 m
    from scipy import ndimage
    used = ndimage.binary_dilation(kind > 0, iterations=int(4.0 / (R * SCALE)))
    H, W = used.shape
    ext = float(A.surround) / SCALE
    rng = np.random.default_rng(3)
    occ = {}
    blds = []
    cell = 4.0 / SCALE
    xs = np.arange(X0 - ext, X0 + W * R + ext, cell); zs = np.arange(Z0 - ext, Z0 + H * R + ext, cell)
    taken = np.zeros((len(zs), len(xs)), bool)
    def free_model(x0, z0, x1, z1):
        j0, j1 = int((x0 - X0) / R), int((x1 - X0) / R); i0, i1 = int((z0 - Z0) / R), int((z1 - Z0) / R)
        j0c, j1c = max(j0, 0), min(j1, W - 1); i0c, i1c = max(i0, 0), min(i1, H - 1)
        if j0c > j1c or i0c > i1c:
            return True
        return not used[i0c:i1c + 1, j0c:j1c + 1].any()
    order = rng.permutation(len(xs) * len(zs))
    for o in order:
        i, j = divmod(int(o), len(xs))
        if taken[i, j]:
            continue
        w = int(rng.integers(3, 6)); d = int(rng.integers(3, 6))
        if i + d > len(zs) or j + w > len(xs) or taken[i:i + d, j:j + w].any():
            continue
        x0, z0 = xs[j], zs[i]; x1, z1 = x0 + (w - 0.5) * cell, z0 + (d - 0.5) * cell
        if not free_model(x0, z0, x1, z1):
            continue
        taken[max(0, i - 1):i + d + 1, max(0, j - 1):j + w + 1] = True   # a street's width between blocks
        # distance to the model decides height: mid-rise near, towers behind
        cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
        far = max(X0 - cx, cx - (X0 + W * R), Z0 - cz, cz - (Z0 + H * R), 0.0) * SCALE
        hgt = float(rng.uniform(14, 30) if far < 40 else rng.uniform(30, 95))
        pts = [to_game(x0, STREET_Y, z0), to_game(x1, STREET_Y, z0), to_game(x1, STREET_Y, z1), to_game(x0, STREET_Y, z1)]
        blds.append({"pts": [[round(p[0], 2), round(p[2], 2)] for p in pts], "h": round(hgt, 1)})
    chunk_surround = {"buildings": blds, "ground_y": 2.0 - 0.12}
    print("surround: %d blocks" % len(blds))
else:
    chunk_surround = None
os.makedirs(os.path.dirname(A.out), exist_ok=True)
if chunk_surround:
    chunk["model"]["surround"] = chunk_surround
json.dump(chunk, open(A.out, "w"), separators=(",", ":"))
print("loop %.0f m, %d samples, y %.1f..%.1f" % (L, N, Rr[:, 1].min(), Rr[:, 1].max()))
