"""Compact 'Lagos Island' street circuit (replaces the old 2.6 x 1.6 km block grid).

The world is built around the road instead of a big square of land:
  * a ~2.9 km closed spline circuit with a start/finish straight, a long Marina
    acceleration straight on the waterfront, a hairpin, a chicane, sweepers and
    tighter 90-degree street corners;
  * a continuous row of roadside buildings on both sides, right behind the
    pavement: real Lagos house / shop-row / uncompleted-building models plus
    procedural 2-5 storey mixed-use blocks, compound walls with gates;
  * short side streets that end at a building (no views into empty land);
  * a ground footprint that only covers the road corridor (5 m cells), so there
    is no huge empty slab and nothing far from the road gets built.
Writes data/map/island/lagos_island.json in the MapBuilder chunk format.
"""
import json, math, os, sys
import numpy as np

OUT = sys.argv[1] if len(sys.argv) > 1 else "data/map/island"
GEO = (6.45106, 3.38798)   # puts the circuit's centre on central Lagos Island
rng = np.random.default_rng(2077)
HW = 8.0            # road half width (kerb to kerb 16 m: 2 lanes each way + median)
LANES, LANE_W, MEDIAN = 2, 3.4, 0.8
PAVE = 4.0          # gutter + pavement between the kerb and the shop fronts
ELEV = 2.0
STEP = 3.0          # centre-line sample spacing (m)
CELL = 5.0          # ground footprint cell size (m)
CLEAR = HW + 3.2    # nothing solid closer than this to any part of the road

# --- 1. circuit: closed centripetal Catmull-Rom through hand-placed points ------
CP = [(0, 0), (320, 0), (400, 40), (415, 130), (450, 235), (560, 280), (760, 280),
      (980, 300), (1060, 360), (1065, 450), (985, 485), (820, 440), (720, 470),
      (640, 430), (520, 470), (380, 540), (200, 520), (120, 440), (60, 330),
      (-40, 250), (-65, 120), (-45, 35)]


def catmull_rom(P, n=60, alpha=0.5):
    P = [np.array(p, float) for p in P]
    N = len(P); out = []
    for i in range(N):
        p0, p1, p2, p3 = P[(i - 1) % N], P[i], P[(i + 1) % N], P[(i + 2) % N]
        tj = lambda ti, a, b: ti + np.linalg.norm(b - a) ** alpha
        t0 = 0.0; t1 = tj(t0, p0, p1); t2 = tj(t1, p1, p2); t3 = tj(t2, p2, p3)
        for t in np.linspace(t1, t2, n, endpoint=False):
            a1 = (t1 - t) / (t1 - t0) * p0 + (t - t0) / (t1 - t0) * p1
            a2 = (t2 - t) / (t2 - t1) * p1 + (t - t1) / (t2 - t1) * p2
            a3 = (t3 - t) / (t3 - t2) * p2 + (t - t2) / (t3 - t2) * p3
            b1 = (t2 - t) / (t2 - t0) * a1 + (t - t0) / (t2 - t0) * a2
            b2 = (t3 - t) / (t3 - t1) * a2 + (t - t1) / (t3 - t1) * a3
            out.append((t2 - t) / (t2 - t1) * b1 + (t - t1) / (t2 - t1) * b2)
    return np.array(out)


def resample_closed(P, step):
    Q = np.vstack([P, P[:1]])
    d = np.r_[0, np.cumsum(np.linalg.norm(np.diff(Q, axis=0), axis=1))]
    s = np.arange(0, d[-1] - step * 0.5, step)
    return np.c_[np.interp(s, d, Q[:, 0]), np.interp(s, d, Q[:, 1])], d[-1]


R, LOOP = resample_closed(catmull_rom(CP), STEP)
N = len(R)
# drive clockwise-on-screen (right-hand bends first): keep spline order
fwd = np.roll(R, -1, 0) - np.roll(R, 1, 0)
fwd /= np.linalg.norm(fwd, axis=1)[:, None]
heading = np.arctan2(fwd[:, 0], fwd[:, 1])            # MapBuilder convention
perp = np.c_[np.cos(heading), -np.sin(heading)]         # right of travel
dist = np.arange(N) * (LOOP / N)


def curv_radius(k=5):
    a, b, c = np.roll(R, k, 0), R, np.roll(R, -k, 0)
    ab = np.linalg.norm(b - a, axis=1); bc = np.linalg.norm(c - b, axis=1); ca = np.linalg.norm(a - c, axis=1)
    cr = (b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0])
    return np.where(np.abs(cr) > 1e-6, ab * bc * ca / (2 * np.abs(cr) + 1e-9), 1e9)


RAD = curv_radius()


def road_dist(pts):
    pts = np.atleast_2d(pts)
    out = np.empty(len(pts))
    for i in range(0, len(pts), 1500):
        q = pts[i:i + 1500]
        out[i:i + 1500] = np.sqrt(((q[:, None, :] - R[None, :, :]) ** 2).sum(-1).min(1))
    return out


def nearest_idx(p):
    return int(((R - np.asarray(p)) ** 2).sum(1).argmin())


def inside_loop(p):
    # even-odd point in polygon against the centre line
    x, z = p; c = False
    for i in range(N):
        x1, z1 = R[i]; x2, z2 = R[(i + 1) % N]
        if (z1 > z) != (z2 > z) and x < (x2 - x1) * (z - z1) / (z2 - z1) + x1:
            c = not c
    return c


# which side (+1 right / -1 left of travel) is the inside of the loop
INSIDE = 1.0 if inside_loop(R[N // 4] + perp[N // 4] * 40.0) else -1.0

# --- 2. features along the route -------------------------------------------------
# Marina waterfront: long straight with the lagoon on the outside, no buildings.
WATER = (640.0, 1070.0)
WATER_SIDE = -INSIDE
# side streets: straight-ish spots, alternating sides, away from the start + waterfront
side_streets, junctions = [], []
cand = [i for i in range(N) if RAD[max(i - 8, 0):i + 8].min() > 220 and 50 < dist[i] < LOOP - 60]
last = -1e9; sgn = 1.0
for i in cand:
    if dist[i] - last < 140:
        continue
    s = sgn
    if WATER[0] - 20 < dist[i] < WATER[1] + 20 and s == WATER_SIDE:
        s = -s
    junctions.append((i, s)); last = dist[i]; sgn = -sgn
STUB = 30.0
for i, s in junctions:
    a = R[i] + perp[i] * s * HW
    b = R[i] + perp[i] * s * (HW + STUB)
    side_streets.append({"w": 7.0, "pts": [[round(a[0], 2), round(a[1], 2)], [round(b[0], 2), round(b[1], 2)]]})
crossings = [round(float(dist[i] - 12.0), 1) for i, s in junctions[::2]]

# --- 3. occupancy raster (no overlapping buildings) ------------------------------
X0, Z0 = R.min(0) - 120; X1, Z1 = R.max(0) + 120
RES = 0.5
occ = np.zeros((int((Z1 - Z0) / RES) + 1, int((X1 - X0) / RES) + 1), bool)


def quad_cells(poly):
    poly = np.asarray(poly)
    lo = np.floor((poly.min(0) - [X0, Z0]) / RES).astype(int)
    hi = np.ceil((poly.max(0) - [X0, Z0]) / RES).astype(int)
    xs = X0 + (np.arange(lo[0], hi[0]) + 0.5) * RES
    zs = Z0 + (np.arange(lo[1], hi[1]) + 0.5) * RES
    gx, gz = np.meshgrid(xs, zs)
    ins = np.ones_like(gx, bool)
    sa = 0.0
    for k in range(len(poly)):
        x1, z1 = poly[k]; x2, z2 = poly[(k + 1) % len(poly)]
        sa += x1 * z2 - x2 * z1
    for k in range(len(poly)):
        x1, z1 = poly[k]; x2, z2 = poly[(k + 1) % len(poly)]
        cr = (x2 - x1) * (gz - z1) - (z2 - z1) * (gx - x1)
        ins &= (cr >= 0) if sa > 0 else (cr <= 0)
    return lo, hi, ins


def free(poly):
    lo, hi, ins = quad_cells(poly)
    sub = occ[lo[1]:hi[1], lo[0]:hi[0]]
    return not (sub & ins[:sub.shape[0], :sub.shape[1]]).any()


def mark(poly):
    lo, hi, ins = quad_cells(poly)
    sub = occ[lo[1]:hi[1], lo[0]:hi[0]]
    sub |= ins[:sub.shape[0], :sub.shape[1]]


def ccw(poly):
    sa = sum(poly[k][0] * poly[(k + 1) % 4][1] - poly[(k + 1) % 4][0] * poly[k][1] for k in range(4))
    return poly if sa > 0 else poly[::-1]


def clear_of_road(poly):
    poly = np.asarray(poly)
    pts = np.vstack([poly, (poly + np.roll(poly, -1, 0)) * 0.5])
    return road_dist(pts).min() >= CLEAR


# keep side-street openings clear
for ss in side_streets:
    a, b = np.array(ss["pts"][0]), np.array(ss["pts"][1])
    d = (b - a) / np.linalg.norm(b - a); n = np.array([-d[1], d[0]]) * 4.2
    mark([a - n - d * 2, a + n - d * 2, b + n, b - n])

# --- 4. roadside frontage --------------------------------------------------------
# Building kinds. Model kinds are scaled uniformly from their real size (front = +X):
#   house 6.1 deep x 6.4 wide x 6 tall, unfinished 7 x 8.76 x 6, plaza 2.62 x 7.88 x 2.5
WALLS = [[0.95, 0.89, 0.74], [0.97, 0.84, 0.52], [0.96, 0.74, 0.60], [0.66, 0.80, 0.90],
         [0.74, 0.88, 0.74], [0.96, 0.96, 0.93], [0.93, 0.76, 0.78], [0.88, 0.62, 0.46]]
blds, walls, trees = [], [], []


def pick_kind(on_bend):
    r = rng.random()
    if on_bend:                       # corners: solid blocks hold the frontage round the bend
        return "block" if r < 0.7 else "house"
    if r < 0.30: return "block"
    if r < 0.52: return "house"
    if r < 0.66: return "plaza"
    if r < 0.78: return "unfinished"
    return "compound"


def lot_size(kind):
    if kind == "house":
        s = rng.uniform(1.15, 1.5); return 6.4 * s, 6.1 * s, s
    if kind == "unfinished":
        s = rng.uniform(1.0, 1.3); return 8.76 * s, 7.0 * s, s
    if kind == "plaza":
        s = rng.uniform(2.1, 2.9); return 7.88 * s, 2.62 * s, s
    if kind == "compound":
        return rng.uniform(13, 20), rng.uniform(13, 17), 1.0
    return rng.uniform(8, 16), rng.uniform(9, 14), 1.0


def offset_line(side):
    Q = R + perp * side * (HW + PAVE)
    seg = np.linalg.norm(np.diff(np.vstack([Q, Q[:1]]), axis=0), axis=1)
    return Q, np.r_[0, np.cumsum(seg)]


def at(Q, cum, u):
    u = u % cum[-1]
    k = int(np.searchsorted(cum, u, side="right") - 1)
    t = (u - cum[k]) / max(cum[k + 1] - cum[k], 1e-6)
    return Q[k] + (Q[(k + 1) % len(Q)] - Q[k]) * t, k


def add_wall_run(Q, cum, u0, u1, side, h, col, kind="wall"):
    """Wall following the frontage line from u0 to u1 (short straight pieces)."""
    u = u0
    while u < u1 - 0.5:
        ue = min(u + 5.0, u1)
        a, ka = at(Q, cum, u); b, _ = at(Q, cum, ue)
        if road_dist([a, b, (a + b) * 0.5]).min() >= HW + 2.6:
            walls.append({"a": [round(a[0], 2), round(a[1], 2)], "b": [round(b[0], 2), round(b[1], 2)],
                          "h": round(h, 2), "t": 0.25, "k": kind, "c": col})
        u = ue


def wall(a, b, h, col, kind="wall", t=0.25):
    walls.append({"a": [round(a[0], 2), round(a[1], 2)], "b": [round(b[0], 2), round(b[1], 2)],
                  "h": round(h, 2), "t": t, "k": kind, "c": col})


for side in (1.0, -1.0):
    Q, cum = offset_line(side)
    L = cum[-1]
    u = 0.0
    gap_start = None
    while u < L - 4.0:
        p0, k0 = at(Q, cum, u)
        ci = k0 % N
        d_here = dist[ci]
        if side == WATER_SIDE and WATER[0] <= d_here <= WATER[1]:
            # Marina promenade: railing + palms, lagoon behind
            if gap_start is not None:
                gap_start = None
            a = R[ci] + perp[ci] * side * (HW + 6.2); b = R[(ci + 2) % N] + perp[(ci + 2) % N] * side * (HW + 6.2)
            wall(a, b, 1.05, [0.85, 0.85, 0.82], "rail", 0.15)
            if rng.random() < 0.16:
                tp = R[ci] + perp[ci] * side * (HW + 4.6)
                trees.append([round(tp[0], 2), round(tp[1], 2), "coconut"])
            u += 6.0
            continue
        on_bend = RAD[max(ci - 6, 0):ci + 6].min() < 90
        kind = pick_kind(on_bend)
        placed = False
        for attempt in range(4):
            w, dp, s = lot_size(kind)
            if attempt >= 2:
                w *= 0.7; dp *= 0.8
            pa, _ = at(Q, cum, u); pb, kb = at(Q, cum, u + w)
            chord = pb - pa
            if np.linalg.norm(chord) < w * 0.75:           # inside of a tight bend
                break
            t = chord / np.linalg.norm(chord)
            n = np.array([t[1], -t[0]])
            mid_i = nearest_idx((pa + pb) * 0.5)
            if np.dot(n, perp[mid_i] * side) < 0:
                n = -n                                     # n points away from the road
            sb = 0.0 if kind == "compound" else rng.uniform(0.0, 1.4)
            f0 = pa + n * sb; f1 = pb + n * sb
            poly = [f0, f1, f1 + n * dp, f0 + n * dp]
            if not (clear_of_road(poly) and free(poly)):
                dp *= 0.65
                poly = [f0, f1, f1 + n * dp, f0 + n * dp]
                if not (clear_of_road(poly) and free(poly)):
                    kind = "block" if kind != "block" else "house"
                    continue
            mark(poly)
            poly = ccw([[round(float(q[0]), 2), round(float(q[1]), 2)] for q in poly])
            front = -n
            ctr = (f0 + f1) * 0.5 + n * dp * 0.5
            col = WALLS[rng.integers(len(WALLS))]
            if kind == "compound":
                # perimeter wall with a gate on the road side, house set back in the yard
                gw = 3.6; g0 = 0.5 - gw / (2 * w) + rng.uniform(-0.2, 0.2)
                ga = f0 + (f1 - f0) * g0; gb = f0 + (f1 - f0) * (g0 + gw / w)
                h = rng.uniform(2.2, 2.7)
                wc = [c * 0.92 for c in col]
                wall(f0, ga, h, wc); wall(gb, f1, h, wc); wall(ga, gb, h - 0.2, [0.12, 0.13, 0.15], "gate")
                wall(f0, f0 + n * dp, h, wc); wall(f1, f1 + n * dp, h, wc); wall(f0 + n * dp, f1 + n * dp, h, wc)
                hs = rng.uniform(1.15, 1.4); hd, hwid = 6.1 * hs, 6.4 * hs
                hc = (f0 + f1) * 0.5 + n * (dp - hd * 0.5 - 1.0)
                hp = [hc + t * hwid / 2 + n * hd / 2, hc - t * hwid / 2 + n * hd / 2, hc - t * hwid / 2 - n * hd / 2, hc + t * hwid / 2 - n * hd / 2]
                blds.append({"pts": ccw([[round(float(q[0]), 2), round(float(q[1]), 2)] for q in hp]), "h": round(6.0 * hs, 1),
                             "d": round(float(road_dist([hc])[0]), 1), "m": "lagos_house/house",
                             "f": [round(float(front[0]), 4), round(float(front[1]), 4)], "w": round(hwid, 2), "dp": round(hd, 2), "nocol": True})
                blds.append({"pts": poly, "h": 0.0, "d": round(float(road_dist([ctr])[0]), 1), "yard": True})
                if rng.random() < 0.5:
                    tp = (f0 + f1) * 0.5 + n * 2.2 + t * (w * 0.3)
                    trees.append([round(tp[0], 2), round(tp[1], 2), "almond" if rng.random() < 0.6 else "coconut"])
            elif kind in ("house", "unfinished", "plaza"):
                model = {"house": "lagos_house/house", "unfinished": "unfinished/unfinished", "plaza": "plaza/plaza"}[kind]
                base_h = {"house": 6.0, "unfinished": 6.0, "plaza": 2.5}[kind]
                blds.append({"pts": poly, "h": round(base_h * s, 1), "d": round(float(road_dist([ctr])[0]), 1), "m": model,
                             "f": [round(float(front[0]), 4), round(float(front[1]), 4)], "w": round(float(np.linalg.norm(f1 - f0)), 2), "dp": round(dp, 2)})
            else:
                storeys = int(rng.choice([2, 2, 3, 3, 3, 4, 5]))
                h = storeys * 3.2 + rng.uniform(0.2, 0.9)
                blds.append({"pts": poly, "h": round(h, 1), "d": round(float(road_dist([ctr])[0]), 1), "shop": True})
            placed = True
            u += np.linalg.norm(f1 - f0) + (rng.uniform(0.0, 0.8) if kind != "compound" else 0.0)
            break
        if not placed:
            # couldn't fit a building here (tight inside bend / side street): close the
            # frontage with a low compound wall instead of leaving a hole
            if not any(abs(d_here - dist[i]) < 8 and s == side for i, s in junctions):
                add_wall_run(Q, cum, u, u + 3.0, side, rng.uniform(2.0, 2.5), [0.82, 0.80, 0.74])
            u += 3.0

# side streets: walls down both sides, closed by a building across the far end
for (i, s), ss in zip(junctions, side_streets):
    a, b = np.array(ss["pts"][0]), np.array(ss["pts"][1])
    d = (b - a) / np.linalg.norm(b - a); n = np.array([-d[1], d[0]])
    col = [0.84, 0.81, 0.74]
    for sd in (-1, 1):
        wall(a + d * (PAVE + 0.5) + n * sd * 3.9, b + n * sd * 3.9, 2.4, col)
    e0 = b + n * 9.0; e1 = b - n * 9.0
    poly = [e0, e1, e1 + d * 11.0, e0 + d * 11.0]
    ctr = b + d * 5.5
    blds.append({"pts": ccw([[round(float(q[0]), 2), round(float(q[1]), 2)] for q in poly]), "h": round(rng.uniform(9, 14), 1),
                 "d": round(float(road_dist([ctr])[0]), 1), "shop": True})

# front edge (closest to the road) of every procedural building: awning + sign go there
for b in blds:
    if b.get("shop"):
        pts = np.array(b["pts"])
        mids = (pts + np.roll(pts, -1, 0)) * 0.5
        b["fe"] = int(road_dist(mids).argmin())

# --- distant towers over the rooftops (Marina / Broad Street high-rises) ---------
towers = []
tw_rng = np.random.default_rng(5)
tries = 0
while len(towers) < 46 and tries < 4000:
    tries += 1
    p = np.array([tw_rng.uniform(X0 - 150, X1 + 150), tw_rng.uniform(Z0 - 150, Z1 + 150)])
    d = road_dist([p])[0]
    if not (HW + 110 < d < HW + 430):
        continue
    i = nearest_idx(p)
    side = 1.0 if np.dot(p - R[i], perp[i]) > 0 else -1.0
    if side == WATER_SIDE and WATER[0] - 80 <= dist[i] <= WATER[1] + 80:
        continue
    if any(np.linalg.norm(p - np.array(t["c"])) < 55 for t in towers):
        continue
    w, dpt = tw_rng.uniform(18, 34), tw_rng.uniform(18, 30)
    a = tw_rng.uniform(0, math.pi)
    u = np.array([math.cos(a), math.sin(a)]); v = np.array([-u[1], u[0]])
    poly = [p - u * w / 2 - v * dpt / 2, p + u * w / 2 - v * dpt / 2, p + u * w / 2 + v * dpt / 2, p - u * w / 2 + v * dpt / 2]
    towers.append({"c": [round(p[0], 1), round(p[1], 1)], "pts": ccw([[round(float(q[0]), 2), round(float(q[1]), 2)] for q in poly]),
                   "h": round(float(tw_rng.choice([tw_rng.uniform(28, 55), tw_rng.uniform(55, 120)], p=[0.6, 0.4])), 1)})

# --- 5. ground footprint: only the road corridor ---------------------------------
cells = set()
cx = np.arange(np.floor(X0 / CELL), np.ceil(X1 / CELL))
cz = np.arange(np.floor(Z0 / CELL), np.ceil(Z1 / CELL))
gx, gz = np.meshgrid(cx, cz)
cc = np.c_[(gx.ravel() + 0.5) * CELL, (gz.ravel() + 0.5) * CELL]
dd = road_dist(cc)
keep = dd < HW + 31.0
for (x, z), k, d in zip(cc, keep, dd):
    if not k:
        continue
    i = nearest_idx((x, z))
    side = 1.0 if np.dot(np.array([x, z]) - R[i], perp[i]) > 0 else -1.0
    if side == WATER_SIDE and WATER[0] <= dist[i] <= WATER[1] and d > HW + 7.0:
        continue    # lagoon right behind the Marina railing
    cells.add((int(np.floor(x / CELL)), int(np.floor(z / CELL))))
# make sure every building / side street stands on ground
for b in blds:
    for q in b["pts"]:
        cells.add((int(np.floor(q[0] / CELL)), int(np.floor(q[1] / CELL))))
    p = np.mean(np.array(b["pts"]), 0)
    cells.add((int(np.floor(p[0] / CELL)), int(np.floor(p[1] / CELL))))
for ss in side_streets:
    a, b = np.array(ss["pts"][0]), np.array(ss["pts"][1])
    for t in np.linspace(0, 1, 12):
        q = a + (b - a) * t
        for ox in (-6, 0, 6):
            for oz in (-6, 0, 6):
                cells.add((int(np.floor((q[0] + ox) / CELL)), int(np.floor((q[1] + oz) / CELL))))

# cheap background ground (no collision) for glimpses through gaps + tower bases
BACK = 20.0
back = set()
bx = np.arange(np.floor((X0 - 200) / BACK), np.ceil((X1 + 200) / BACK))
bz = np.arange(np.floor((Z0 - 200) / BACK), np.ceil((Z1 + 200) / BACK))
gx, gz = np.meshgrid(bx, bz)
bc = np.c_[(gx.ravel() + 0.5) * BACK, (gz.ravel() + 0.5) * BACK]
bd = road_dist(bc)
for (x, z), d in zip(bc, bd):
    if d > HW + 150:
        continue
    i = nearest_idx((x, z))
    side = 1.0 if np.dot(np.array([x, z]) - R[i], perp[i]) > 0 else -1.0
    if side == WATER_SIDE and WATER[0] - 60 <= dist[i] <= WATER[1] + 60:
        continue
    back.add((int(np.floor(x / BACK)), int(np.floor(z / BACK))))
for t in towers:
    for q in t["pts"] + [t["c"]]:
        for ox in (-10, 0, 10):
            for oz in (-10, 0, 10):
                back.add((int(np.floor((q[0] + ox) / BACK)), int(np.floor((q[1] + oz) / BACK))))

# --- 6. samples, start line, checkpoints ------------------------------------------
samples = []
for i in range(N):
    samples.append({"x": round(float(R[i, 0]), 3), "z": round(float(R[i, 1]), 3), "elev_m": ELEV, "on_bridge": False,
                    "dist_m": round(float(dist[i]), 2), "heading_rad": round(float(heading[i]), 6)})
samples.append(dict(samples[0], dist_m=round(float(LOOP), 2)))
lane_r = MEDIAN * 0.5 + LANE_W * 1.5          # outer right lane
sp_i = N - int(22 / STEP)                     # grid just behind the start line
sp = R[sp_i] + perp[sp_i] * lane_r
cps = []
for ci, frac in enumerate([0.11, 0.24, 0.37, 0.5, 0.63, 0.76, 0.89]):
    i = int(frac * N)
    cps.append({"index": ci, "x": round(float(R[i, 0]), 3), "z": round(float(R[i, 1]), 3), "y": ELEV,
                "heading_rad": round(float(heading[i]), 6), "dist_m": round(float(dist[i]), 2)})
cps.append({"index": len(cps), "x": round(float(R[0, 0]), 3), "z": round(float(R[0, 1]), 3), "y": ELEV,
            "heading_rad": round(float(heading[0]), 6), "dist_m": round(float(LOOP), 2), "finish": True})

bx0, bz0 = R.min(0) - 300; bx1, bz1 = R.max(0) + 300
chunk = {
    "chunk_id": "lagos_island", "description": "Lagos Island street circuit (compact district: Broad St, Marina, Balogun)",
    "approximate": True, "no_landmarks": True, "district": True, "loop": True,
    "pavement_m": PAVE,
    "geo_origin": {"lat": GEO[0], "lon": GEO[1]},
    "bounds_local_m": {"min_x": round(float(bx0), 1), "max_x": round(float(bx1), 1), "min_z": round(float(bz0), 1), "max_z": round(float(bz1), 1)},
    "road": {"half_width_m": HW, "barrier_height_m": 0.22, "lanes_per_direction": LANES, "lane_width_m": LANE_W,
             "median_width_m": MEDIAN, "length_m": round(float(LOOP), 2), "samples": samples},
    "bridge": {"deck_thickness_m": 1.2, "support_spacing_m": 40.0, "support_width_m": 2.0, "water_level_y": 0.0, "pier_foot_y": -6.0},
    "buildings": [], "osm_buildings": blds, "side_streets": side_streets, "walls": walls, "trees": trees,
    "towers": [{"pts": t["pts"], "h": t["h"]} for t in towers],
    "back_cells": {"cell_m": BACK, "cells": sorted([list(c) for c in back])},
    "crossings": crossings, "start_line": {"dist_m": 0.0},
    "promenade": {"from": WATER[0], "to": WATER[1], "side": WATER_SIDE, "w": 6.4},
    "land_cells": {"cell_m": CELL, "cells": sorted([list(c) for c in cells])},
    "spawn": {"x": round(float(sp[0]), 3), "y": ELEV + 0.5, "z": round(float(sp[1]), 3), "heading_rad": round(float(heading[sp_i]), 6)},
    "checkpoints": cps, "source": {"type": "procedural", "license": "generated"},
}
os.makedirs(OUT, exist_ok=True)
json.dump(chunk, open(os.path.join(OUT, "lagos_island.json"), "w"), separators=(",", ":"))
corners = int(((RAD[:-1] >= 150) & (RAD[1:] < 150)).sum())
print("loop %.0f m, %d samples, min radius %.0f m, %d corners, %d buildings, %d wall pieces, %d side streets, %d ground cells (%.2f km2)"
      % (LOOP, N, RAD.min(), corners, len(blds), len(walls), len(side_streets), len(cells), len(cells) * CELL * CELL / 1e6))


# --- 7. menu assets: track preview + route on the Lagos map screen ---------------
def write_ui_assets():
    if not os.path.isdir("assets/ui"):
        return
    from PIL import Image, ImageDraw, ImageFilter
    W, H, M = 480, 300, 26
    lo, hi = R.min(0), R.max(0)
    sc = min((W - 2 * M) / (hi[0] - lo[0]), (H - 2 * M) / (hi[1] - lo[1]))
    ox = (W - (hi[0] - lo[0]) * sc) / 2; oy = (H - (hi[1] - lo[1]) * sc) / 2
    px = lambda p: (ox + (p[0] - lo[0]) * sc, H - (oy + (p[1] - lo[1]) * sc))   # north up
    img = Image.new("RGB", (W, H), (17, 18, 23)); dr = ImageDraw.Draw(img)
    for x in range(0, W, 24): dr.line([(x, 0), (x, H)], fill=(28, 30, 37))
    for y in range(0, H, 24): dr.line([(0, y), (W, y)], fill=(28, 30, 37))
    pts = [px(p) for p in R] + [px(R[0])]
    glow = Image.new("RGB", (W, H), (0, 0, 0)); gd = ImageDraw.Draw(glow)
    gd.line(pts, fill=(250, 190, 30), width=12, joint="curve")
    img = Image.blend(img, Image.composite(glow.filter(ImageFilter.GaussianBlur(6)), img, glow.convert("L").point(lambda v: 255 if v else 0)), 0.45)
    dr = ImageDraw.Draw(img)
    dr.line(pts, fill=(250, 196, 40), width=5, joint="curve")
    sx, sy = px(R[0])
    for k in range(4):
        for j in range(4):
            dr.rectangle([sx - 8 + k * 4, sy - 8 + j * 4, sx - 4 + k * 4, sy - 4 + j * 4], fill=(255, 255, 255) if (k + j) % 2 == 0 else (10, 10, 10))
    img.save("assets/ui/tracks/island_circuit.png")
    mp = "assets/ui/lagos_map.json"
    if os.path.exists(mp):
        m = json.load(open(mp))
        geo = [[round(GEO[0] + p[1] / 110574.0, 5), round(GEO[1] + p[0] / (111320.0 * math.cos(math.radians(GEO[0]))), 5)] for p in R[::12]]
        geo.append(geo[0])
        for r in m["routes"]:
            if r["key"] == "island":
                r["pts"] = geo
                r["name"] = "Lagos Island Circuit"
        json.dump(m, open(mp, "w"))


if OUT.rstrip("/").endswith("data/map/island"):
    write_ui_assets()
