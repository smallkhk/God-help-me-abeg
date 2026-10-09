#!/usr/bin/env python3
"""Real Lagos buildings from OpenStreetMap tiles (© OpenStreetMap contributors, ODbL).

Reads .osm tiles, extracts every closed `building=*` way, converts the footprint
to local metres (same origin as the road chunk), picks a height from OSM
`height` / `building:levels` or a deterministic default, and also derives a
"land" grid (50 m cells that contain buildings, dilated) so buildings sit on
ground instead of in the lagoon. Merges the result into the road chunk JSON.

  python3 -I tools/lagos_map_pipeline/generate_osm_buildings.py \
      --tiles a.osm b.osm --chunk data/map/lagos_bridge/third_mainland_bridge.json
"""
from __future__ import annotations
import argparse, json, math, os, sys, zlib
import xml.etree.ElementTree as ET

M_LAT = 110574.0
M_LON = 111320.0
CELL = 50.0


def to_local(lat, lon, lat0, lon0):
    return ((lon - lon0) * M_LON * math.cos(math.radians(lat0)), (lat - lat0) * M_LAT)


def height_for(tags, wid):
    h = tags.get("height", "").replace("m", "").strip()
    try:
        return max(3.0, min(float(h), 160.0))
    except ValueError:
        pass
    lv = tags.get("building:levels", "")
    try:
        return max(3.0, min(float(lv) * 3.2, 160.0))
    except ValueError:
        pass
    # deterministic Lagos-ish default: mostly 1-4 storeys, occasional taller
    r = zlib.crc32(wid.encode()) % 100
    if r < 55: return 4.0 + (r % 4)          # bungalows / 1-storey
    if r < 85: return 8.0 + (r % 7)          # 2-4 storeys
    if r < 97: return 15.0 + (r % 12)        # 5-8 storeys
    return 30.0 + (r % 30)                   # occasional tower


def area(pts):
    a = 0.0
    for i in range(len(pts)):
        x1, z1 = pts[i]; x2, z2 = pts[(i + 1) % len(pts)]
        a += x1 * z2 - x2 * z1
    return abs(a) / 2.0


def dist_to_route(x, z, route, step=4):
    best = 1e18
    for i in range(0, len(route), step):
        dx = route[i][0] - x; dz = route[i][1] - z
        d = dx * dx + dz * dz
        if d < best: best = d
    return math.sqrt(best)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiles", nargs="+", required=True)
    ap.add_argument("--chunk", required=True)
    ap.add_argument("--max", type=int, default=6000)
    a = ap.parse_args()

    chunk = json.load(open(a.chunk, encoding="utf-8"))
    lat0 = chunk["geo_origin"]["lat"]; lon0 = chunk["geo_origin"]["lon"]
    route = [(s["x"], s["z"]) for s in chunk["road"]["samples"]]
    clear = chunk["road"]["half_width_m"] + 6.0

    nodes, ways, seen = {}, [], set()
    for p in a.tiles:
        root = ET.parse(p).getroot()
        for n in root.findall("node"):
            nodes[n.get("id")] = (float(n.get("lat")), float(n.get("lon")))
        for w in root.findall("way"):
            wid = w.get("id")
            if wid in seen: continue
            tags = {c.get("k"): c.get("v") for c in w.findall("tag")}
            if "building" not in tags: continue
            seen.add(wid)
            ways.append((wid, tags, [nd.get("ref") for nd in w.findall("nd")]))

    out = []
    for wid, tags, refs in ways:
        if len(refs) < 4 or refs[0] != refs[-1]: continue
        if any(r not in nodes for r in refs): continue
        pts = [to_local(*nodes[r], lat0, lon0) for r in refs[:-1]]
        ar = area(pts)
        if ar < 20.0: continue
        cx = sum(p[0] for p in pts) / len(pts); cz = sum(p[1] for p in pts) / len(pts)
        if dist_to_route(cx, cz, route) < clear: continue   # never on the road
        out.append({"pts": [[round(p[0], 2), round(p[1], 2)] for p in pts],
                    "h": round(height_for(tags, wid), 1), "a": ar})
    # keep the biggest footprints if over budget (perf on low-end GPUs)
    out.sort(key=lambda b: -b["a"])
    out = out[: a.max]
    for b in out: b.pop("a")

    # land grid: cells containing buildings, dilated by 1 cell
    cells = set()
    for b in out:
        for x, z in b["pts"]:
            cells.add((math.floor(x / CELL), math.floor(z / CELL)))
    land = set()
    for (i, j) in cells:
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                land.add((i + di, j + dj))
    # don't put land over the bridge deck
    land = [c for c in land
            if dist_to_route((c[0] + .5) * CELL, (c[1] + .5) * CELL, route) > clear + CELL * 0.6]

    chunk["osm_buildings"] = out
    chunk["land_cells"] = {"cell_m": CELL, "cells": sorted([list(c) for c in land])}
    chunk["buildings"] = []  # drop the old random skyline boxes
    json.dump(chunk, open(a.chunk, "w", encoding="utf-8"))
    print(f"[osm_buildings] {len(ways)} building ways -> {len(out)} kept; "
          f"{len(land)} land cells -> {a.chunk}", file=sys.stderr)


if __name__ == "__main__":
    main()
