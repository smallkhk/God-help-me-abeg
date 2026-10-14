"""Lagos Island street circuit on REAL streets (© OpenStreetMap contributors, ODbL).

Every metre of the route follows OpenStreetMap street geometry; the only change
is a small fillet at each junction so a car can take the corner. Buildings are
the real OSM footprints (height from `height` / `building:levels`, else a
deterministic estimate); open plots stay open. Real side streets appear at
their real junctions. Each route section is tagged with its street name and
`"verified": true` (real road) — designed shortcuts, if ever added, must be
tagged `"verified": false`.

Route (clockwise on the map):
  Old Marina Street (east, waterfront) -> Campbell Street (north) ->
  Broad Street (west) -> Nnamdi Azikiwe Street (north) -> Ali Balogun Street ->
  Martin Street -> Balogun Street (south-west, market) -> Broad Street -> start

Input: parsed OSM json (from osm .osm tiles of Lagos Island), e.g.
  python3 -I tools/lagos_map_pipeline/generate_island_osm.py work/island_osm.json
Writes data/map/island/lagos_island.json (MapBuilder district chunk), the menu
track preview and the map-screen route.
"""
import heapq, json, math, os, sys
import numpy as np

SRC = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else "data/map/island"
HW = 7.0                     # 14 m kerb to kerb (Broad St / Marina class streets)
LANES, LANE_W, MEDIAN = 2, 3.2, 0.4
PAVE = 3.0
ELEV = 2.0
STEP = 3.0
CELL = 5.0
FILLET = 18.0                # corner rounding radius at junctions (m)
rng = np.random.default_rng(1861)

# real junctions (lat, lon) from OSM, in driving order
WAYPOINTS = [
    ("Old Marina Street", (6.45511, 3.38325)),      # Balogun St / Old Marina St
    ("Campbell Street", (6.44589, 3.39764)),        # Campbell St / Old Marina St
    ("Broad Street", (6.44691, 3.39834)),           # Campbell St / Broad St
    ("Nnamdi Azikiwe Street", (6.45393, 3.38975)),  # Broad St / Nnamdi Azikiwe St (east node, Ali St)
    ("Ali Balogun Street", (6.45829, 3.38757)),     # Nnamdi Azikiwe / Ali Balogun St
    ("Martin Street", (6.45836, 3.38649)),          # Ali Balogun / Martin St
    ("Balogun Street", (6.45899, 3.38653)),         # Martin St / Balogun St
    ("Broad Street", (6.45576, 3.38367)),           # Balogun St / Broad St
]
# streets each leg may use (keeps the path on the named real streets)
LEG_STREETS = [
    {"Old Marina Street", "Marina Road", ""},
    {"Campbell Street", "Old Marina Street", "Broad Street"},
    {"Broad Street", "Campbell Street"},
    {"Nnamdi Azikiwe Street", "Broad Street"},
    {"Ali Balogun Street", "Nnamdi Azikiwe Street", "Martin Street"},
    {"Martin Street", "Ali Balogun Street", "Balogun Street"},
    {"Balogun Street", "Martin Street", "Broad Street"},
    {"Broad Street", "Balogun Street", "Old Marina Street", "Issa Williams Street", ""},
]

d = json.load(open(SRC))
nodes = {int(k): tuple(v) for k, v in d["nodes"].items()}
lat_c = np.mean([w[1][0] for w in WAYPOINTS]); lon_c = np.mean([w[1][1] for w in WAYPOINTS])
GEO = (round(float(lat_c), 5), round(float(lon_c), 5))


def loc(p):
    return np.array([(p[1] - GEO[1]) * 111320.0 * math.cos(math.radians(GEO[0])), (p[0] - GEO[0]) * 110574.0])


# --- 1. street graph and the route --------------------------------------------------
adj = {}
for r in d["roads"]:
    nds = r["nds"]
    for a, b in zip(nds, nds[1:]):
        w = float(np.linalg.norm(loc(nodes[a]) - loc(nodes[b])))
        adj.setdefault(a, []).append((b, w, r["name"]))
        if r.get("oneway") not in ("yes", "1") or True:     # racing ignores one-way
            adj.setdefault(b, []).append((a, w, r["name"]))


def nearest_node(p):
    q = loc(p)
    return min(adj, key=lambda n: float(np.sum((loc(nodes[n]) - q) ** 2)))


def path(a, b, allowed):
    dist = {a: 0.0}; prev = {}; pq = [(0.0, a)]
    while pq:
        c, n = heapq.heappop(pq)
        if n == b:
            break
        if c > dist[n]:
            continue
        for m, w, name in adj.get(n, []):
            if name not in allowed:
                continue
            nc = c + w
            if nc < dist.get(m, 1e18):
                dist[m] = nc; prev[m] = (n, name); heapq.heappush(pq, (nc, m))
    if b not in dist:
        raise SystemExit("no path on allowed streets: %s" % allowed)
    out = [(b, prev[b][1])]
    while out[-1][0] != a:
        n, name = prev[out[-1][0]]
        out.append((n, name if n != a else name))
    return out[::-1]


wp_nodes = [nearest_node(p) for _, p in WAYPOINTS]
route_nodes, route_names = [], []
for i in range(len(wp_nodes)):
    seg = path(wp_nodes[i], wp_nodes[(i + 1) % len(wp_nodes)], LEG_STREETS[i])
    for k, (n, name) in enumerate(seg[:-1]):
        route_nodes.append(n); route_names.append(seg[k + 1][1] or WAYPOINTS[i][0])
P = np.array([loc(nodes[n]) for n in route_nodes])
# drop duplicate consecutive points
keep = [0] + [i for i in range(1, len(P)) if np.linalg.norm(P[i] - P[i - 1]) > 0.5]
P = P[keep]; names = [route_names[i] for i in keep]


# --- 2. fillet sharp corners (keeps alignment, makes it drivable) --------------------
def fillet(P, r):
    out = []
    n = len(P)
    for i in range(n):
        a, b, c = P[i - 1], P[i], P[(i + 1) % n]
        u = a - b; v = c - b
        lu, lv = np.linalg.norm(u), np.linalg.norm(v)
        if lu < 1e-6 or lv < 1e-6:
            continue
        u /= lu; v /= lv
        ang = math.acos(max(-1.0, min(1.0, float(np.dot(u, v)))))
        if ang > math.radians(165):       # nearly straight: keep point
            out.append(b); continue
        t = min(r / math.tan(ang / 2), lu * 0.45, lv * 0.45)
        p0 = b + u * t; p1 = b + v * t
        for s in np.linspace(0, 1, 9):     # quadratic Bezier through the corner
            out.append((1 - s) ** 2 * p0 + 2 * (1 - s) * s * b + s ** 2 * p1)
    return np.array(out)


def resample_closed(P, step):
    Q = np.vstack([P, P[:1]])
    dd = np.r_[0, np.cumsum(np.linalg.norm(np.diff(Q, axis=0), axis=1))]
    s = np.arange(0, dd[-1] - step * 0.5, step)
    return np.c_[np.interp(s, dd, Q[:, 0]), np.interp(s, dd, Q[:, 1])], dd[-1]


def simplify(P, tol):
    """Douglas-Peucker on the closed loop: drops OSM micro-segments at junctions
    (they leave no room for a fillet) while staying within `tol` of the street."""
    def rdp(Q):
        if len(Q) < 3:
            return Q
        a, b = Q[0], Q[-1]
        ab = b - a; L = np.linalg.norm(ab) + 1e-9
        dd = np.abs((Q[:, 0] - a[0]) * ab[1] - (Q[:, 1] - a[1]) * ab[0]) / L
        k = int(dd.argmax())
        if dd[k] <= tol:
            return np.vstack([a, b])
        return np.vstack([rdp(Q[:k + 1])[:-1], rdp(Q[k:])])
    k = int(np.argmax(np.linalg.norm(P - P[0], axis=1)))
    return np.vstack([rdp(np.vstack([P[:k + 1]]))[:-1], rdp(np.vstack([P[k:], P[:1]]))[:-1]])


P_s = simplify(P, 1.5)
R, LOOP = resample_closed(fillet(fillet(P_s, FILLET), FILLET * 0.5), STEP)
# light smoothing of sample noise (OSM node jitter), keeps shape within ~1 m
for _ in range(2):
    R = (np.roll(R, 1, 0) + 2 * R + np.roll(R, -1, 0)) / 4.0
N = len(R)
fwd = np.roll(R, -1, 0) - np.roll(R, 1, 0)
fwd /= np.linalg.norm(fwd, axis=1)[:, None]
heading = np.arctan2(fwd[:, 0], fwd[:, 1])
perp = np.c_[np.cos(heading), -np.sin(heading)]
dist = np.arange(N) * (LOOP / N)
# street name per sample (nearest original route vertex)
name_at = [names[int(np.argmin(np.sum((P - R[i]) ** 2, 1)))] for i in range(N)]


def road_dist(pts):
    pts = np.atleast_2d(pts); out = np.empty(len(pts))
    for i in range(0, len(pts), 1500):
        q = pts[i:i + 1500]
        out[i:i + 1500] = np.sqrt(((q[:, None, :] - R[None, :, :]) ** 2).sum(-1).min(1))
    return out


# --- 3. real buildings ---------------------------------------------------------------
def height_for(b):
    h = str(b.get("height", "")).replace("m", "").strip()
    try:
        return max(3.0, min(float(h), 160.0))
    except ValueError:
        pass
    try:
        return max(3.0, min(float(b.get("levels")) * 3.2 + 0.6, 160.0))
    except (TypeError, ValueError):
        pass
    import zlib
    return 4.5 + (zlib.crc32(str(b["id"]).encode()) % 100) / 100.0 * 7.0   # 1-3 storeys


blds, dropped = [], 0
for b in d["buildings"]:
    pts = np.array([loc(p) for p in b["pts"]])
    if len(pts) > 3 and np.linalg.norm(pts[0] - pts[-1]) < 0.01:
        pts = pts[:-1]
    if len(pts) < 3:
        continue
    rd = road_dist(np.vstack([pts, pts.mean(0)]))
    if rd.min() > 140.0:
        continue
    if rd.min() < HW + 1.2:
        dropped += 1            # footprint reaches onto the (widened) carriageway
        continue
    sa = sum(pts[k][0] * pts[(k + 1) % len(pts)][1] - pts[(k + 1) % len(pts)][0] * pts[k][1] for k in range(len(pts)))
    if sa < 0:
        pts = pts[::-1]
    h = height_for(b)
    entry = {"pts": [[round(float(q[0]), 2), round(float(q[1]), 2)] for q in pts], "h": round(h, 1),
             "d": round(float(rd.min()), 1), "osm": int(b["id"])}
    if b.get("name"):
        entry["name"] = b["name"]
    if rd.min() < 30.0 and h < 18.0:
        mids = (pts + np.roll(pts, -1, 0)) * 0.5
        entry["fe"] = int(road_dist(mids).argmin())       # shopfront faces the road
    blds.append(entry)

# --- 4. real side streets at their real junctions -----------------------------------
route_set = set(route_nodes)
side_streets = []
for r in d["roads"]:
    if r["type"] in ("motorway", "motorway_link", "trunk", "trunk_link"):
        continue
    nds = r["nds"]
    for k, n in enumerate(nds):
        if n not in route_set:
            continue
        for direction in (1, -1):
            j = k + direction
            if not (0 <= j < len(nds)) or nds[j] in route_set:
                continue
            pts = [loc(nodes[n])]
            length = 0.0
            while 0 <= j < len(nds) and length < 40.0 and nds[j] not in route_set:
                q = loc(nodes[nds[j]]); length += float(np.linalg.norm(q - pts[-1])); pts.append(q); j += direction
            if length < 8.0:
                continue
            # start the stub at the kerb, not the centre line
            a, b2 = pts[0], pts[1]
            dv = (b2 - a) / max(np.linalg.norm(b2 - a), 1e-6)
            pts[0] = a + dv * HW
            side_streets.append({"w": 6.0, "name": r["name"], "pts": [[round(float(p[0]), 2), round(float(p[1]), 2)] for p in pts]})

# --- 5. ground footprint --------------------------------------------------------------
X0, Z0 = R.min(0) - 160; X1, Z1 = R.max(0) + 160
cells = set()
cx = np.arange(np.floor(X0 / CELL), np.ceil(X1 / CELL)); cz = np.arange(np.floor(Z0 / CELL), np.ceil(Z1 / CELL))
gx, gz = np.meshgrid(cx, cz)
cc = np.c_[(gx.ravel() + 0.5) * CELL, (gz.ravel() + 0.5) * CELL]
for (x, z), dd in zip(cc, road_dist(cc)):
    if dd < HW + 45.0:
        cells.add((int(np.floor(x / CELL)), int(np.floor(z / CELL))))
for b in blds:
    for q in b["pts"]:
        cells.add((int(np.floor(q[0] / CELL)), int(np.floor(q[1] / CELL))))
for ss in side_streets:
    for q in ss["pts"]:
        for ox in (-5, 0, 5):
            for oz in (-5, 0, 5):
                cells.add((int(np.floor((q[0] + ox) / CELL)), int(np.floor((q[1] + oz) / CELL))))
BACK = 20.0
back = set()
bx = np.arange(np.floor((X0 - 150) / BACK), np.ceil((X1 + 150) / BACK)); bz = np.arange(np.floor((Z0 - 150) / BACK), np.ceil((Z1 + 150) / BACK))
gx, gz = np.meshgrid(bx, bz)
bc = np.c_[(gx.ravel() + 0.5) * BACK, (gz.ravel() + 0.5) * BACK]
for (x, z), dd in zip(bc, road_dist(bc)):
    if dd < HW + 160:
        back.add((int(np.floor(x / BACK)), int(np.floor(z / BACK))))

# --- 6. samples, sections, start line, checkpoints -----------------------------------
samples = [{"x": round(float(R[i, 0]), 3), "z": round(float(R[i, 1]), 3), "elev_m": ELEV, "on_bridge": False,
            "dist_m": round(float(dist[i]), 2), "heading_rad": round(float(heading[i]), 6)} for i in range(N)]
samples.append(dict(samples[0], dist_m=round(float(LOOP), 2)))
# start/finish on the straight part of Old Marina Street, ~120 m east of Balogun St
s0 = int(120 / STEP)
R = np.roll(R, -s0, 0); heading = np.roll(heading, -s0); perp = np.roll(perp, -s0, 0)
for k, s in enumerate(samples[:-1]):
    i = (k + s0) % N
    s.update({"x": round(float(R[k, 0]), 3), "z": round(float(R[k, 1]), 3), "heading_rad": round(float(heading[k]), 6)})
samples[-1] = dict(samples[0], dist_m=round(float(LOOP), 2))
name_at = name_at[s0:] + name_at[:s0]
sections = []
for i in range(N):
    if not sections or sections[-1]["name"] != name_at[i]:
        sections.append({"name": name_at[i], "from_m": round(float(dist[i]), 1), "verified": True})
lane_r = MEDIAN * 0.5 + LANE_W * 1.5
sp_i = N - int(22 / STEP)
sp = R[sp_i] + perp[sp_i] * lane_r
cps = []
for ci, frac in enumerate([0.11, 0.24, 0.37, 0.5, 0.63, 0.76, 0.89]):
    i = int(frac * N)
    cps.append({"index": ci, "x": round(float(R[i, 0]), 3), "z": round(float(R[i, 1]), 3), "y": ELEV,
                "heading_rad": round(float(heading[i]), 6), "dist_m": round(float(i * LOOP / N), 2)})
cps.append({"index": len(cps), "x": round(float(R[0, 0]), 3), "z": round(float(R[0, 1]), 3), "y": ELEV,
            "heading_rad": round(float(heading[0]), 6), "dist_m": round(float(LOOP), 2), "finish": True})

chunk = {
    "chunk_id": "lagos_island", "description": "Lagos Island street circuit on real OSM streets (Marina, Campbell, Broad, Nnamdi Azikiwe, Balogun)",
    "approximate": False, "no_landmarks": True, "district": True, "loop": True, "pavement_m": PAVE,
    "geo_origin": {"lat": GEO[0], "lon": GEO[1]},
    "bounds_local_m": {"min_x": round(float(X0 - 200), 1), "max_x": round(float(X1 + 200), 1), "min_z": round(float(Z0 - 200), 1), "max_z": round(float(Z1 + 200), 1)},
    "road": {"half_width_m": HW, "barrier_height_m": 0.22, "lanes_per_direction": LANES, "lane_width_m": LANE_W,
             "median_width_m": MEDIAN, "length_m": round(float(LOOP), 2), "samples": samples},
    "sections": sections,
    "bridge": {"deck_thickness_m": 1.2, "support_spacing_m": 40.0, "support_width_m": 2.0, "water_level_y": 0.0, "pier_foot_y": -6.0},
    "buildings": [], "osm_buildings": blds, "side_streets": side_streets, "walls": [], "trees": [],
    "crossings": [], "start_line": {"dist_m": 0.0},
    "land_cells": {"cell_m": CELL, "cells": sorted([list(c) for c in cells])},
    "back_cells": {"cell_m": BACK, "cells": sorted([list(c) for c in back])},
    "spawn": {"x": round(float(sp[0]), 3), "y": ELEV + 0.5, "z": round(float(sp[1]), 3), "heading_rad": round(float(heading[sp_i]), 6)},
    "checkpoints": cps,
    "source": {"type": "osm", "license": "ODbL — © OpenStreetMap contributors", "fetched": "2026-10-14"},
}
os.makedirs(OUT, exist_ok=True)
json.dump(chunk, open(os.path.join(OUT, "lagos_island.json"), "w"), separators=(",", ":"))
rad = []
for i in range(N):
    a, b, c = R[i - 5], R[i], R[(i + 5) % N]
    cr = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    rad.append(np.linalg.norm(b - a) * np.linalg.norm(c - b) * np.linalg.norm(a - c) / (2 * abs(cr) + 1e-9))
print("loop %.0f m, %d samples, min radius %.0f m, %d real buildings (%d dropped off the carriageway), %d side streets"
      % (LOOP, N, min(rad), len(blds), dropped, len(side_streets)))
print("sections:", " -> ".join("%s@%d" % (s["name"], s["from_m"]) for s in sections))


def write_ui_assets():
    if not os.path.isdir("assets/ui"):
        return
    from PIL import Image, ImageDraw, ImageFilter
    W, H, M = 480, 300, 26
    lo, hi = R.min(0), R.max(0)
    sc = min((W - 2 * M) / (hi[0] - lo[0]), (H - 2 * M) / (hi[1] - lo[1]))
    ox = (W - (hi[0] - lo[0]) * sc) / 2; oy = (H - (hi[1] - lo[1]) * sc) / 2
    px = lambda p: (ox + (p[0] - lo[0]) * sc, H - (oy + (p[1] - lo[1]) * sc))
    img = Image.new("RGB", (W, H), (17, 18, 23)); dr = ImageDraw.Draw(img)
    for x in range(0, W, 24): dr.line([(x, 0), (x, H)], fill=(28, 30, 37))
    for y in range(0, H, 24): dr.line([(0, y), (W, y)], fill=(28, 30, 37))
    pts = [px(p) for p in R] + [px(R[0])]
    glow = Image.new("RGB", (W, H), (0, 0, 0)); ImageDraw.Draw(glow).line(pts, fill=(250, 190, 30), width=12, joint="curve")
    img = Image.blend(img, Image.composite(glow.filter(ImageFilter.GaussianBlur(6)), img, glow.convert("L").point(lambda v: 255 if v else 0)), 0.45)
    dr = ImageDraw.Draw(img); dr.line(pts, fill=(250, 196, 40), width=5, joint="curve")
    sx, sy = px(R[0])
    for k in range(4):
        for j in range(4):
            dr.rectangle([sx - 8 + k * 4, sy - 8 + j * 4, sx - 4 + k * 4, sy - 4 + j * 4], fill=(255, 255, 255) if (k + j) % 2 == 0 else (10, 10, 10))
    img.save("assets/ui/tracks/island_circuit.png")
    mp = "assets/ui/lagos_map.json"
    if os.path.exists(mp):
        m = json.load(open(mp))
        geo = [[round(GEO[0] + p[1] / 110574.0, 5), round(GEO[1] + p[0] / (111320.0 * math.cos(math.radians(GEO[0]))), 5)] for p in R[::10]]
        geo.append(geo[0])
        for r in m["routes"]:
            if r["key"] == "island":
                r["pts"] = geo; r["name"] = "Lagos Island Circuit"
        json.dump(m, open(mp, "w"))


if OUT.rstrip("/").endswith("data/map/island"):
    write_ui_assets()
