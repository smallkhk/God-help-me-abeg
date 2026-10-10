"""Assign real building heights from Google Open Buildings 2.5D Temporal (2023)
to every building footprint in the game chunks. Downloads one 12.5 km tile at a
time (gsutil), reads only small windows, then deletes it."""
import json, math, os, subprocess, sys
import numpy as np, tifffile, zarr

WORK, MANIFEST_DIR, *CHUNKS = sys.argv[1:]

def utm(lat, lon, zone=31):
    a=6378137.0;f=1/298.257223563;k0=0.9996;e2=f*(2-f);ep2=e2/(1-e2)
    lon0=math.radians((zone-1)*6-180+3);phi=math.radians(lat);lam=math.radians(lon)
    N=a/math.sqrt(1-e2*math.sin(phi)**2);T=math.tan(phi)**2;C=ep2*math.cos(phi)**2;A=math.cos(phi)*(lam-lon0)
    M=a*((1-e2/4-3*e2**2/64-5*e2**3/256)*phi-(3*e2/8+3*e2**2/32+45*e2**3/1024)*math.sin(2*phi)+(15*e2**2/256+45*e2**3/1024)*math.sin(4*phi)-(35*e2**3/3072)*math.sin(6*phi))
    x=k0*N*(A+(1-T+C)*A**3/6+(5-18*T+T*T+72*C-58*ep2)*A**5/120)+500000
    y=k0*(M+N*math.tan(phi)*(A*A/2+(5-T+9*C+4*C*C)*A**4/24+(61-58*T+T*T+600*C-330*ep2)*A**6/720))
    return x, y

# tiles
tiles = []
for fn in os.listdir(MANIFEST_DIR):
    if not fn.endswith(".json"): continue
    j = json.load(open(os.path.join(MANIFEST_DIR, fn)))
    for ts in j["tilesets"]:
        for s in ts["sources"]:
            t = s["affineTransform"]; w = s["dimensions"]["width"]; h = s["dimensions"]["height"]
            tiles.append({"uri": j["uriPrefix"] + s["uris"][0], "x0": t["translateX"], "y1": t["translateY"], "w": w, "h": h})

# buildings -> utm polygons
chunks = []
jobs = {}  # tile index -> list of (chunk i, bldg i, utm pts)
for ci, path in enumerate(CHUNKS):
    c = json.load(open(path)); chunks.append(c)
    lat0 = c["geo_origin"]["lat"]; lon0 = c["geo_origin"]["lon"]
    kx = 111320.0 * math.cos(math.radians(lat0))
    for bi, b in enumerate(c["osm_buildings"]):
        u = [utm(lat0 + z / 110574.0, lon0 + x / kx) for x, z in b["pts"]]
        cx = sum(p[0] for p in u) / len(u); cy = sum(p[1] for p in u) / len(u)
        for ti, t in enumerate(tiles):
            if t["x0"] <= cx < t["x0"] + t["w"] * 0.5 and t["y1"] - t["h"] * 0.5 < cy <= t["y1"]:
                jobs.setdefault(ti, []).append((ci, bi, u)); break
print("buildings per tile:", {tiles[k]["uri"].split("/")[-1]: len(v) for k, v in jobs.items()}, flush=True)

got = 0
for ti, items in jobs.items():
    t = tiles[ti]; local = os.path.join(WORK, os.path.basename(t["uri"]))
    subprocess.run(["gsutil", "-q", "cp", t["uri"], local], check=True)
    store = tifffile.imread(local, aszarr=True)
    arr = zarr.open(store, mode="r")
    if isinstance(arr, zarr.Group): arr = arr["0"]
    for ci, bi, u in items:
        cols = [(p[0] - t["x0"]) / 0.5 for p in u]; rows = [(t["y1"] - p[1]) / 0.5 for p in u]
        c0 = max(int(min(cols)), 0); c1 = min(int(max(cols)) + 1, t["w"])
        r0 = max(int(min(rows)), 0); r1 = min(int(max(rows)) + 1, t["h"])
        if c1 - c0 < 2 or r1 - r0 < 2: continue
        # shrink to the inner part of the footprint (avoid edge pixels)
        mc = (c1 - c0) // 4; mr = (r1 - r0) // 4
        hgt = np.asarray(arr[1, r0 + mr:r1 - mr, c0 + mc:c1 - mc])
        pres = np.asarray(arr[2, r0 + mr:r1 - mr, c0 + mc:c1 - mc])
        v = hgt[(pres > 0.5) & (hgt > 1.0)]
        if v.size >= 4:
            chunks[ci]["osm_buildings"][bi]["h"] = round(float(np.percentile(v, 75)), 1)
            chunks[ci]["osm_buildings"][bi]["hsrc"] = "g25d"
            got += 1
    store.close(); os.remove(local)
    print("done", os.path.basename(local), "total heights", got, flush=True)

for path, c in zip(CHUNKS, chunks):
    hs = [b["h"] for b in c["osm_buildings"] if b.get("hsrc") == "g25d"]
    print(path, "real heights:", len(hs), "/", len(c["osm_buildings"]),
          "max %.0f m, median %.1f m" % (max(hs), sorted(hs)[len(hs) // 2]) if hs else "")
    json.dump(c, open(path, "w"))
