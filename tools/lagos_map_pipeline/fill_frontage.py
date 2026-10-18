#!/usr/bin/env python3
"""Fill the empty roadside plots of an OSM district circuit with Lagos life.

Real OSM footprints only cover part of the frontage (VI / Ikoyi have big open
plots). This walks both sides of the route and, wherever nothing real stands,
adds: shop blocks, Lagos houses, uncompleted buildings, walled compounds with
steel gates and trees, roadside businesses (mechanic, mama put, vulcaniser,
suya, kiosk + generator), okada / keke ranks, and the odd landmark (petrol
station, bank, church, mosque). Re-running replaces the previous fill.

  python3 -I tools/lagos_map_pipeline/fill_frontage.py data/map/vi/victoria_island.json [seed]
"""
import json, sys
import numpy as np

path = sys.argv[1]
rng = np.random.default_rng(int(sys.argv[2]) if len(sys.argv) > 2 else 7)
chunk = json.load(open(path))
HW = float(chunk["road"]["half_width_m"])
PAVE = float(chunk.get("pavement_m", 3.0))
chunk["osm_buildings"] = [b for b in chunk["osm_buildings"] if not b.get("fill")]
walls, trees, props = [], [], []

S = chunk["road"]["samples"][:-1]
R = np.array([[s["x"], s["z"]] for s in S])
N = len(R)
dist = np.array([s["dist_m"] for s in S])
hd = np.array([s["heading_rad"] for s in S])
perp = np.c_[np.cos(hd), -np.sin(hd)]          # right of travel (same as map_builder)

# every surface a car can drive on, with the clearance a lot must keep from it
road_pts, road_clr = [R], [np.full(N, HW + PAVE + 0.3)]
for ss in chunk.get("side_streets", []):
    P = np.array(ss["pts"], float)
    for a, b in zip(P[:-1], P[1:]):
        k = max(2, int(np.linalg.norm(b - a) / 1.5))
        road_pts.append(a + (b - a) * np.linspace(0, 1, k)[:, None])
        road_clr.append(np.full(k, float(ss.get("w", 6.0)) * 0.5 + PAVE + 0.5))
for sc in chunk.get("shortcuts", []):
    P = np.array([[s["x"], s["z"]] for s in sc["samples"]])
    road_pts.append(P); road_clr.append(np.full(len(P), float(sc.get("hw", 4.0)) + PAVE + 1.0))
RP = np.vstack(road_pts); RC = np.concatenate(road_clr)


def clear_of_road(poly, extra=0.0):
    poly = np.asarray(poly)
    c = poly.mean(0)
    pts = np.vstack([poly, (poly + np.roll(poly, -1, 0)) * 0.5, c, (poly + c) * 0.5])
    d = np.linalg.norm(pts[:, None, :] - RP[None, :, :], axis=2)
    return bool(((d - RC[None, :]) >= extra).all())


def road_dist(p):
    return float(np.linalg.norm(R - np.asarray(p), axis=1).min())


# occupancy raster: real buildings + what we place
X0, Z0 = R.min(0) - 200; X1, Z1 = R.max(0) + 200
RES = 0.5
occ = np.zeros((int((Z1 - Z0) / RES) + 1, int((X1 - X0) / RES) + 1), bool)


def cells(poly):
    poly = np.asarray(poly, float)
    lo = np.maximum(np.floor((poly.min(0) - [X0, Z0]) / RES).astype(int), 0)
    hi = np.ceil((poly.max(0) - [X0, Z0]) / RES).astype(int)
    xs = X0 + (np.arange(lo[0], hi[0]) + 0.5) * RES
    zs = Z0 + (np.arange(lo[1], hi[1]) + 0.5) * RES
    gx, gz = np.meshgrid(xs, zs)
    ins = np.ones_like(gx, bool)
    sa = sum(poly[k][0] * poly[(k + 1) % len(poly)][1] - poly[(k + 1) % len(poly)][0] * poly[k][1] for k in range(len(poly)))
    for k in range(len(poly)):
        x1, z1 = poly[k]; x2, z2 = poly[(k + 1) % len(poly)]
        cr = (x2 - x1) * (gz - z1) - (z2 - z1) * (gx - x1)
        ins &= (cr >= 0) if sa > 0 else (cr <= 0)
    return lo, hi, ins


def free(poly):
    lo, hi, ins = cells(poly)
    sub = occ[lo[1]:hi[1], lo[0]:hi[0]]
    return not (sub & ins[:sub.shape[0], :sub.shape[1]]).any()


def mark(poly):
    lo, hi, ins = cells(poly)
    sub = occ[lo[1]:hi[1], lo[0]:hi[0]]
    sub |= ins[:sub.shape[0], :sub.shape[1]]


def grow(poly, m):
    poly = np.asarray(poly, float); c = poly.mean(0)
    return c + (poly - c) * (1.0 + m / max(np.linalg.norm(poly - c, axis=1).min(), 0.5))


for b in chunk["osm_buildings"]:
    mark(grow(b["pts"], 1.0))


def ccw(poly):
    sa = sum(poly[k][0] * poly[(k + 1) % 4][1] - poly[(k + 1) % 4][0] * poly[k][1] for k in range(4))
    return poly if sa > 0 else poly[::-1]


def r2(p):
    return [round(float(p[0]), 2), round(float(p[1]), 2)]


def wall(a, b, h, col, kind="wall", t=0.25):
    walls.append({"a": r2(a), "b": r2(b), "h": round(h, 2), "t": t, "k": kind, "c": [round(c, 3) for c in col]})


def prop(model, p, face, sc=1.0, lift=0.0, col=None, yaw_off=0.0):
    # models face +X: yaw so +X points along `face`
    yaw = float(np.arctan2(-face[1], face[0])) + yaw_off
    e = [model, round(float(p[0]), 2), round(lift, 2), round(float(p[1]), 2), round(yaw, 4), round(sc, 3)]
    if col:
        e += [round(col[0] * sc, 2), round(col[1] * sc, 2)]
    props.append(e)


WALLS = [[0.95, 0.89, 0.74], [0.97, 0.84, 0.52], [0.96, 0.74, 0.60], [0.66, 0.80, 0.90],
         [0.74, 0.88, 0.74], [0.96, 0.96, 0.93], [0.93, 0.76, 0.78], [0.88, 0.62, 0.46]]
# real size of each Lagos model at scale 1 (depth along its front axis, width)
LANDMARK = {"petrol": (15.0, 22.0), "bank": (13.6, 13.7), "church": (24.0, 15.2), "mosque": (23.7, 26.0)}
BUSINESS = {"mechanic": (7.6, 8.0), "mamaput": (5.8, 6.0), "vulcaniser": (1.9, 3.5), "suya": (2.6, 3.5),
            "villagekiosk": (2.7, 4.0)}
next_landmark = {k: rng.uniform(80, 400) for k in LANDMARK}
counts = {}


def pick(on_bend, d_here):
    if on_bend:
        return "block" if rng.random() < 0.7 else "house"
    for k in LANDMARK:
        if d_here >= next_landmark[k] and rng.random() < 0.08:
            return k
    r = rng.random()
    if r < 0.26: return "block"
    if r < 0.40: return "house"
    if r < 0.48: return "unfinished"
    if r < 0.68: return "compound"
    if r < 0.88: return "business"
    return "rank"


def size(kind):
    if kind in LANDMARK:
        d, w = LANDMARK[kind]; return w + 6.0, d + 6.0
    if kind == "house": s = rng.uniform(1.15, 1.45); return 6.4 * s, 6.1 * s
    if kind == "unfinished": s = rng.uniform(1.0, 1.3); return 8.76 * s, 7.0 * s
    if kind == "compound": return rng.uniform(14, 22), rng.uniform(13, 18)
    if kind == "business": return rng.uniform(10, 14), rng.uniform(8, 11)
    if kind == "rank": return rng.uniform(8, 11), rng.uniform(5, 7)
    return rng.uniform(8, 15), rng.uniform(9, 13)


RAD = np.full(N, 1e9)
for i in range(N):
    a, b, c = R[i - 4], R[i], R[(i + 4) % N]
    cr = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    RAD[i] = np.linalg.norm(b - a) * np.linalg.norm(c - b) * np.linalg.norm(a - c) / (2 * abs(cr) + 1e-9)

FRONT = HW + PAVE + 0.5
step = float(np.median(np.diff(dist)))
for side in (1.0, -1.0):
    Q = R + perp * side * FRONT
    seg = np.linalg.norm(np.diff(np.vstack([Q, Q[:1]]), axis=0), axis=1)
    cum = np.r_[0, np.cumsum(seg)]

    def at(u):
        u = u % cum[-1]
        k = int(np.searchsorted(cum, u, side="right") - 1)
        t = (u - cum[k]) / max(cum[k + 1] - cum[k], 1e-6)
        return Q[k] + (Q[(k + 1) % N] - Q[k]) * t, k

    u = 0.0
    while u < cum[-1] - 6.0:
        pa, ka = at(u)
        ci = ka % N
        on_bend = RAD[max(ci - 5, 0):ci + 5].min() < 70
        kind = pick(on_bend, dist[ci])
        placed = False
        for attempt in range(3):
            w, dp = size(kind)
            if attempt == 2:
                w *= 0.75; dp *= 0.75
            pb, _ = at(u + w)
            chord = pb - pa
            if np.linalg.norm(chord) < w * 0.8:
                break                                   # tight inside bend
            t = chord / np.linalg.norm(chord)
            n = np.array([t[1], -t[0]])
            if np.dot(n, perp[ci] * side) < 0:
                n = -n                                  # away from the road
            sb = 0.0 if kind in ("compound", "rank") else rng.uniform(0.0, 1.0)
            f0 = pa + n * sb; f1 = pb + n * sb
            poly = [f0, f1, f1 + n * dp, f0 + n * dp]
            if not (free(poly) and clear_of_road(poly)):
                if kind in LANDMARK or kind == "compound":
                    kind = "block"
                continue
            mark(grow(poly, 0.3))
            front = -n
            mid = (f0 + f1) * 0.5
            col = WALLS[rng.integers(len(WALLS))]
            pp = ccw([r2(q) for q in poly])
            if kind == "block":
                storeys = int(rng.choice([2, 2, 3, 3, 3, 4]))
                chunk["osm_buildings"].append({"pts": pp, "h": round(storeys * 3.2 + rng.uniform(0.2, 0.9), 1),
                                               "d": round(road_dist(mid), 1), "fill": 1})
            elif kind in ("house", "unfinished"):
                model = "lagos_house/house" if kind == "house" else "unfinished/unfinished"
                chunk["osm_buildings"].append({"pts": pp, "h": round(6.0 * w / (6.4 if kind == "house" else 8.76), 1),
                                               "d": round(road_dist(mid), 1), "m": model, "f": r2(front),
                                               "w": round(w, 2), "dp": round(dp, 2), "fill": 1})
            elif kind == "compound":
                gw = 3.6; g0 = 0.5 - gw / (2 * w) + rng.uniform(-0.2, 0.2)
                ga = f0 + (f1 - f0) * g0; gb = f0 + (f1 - f0) * (g0 + gw / w)
                h = rng.uniform(2.2, 2.7); wc = [c * 0.92 for c in col]
                wall(f0, ga, h, wc); wall(gb, f1, h, wc); wall(ga, gb, h - 0.2, [0.12, 0.13, 0.15], "gate")
                wall(f0, f0 + n * dp, h, wc); wall(f1, f1 + n * dp, h, wc); wall(f0 + n * dp, f1 + n * dp, h, wc)
                hs = rng.uniform(1.15, 1.4); hdp, hwid = 6.1 * hs, 6.4 * hs
                hc = mid + n * (dp - hdp * 0.5 - 1.0)
                hp = [hc + t * hwid / 2 + n * hdp / 2, hc - t * hwid / 2 + n * hdp / 2, hc - t * hwid / 2 - n * hdp / 2, hc + t * hwid / 2 - n * hdp / 2]
                chunk["osm_buildings"].append({"pts": ccw([r2(q) for q in hp]), "h": round(6.0 * hs, 1), "d": round(road_dist(hc), 1),
                                               "m": "lagos_house/house", "f": r2(front), "w": round(hwid, 2), "dp": round(hdp, 2),
                                               "nocol": True, "fill": 1})
                for k in range(int(rng.integers(1, 4))):
                    tp = f0 + (f1 - f0) * rng.uniform(0.1, 0.9) + n * rng.uniform(1.8, 3.0)
                    if np.linalg.norm(tp - (ga + gb) * 0.5) > 2.5:
                        trees.append(r2(tp) + [str(rng.choice(["almond", "coconut", "bush"], p=[0.45, 0.35, 0.2]))])
            elif kind in LANDMARK:
                d0, w0 = LANDMARK[kind]
                pc = mid + n * (3.0 + d0 * 0.5)
                prop("lagos/" + kind, pc, front, 1.0, -0.05, (d0, w0))
                next_landmark[kind] = dist[ci] + rng.uniform(900, 1600)
                for e in (f0, f1):                       # low boundary wall + palms either side
                    wall(e, e + n * dp, 1.4, [0.9, 0.9, 0.86])
                    trees.append(r2(e + n * 2.0 + (t if e is f0 else -t) * 1.5) + ["coconut"])
            elif kind == "business":
                biz = str(rng.choice(list(BUSINESS), p=[0.3, 0.25, 0.2, 0.15, 0.1]))
                d0, w0 = BUSINESS[biz]
                pc = mid + n * (1.2 + d0 * 0.5) + t * rng.uniform(-1.0, 1.0)
                prop("lagos/" + biz, pc, front, 1.0, -0.05, (d0, w0) if d0 > 3.0 else None)
                wall(f0 + n * dp, f1 + n * dp, 2.4, [c * 0.9 for c in col])   # back wall closes the plot
                g = pc + t * (w0 * 0.5 + 1.2) * (1 if rng.random() < 0.5 else -1)
                prop("lagos/generator", g, front, 1.0, -0.05)
                if rng.random() < 0.6:
                    trees.append(r2(f0 + n * (dp - 2.0) + t * 1.5) + ["almond"])
            else:                                       # okada / keke rank
                for k in range(int(rng.integers(2, 5))):
                    vp = f0 + (f1 - f0) * (0.15 + 0.7 * k / 4.0) + n * rng.uniform(1.4, 2.4)
                    if rng.random() < 0.7:
                        prop("okada/okada", vp, n, 1.1, 0.66, None, -np.pi * 0.5 + rng.uniform(-0.3, 0.3))
                    else:
                        prop("keke/keke", vp, n, 1.0, 0.9, None, -np.pi * 0.5 + rng.uniform(-0.2, 0.2))
                prop("lagos/villagekiosk", mid + n * (dp - 1.6), front, 1.0, -0.05)
                trees.append(r2(mid + n * (dp - 1.0) + t * 3.0) + ["almond"])
            counts[kind] = counts.get(kind, 0) + 1
            placed = True
            u += w + rng.uniform(0.4, 1.5)
            break
        if not placed:
            u += 3.0

chunk["walls"] = walls
chunk["trees"] = trees
chunk["props"] = props
json.dump(chunk, open(path, "w"), separators=(",", ":"))
print(path, counts, "walls", len(walls), "trees", len(trees), "props", len(props))
