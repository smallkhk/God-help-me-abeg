#!/usr/bin/env python3
"""World Streets: five small street scenes (Sketchfab models) joined into one
lap by generated connecting roads. Each scene is placed round a ring so its
street runs along the lap; smooth (Hermite) connectors link one street's exit
to the next street's entry. Writes the race chunk (several models + connector
road ranges) and a top-down plan for review.
  python3 -I world_streets.py <snow path.npy> out.json plan.png"""
import json, math, sys, numpy as np
from PIL import Image, ImageDraw

SNOW = np.load(sys.argv[1])          # snow hairpin centreline [x, y, z] (model metres)
OUT, PLAN = sys.argv[2], sys.argv[3]

# name, glb, glb units -> metres, extra scale, street path (model metres, x/z), street y (model m),
# footprint (model metres: x0, x1, z0, z1), entry mode, hidden mesh name parts, no-collision materials
ST = [
    dict(name="Hong Kong", glb="hongkong", unit=0.0254, k=1.0, path=[(-38, 14), (28, 14)], y=0.0,
         fp=(-38.6, 80.2, -38.2, 58.8), mode="t", nocol=["Material387"]),
    dict(name="Asian street", glb="asianstreet", unit=0.0254, k=1.0, path=[(-20, -60), (-20, 40)], y=0.125,
         fp=(-31.6, 25.2, -61.2, 58.0), mode="t"),
    dict(name="Euro street", glb="eurostreet", unit=1.0, k=2.0,
         path=[(-2.6, 12), (-2.6, 2), (-2.3, -4), (-0.6, -7.4), (3, -10.4), (7.5, -13.5)], y=0.035, fp=(-15.4, 38.3, -26.5, 26.4), mode="t",
         hide=["Plane_009_", "Plane_012_", "Plane_013_", "Plane_014_", "Plane_015_", "Plane_016_", "Plane_030_",
              "Cube_017_", "Cube_018_"],   # the two houses closing the lane's north end
         nocol=["node_0"]),   # lamp posts
    dict(name="Modern street", glb="modernstreet", unit=1.0, k=10.0,
         path=[(0.35, -6.0), (0.35, -1.0), (0.42, -0.74), (0.7, -0.64), (5.5, -0.65)], y=-0.3205,
         fp=(-3.47, 7.4, -5.98, 2.61), mode="l", nocol=["3.00", "5 (1)"], hide=["Cube_007"]),   # a block standing where the exit road bends
    dict(name="Snow mountain", glb="snowroad", unit=1.0, k=1.0, path=[(p[0], p[2]) for p in SNOW[0::4]] + [(SNOW[-1, 0], SNOW[-1, 2])],
         ys=[p[1] for p in SNOW[0::4]] + [SNOW[-1, 1]], nocol=["ROAD_POLE", "ROAD_SNOW_OVERLAY", "SNOW_DECAL", "SNOW_EDGE"], y=float(np.min(SNOW[:, 1])), fp=(278, 363, -324, -245), mode="u",  # hairpin bottom at street level
         hide=["MIST"], extra_fp=[(515, 1049, -1014, -60)]),
]
RING = 165.0
ANG = [0, 72, 144, 216, 288]


def rot(theta):   # Godot Basis(UP, theta) on (x, z)
    c, s = math.cos(theta), math.sin(theta)
    return lambda v: np.array([v[0] * c + v[1] * s, -v[0] * s + v[1] * c])


def ang(v):
    return math.atan2(v[1], v[0])


def resample(P, step=3.0):
    P = np.asarray(P, float)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1); cum = np.r_[0, np.cumsum(seg)]
    u = np.linspace(0, cum[-1], max(2, int(cum[-1] / step) + 1))
    return np.c_[[np.interp(u, cum, P[:, k]) for k in range(P.shape[1])]].T


placed = []
for st, a_deg in zip(ST, ANG):
    a = math.radians(a_deg)
    C = np.array([RING * math.cos(a), RING * math.sin(a)])
    t = np.array([-math.sin(a), math.cos(a)]); n = np.array([math.cos(a), math.sin(a)])
    P = np.array(st["path"], float) * st["k"]
    din = P[min(2, len(P) - 1)] - P[0]
    if st["mode"] == "u":
        want = n                      # drive out into the hairpin, come back in
        C = C + n * 30.0
    elif st["mode"] == "l":
        din = P[-1] - P[0]            # corner street: its overall chord runs along the lap
        want = t
    else:
        want = t
    theta = ang(din) - ang(want)
    R = rot(theta)
    mid = P.mean(axis=0)
    off = C - R(mid)
    W = np.array([R(p) + off for p in P])
    sc = st["unit"] * st["k"]
    ys = (np.array(st.get("ys", [st["y"]] * len(P))) * st["k"])
    oy = 2.0 - st["y"] * st["k"]
    fp = st["fp"]
    corners = np.array([R(np.array([x, z]) * st["k"]) + off for x, z in [(fp[0], fp[2]), (fp[1], fp[2]), (fp[1], fp[3]), (fp[0], fp[3])]])
    extra = []
    for fx in st.get("extra_fp", []):
        extra.append(np.array([R(np.array([x, z]) * st["k"]) + off for x, z in [(fx[0], fx[2]), (fx[1], fx[2]), (fx[1], fx[3]), (fx[0], fx[3])]]))
    placed.append(dict(st=st, W=W, Y=ys + oy, theta=theta, off=off, oy=oy, scale=sc, corners=corners, extra=extra))

# route: street, connector, street, ...
route = []      # [x, y, z, is_street]
for i, pl in enumerate(placed):
    S3 = resample(np.c_[pl["W"][:, 0], pl["Y"], pl["W"][:, 1]])
    for p in S3:
        route.append([p[0], p[1], p[2], 1])
    nx = placed[(i + 1) % len(placed)]
    p0 = pl["W"][-1]; d0 = pl["W"][-1] - pl["W"][-2]; d0 /= np.linalg.norm(d0)
    p1 = nx["W"][0]; d1 = nx["W"][1] - nx["W"][0]; d1 /= np.linalg.norm(d1)
    y0 = pl["Y"][-1]; y1 = nx["Y"][0]
    L = np.linalg.norm(p1 - p0)
    m0 = d0 * L * 0.9; m1 = d1 * L * 0.9
    n = max(4, int(L * 1.3 / 3.0))
    for k in range(1, n):
        s = k / n
        h00 = 2 * s ** 3 - 3 * s ** 2 + 1; h10 = s ** 3 - 2 * s ** 2 + s; h01 = -2 * s ** 3 + 3 * s ** 2; h11 = s ** 3 - s ** 2
        q = h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1
        yy = y0 + (y1 - y0) * (3 * s ** 2 - 2 * s ** 3)
        route.append([q[0], yy, q[1], 0])
route = np.array(route)
# connectors overlap one sample into each street (no gap where a scene's road ends early)
isst = route[:, 3].copy()
for i in range(len(route)):
    if isst[i] == 1 and (isst[i - 1] == 0 or isst[i - 2] == 0 or isst[(i + 1) % len(route)] == 0 or isst[(i + 2) % len(route)] == 0):
        route[i, 3] = 0
# start in the middle of the Hong Kong street
first_conn = int(np.argmax(route[:, 3] == 0))
start = first_conn // 2
route = np.roll(route, -start, axis=0)
Pxz = route[:, [0, 2]]
seg = np.linalg.norm(np.diff(np.vstack([Pxz, Pxz[:1]]), axis=0), axis=1)
dist = np.r_[0, np.cumsum(seg)][:-1]
L = float(np.sum(seg))
fwd = np.roll(Pxz, -1, 0) - np.roll(Pxz, 1, 0)
heading = np.arctan2(fwd[:, 0], fwd[:, 1])
samples = [{"x": round(float(p[0]), 3), "z": round(float(p[2]), 3), "elev_m": round(float(p[1]), 3), "on_bridge": False,
            "dist_m": round(float(d), 2), "heading_rad": round(float(h), 6), "street": int(p[3])} for p, d, h in zip(route, dist, heading)]
samples.append(dict(samples[0], dist_m=round(L, 2)))
N = len(route)
cps = []
for k in range(1, 9):
    i = int(N * k / 8) % N if k < 8 else 0
    s = samples[i]
    cps.append({"x": s["x"], "y": s["elev_m"], "z": s["z"], "heading_rad": s["heading_rad"], "dist_m": round(L if k == 8 else s["dist_m"], 2)})
models = []
for pl in placed:
    st = pl["st"]
    models.append({"name": st["name"], "path": "res://assets/maps/%s/%s.glb" % (st["glb"], st["glb"]), "scale": pl["scale"],
                   "yaw": round(pl["theta"], 6), "offset": [round(float(pl["off"][0]), 3), round(pl["oy"], 3), round(float(pl["off"][1]), 3)],
                   "hide": st.get("hide", []), "no_collision": ["BACKGROUND_TREES", "MIST"] + st.get("nocol", [])})
chunk = {
    "chunk_id": "world_streets", "description": "World Streets: Hong Kong, Asian street, Euro street, modern street, snow mountain",
    "approximate": False, "no_landmarks": True, "district": False, "park_ground": True, "loop": True, "ambient_traffic": False,
    "models": models, "connector": {"half_width_m": 5.0, "ground_y": 1.6},
    "road": {"half_width_m": 3.0, "barrier_height_m": 0.0, "lanes_per_direction": 2, "lane_width_m": 2.6, "median_width_m": -5.2,
             "length_m": round(L, 2), "samples": samples},
    "sections": [], "bridge": {"water_level_y": -50.0}, "buildings": [], "crossings": [], "start_line": {"dist_m": 0.0},
    "spawn": {"x": samples[0]["x"], "y": samples[0]["elev_m"] + 0.6, "z": samples[0]["z"], "heading_rad": samples[0]["heading_rad"]},
    "checkpoints": cps, "shortcuts": [],
    "source": {"type": "models", "license": "see docs/source_licenses.md (World Streets)"},
}
json.dump(chunk, open(OUT, "w"), separators=(",", ":"))
# plan
S = 1.5; O = 1100
img = Image.new("RGB", (int(2 * O * S / 1.5 * 1.0) + 1, int(2 * O * S / 1.5) + 1), (25, 25, 30)); d = ImageDraw.Draw(img)
tp = lambda x, z: ((x + O) / 1.5 * S / S * 1.0, (z + O) / 1.5)
for pl in placed:
    for ex in pl["extra"]:
        d.polygon([tp(*c) for c in ex], outline=(90, 140, 255))
    d.polygon([tp(*c) for c in pl["corners"]], outline=(160, 160, 160)); d.text(tp(*pl["W"][0]), pl["st"]["name"], fill=(255, 255, 0))
for i in range(N):
    a = route[i]; b = route[(i + 1) % N]
    d.line([tp(a[0], a[2]), tp(b[0], b[2])], fill=(255, 140, 40) if a[3] else (255, 255, 255), width=3)
d.ellipse([tp(route[0, 0], route[0, 2])[0] - 5, tp(route[0, 0], route[0, 2])[1] - 5, tp(route[0, 0], route[0, 2])[0] + 5, tp(route[0, 0], route[0, 2])[1] + 5], fill=(0, 255, 0))
img.save(PLAN)
print("lap %.0f m, %d samples, street share %.0f%%, y %.1f..%.1f" % (L, N, 100 * route[:, 3].mean(), route[:, 1].min(), route[:, 1].max()))
