"""Add the real OSM side streets near the race road to a chunk as 'side_streets'
(polylines in local metres + width). Rendered as sandy/laterite streets."""
import json, math, sys, xml.etree.ElementTree as ET
chunk_path, keep, *tiles = sys.argv[1], float(sys.argv[2]), *sys.argv[3:]
KINDS = {"residential": 6.0, "unclassified": 6.0, "tertiary": 8.0, "service": 4.5,
         "living_street": 5.0, "track": 4.0, "secondary": 9.0, "primary": 10.0}
c = json.load(open(chunk_path))
lat0, lon0 = c["geo_origin"]["lat"], c["geo_origin"]["lon"]
kx = 111320.0 * math.cos(math.radians(lat0))
route = [(s["x"], s["z"]) for s in c["road"]["samples"]][::3]
hw = c["road"]["half_width_m"]
def dmin(x, z): return min(math.hypot(x - a, z - b) for a, b in route)
nodes, ways, seen = {}, [], set()
for t in tiles:
    r = ET.parse(t).getroot()
    for n in r.findall("node"): nodes[n.get("id")] = (float(n.get("lat")), float(n.get("lon")))
    for w in r.findall("way"):
        tg = {e.get("k"): e.get("v") for e in w.findall("tag")}
        if tg.get("highway") in KINDS and w.get("id") not in seen and tg.get("bridge") != "yes":
            seen.add(w.get("id")); ways.append((KINDS[tg["highway"]], [nd.get("ref") for nd in w.findall("nd")]))
out = []
for width, refs in ways:
    pts = [((nodes[r][1] - lon0) * kx, (nodes[r][0] - lat0) * 110574.0) for r in refs if r in nodes]
    # keep the parts near the race road but not on it
    seg = []
    for x, z in pts:
        d = dmin(x, z)
        if hw + 4 < d < keep:
            seg.append([round(x, 1), round(z, 1)])
        else:
            if len(seg) >= 2: out.append({"w": width, "pts": seg})
            seg = []
    if len(seg) >= 2: out.append({"w": width, "pts": seg})
c["side_streets"] = out
json.dump(c, open(chunk_path, "w"))
print(chunk_path, "side streets:", len(out), "segments, total pts", sum(len(s["pts"]) for s in out))
