#!/usr/bin/env python3
"""Stitch real OSM tiles into one Third Mainland Bridge centerline.

Reads several `.osm` XML tiles (downloaded from the OpenStreetMap API during
development — spec §8.1, no runtime downloads), extracts every way tagged
name="Third Mainland Bridge", chains the segments that share endpoints into
continuous lines (the two carriageways form separate chains), picks the longest
chain as the drivable centerline, and writes it in the pipeline's stage-1 format
(work/01_raw_centerline.json) so process_roads.py can carry on unchanged.

Elevation is not in OSM for the deck, so a simple bridge profile is applied:
low at both approaches, raised over the lagoon (spec §3.3 — height must be
modelled, not trusted from OSM).

Run (untrusted downloaded XML → use -I):
  python3 -I tools/lagos_map_pipeline/stitch_osm_tiles.py --tiles a.osm b.osm ... \
      --out tools/lagos_map_pipeline/work/01_raw_centerline.json
"""
from __future__ import annotations
import argparse
import json
import math
import os
import xml.etree.ElementTree as ET

BRIDGE_NAME = "Third Mainland Bridge"


def _tag(elem, key):
    for c in elem.findall("tag"):
        if c.get("k") == key:
            return c.get("v")
    return None


def load_tiles(paths):
    nodes = {}            # id -> (lat, lon)
    segments = []         # list of node-id lists (one per TMB way), de-duped by way id
    seen_ways = set()
    for p in paths:
        root = ET.parse(p).getroot()
        for n in root.findall("node"):
            nodes[n.get("id")] = (float(n.get("lat")), float(n.get("lon")))
        for w in root.findall("way"):
            if _tag(w, "name") != BRIDGE_NAME:
                continue
            wid = w.get("id")
            if wid in seen_ways:
                continue
            seen_ways.add(wid)
            refs = [nd.get("ref") for nd in w.findall("nd")]
            if len(refs) >= 2:
                segments.append(refs)
    return nodes, segments


def chain_all(segs):
    chains = []
    used = [False] * len(segs)
    for i in range(len(segs)):
        if used[i]:
            continue
        chain = list(segs[i]); used[i] = True
        extended = True
        while extended:
            extended = False
            for j in range(len(segs)):
                if used[j]:
                    continue
                s = segs[j]
                if s[0] == chain[-1]:
                    chain.extend(s[1:]); used[j] = True; extended = True
                elif s[-1] == chain[-1]:
                    chain.extend(list(reversed(s))[1:]); used[j] = True; extended = True
                elif s[-1] == chain[0]:
                    chain = s[:-1] + chain; used[j] = True; extended = True
                elif s[0] == chain[0]:
                    chain = list(reversed(s))[:-1] + chain; used[j] = True; extended = True
        chains.append(chain)
    return chains


def chain_length_m(chain, nodes):
    total = 0.0
    for a, b in zip(chain, chain[1:]):
        la, lo = nodes[a]; lb, ob = nodes[b]
        dlat = (lb - la) * 110574.0
        dlon = (ob - lo) * 111320.0 * math.cos(math.radians(la))
        total += math.hypot(dlat, dlon)
    return total


def apply_bridge_profile(points):
    """low approaches, raised deck over the lagoon."""
    n = len(points)
    for i, p in enumerate(points):
        f = i / max(n - 1, 1)
        # smooth hump: ~2 m at ends, ~12 m across the middle
        hump = math.sin(math.pi * f)
        p["elev_m"] = round(2.0 + 10.0 * hump, 2)
        p["on_bridge"] = 0.08 < f < 0.92


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiles", nargs="+", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    nodes, segments = load_tiles(args.tiles)
    if not segments:
        raise SystemExit("no 'Third Mainland Bridge' ways found in tiles")
    chains = chain_all(segments)
    # keep only chains whose nodes we actually have coords for
    chains = [[nd for nd in c if nd in nodes] for c in chains]
    chains = [c for c in chains if len(c) >= 2]
    chains.sort(key=lambda c: chain_length_m(c, nodes), reverse=True)
    best = chains[0]
    length = chain_length_m(best, nodes)

    points = [{"lat": nodes[nd][0], "lon": nodes[nd][1]} for nd in best]
    apply_bridge_profile(points)

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"source_type": "osm_real", "points": points}, f, indent=2)
    print(f"[stitch_osm_tiles] {len(segments)} TMB segments -> {len(chains)} chains; "
          f"longest = {len(best)} pts, {length:.0f} m -> {args.out}")


if __name__ == "__main__":
    main()
