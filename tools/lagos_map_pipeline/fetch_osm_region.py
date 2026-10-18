#!/usr/bin/env python3
"""Download OpenStreetMap tiles for a region and parse them into the compact
JSON the circuit generator reads (same format as work/island_osm.json):
  {"nodes": {id: [lat, lon]}, "roads": [{id, type, name, lanes, oneway,
   bridge, layer, nds}], "buildings": [{id, pts, height, levels, name}]}

Map data © OpenStreetMap contributors (ODbL). Development-time only: the game
never downloads anything.

  python3 -I tools/lagos_map_pipeline/fetch_osm_region.py \
      --bbox 6.418,3.405,6.462,3.445 --tiles-dir <scratch>/osm_vi \
      --out tools/lagos_map_pipeline/work/vi_ikoyi_osm.json
"""
import argparse, json, os, subprocess, time
import xml.etree.ElementTree as ET

ROAD_TYPES = {"motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary",
              "secondary_link", "tertiary", "tertiary_link", "residential", "unclassified", "service",
              "pedestrian", "living_street"}


def fetch(bbox, step, tiles_dir):
    s, w, n, e = bbox
    os.makedirs(tiles_dir, exist_ok=True)
    paths = []
    lat = s
    k = 0
    while lat < n - 1e-9:
        lon = w
        while lon < e - 1e-9:
            p = os.path.join(tiles_dir, "t%03d.osm" % k)
            if not os.path.exists(p) or os.path.getsize(p) < 200:
                url = "https://api.openstreetmap.org/api/0.6/map?bbox=%.4f,%.4f,%.4f,%.4f" % (
                    lon, lat, min(lon + step, e), min(lat + step, n))
                for attempt in range(4):
                    r = subprocess.run(["curl", "-s", "--max-time", "90", "-o", p, "-w", "%{http_code}", url],
                                       capture_output=True, text=True)
                    if r.stdout.strip() == "200":
                        break
                    time.sleep(2 ** attempt)
                print("tile", k, r.stdout.strip(), os.path.getsize(p) if os.path.exists(p) else 0)
            paths.append(p)
            k += 1
            lon += step
        lat += step
    return paths


def parse(paths):
    nodes, roads, blds = {}, {}, {}
    for p in paths:
        try:
            root = ET.parse(p).getroot()
        except ET.ParseError:
            print("skip bad tile", p)
            continue
        for nd in root.iter("node"):
            nodes[int(nd.get("id"))] = [float(nd.get("lat")), float(nd.get("lon"))]
        for way in root.iter("way"):
            wid = int(way.get("id"))
            tags = {t.get("k"): t.get("v") for t in way.findall("tag")}
            nds = [int(x.get("ref")) for x in way.findall("nd")]
            if tags.get("highway") in ROAD_TYPES:
                roads[wid] = {"id": wid, "type": tags["highway"], "name": tags.get("name", ""),
                              "lanes": tags.get("lanes", ""), "oneway": tags.get("oneway", ""),
                              "bridge": tags.get("bridge", ""), "layer": tags.get("layer", ""), "nds": nds}
            elif "building" in tags and len(nds) >= 4:
                blds[wid] = {"id": wid, "nds": nds, "height": tags.get("height", ""),
                             "levels": tags.get("building:levels", ""), "name": tags.get("name", "")}
    out_b = []
    for b in blds.values():
        if all(n in nodes for n in b["nds"]):
            out_b.append({"id": b["id"], "pts": [nodes[n] for n in b["nds"]], "height": b["height"],
                          "levels": b["levels"], "name": b["name"]})
    road_list = [r for r in roads.values() if all(n in nodes for n in r["nds"])]
    used = {n for r in road_list for n in r["nds"]}
    return {"nodes": {str(k): v for k, v in nodes.items() if k in used}, "roads": road_list,
            "buildings": out_b, "areas": []}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--bbox", required=True, help="south,west,north,east")
    ap.add_argument("--step", type=float, default=0.008)
    ap.add_argument("--tiles-dir", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    bb = [float(x) for x in a.bbox.split(",")]
    d = parse(fetch(bb, a.step, a.tiles_dir))
    json.dump(d, open(a.out, "w"))
    print("roads", len(d["roads"]), "buildings", len(d["buildings"]), "nodes", len(d["nodes"]))
