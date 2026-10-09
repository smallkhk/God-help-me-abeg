#!/usr/bin/env python3
"""Stage 1 — extract an ordered road centerline (spec §8.2 step 1).

Two sources (chosen by config["source"]["type"]):
  * "synthetic": use the hand-authored approximate polyline in config.json.
    This is a placeholder so the map is driveable offline before a real extract
    is wired in. It is NOT surveyed data (spec §3.3, §8.3).
  * "osm": parse a local OpenStreetMap .osm XML file and follow the listed way
    ids, concatenating their node coordinates in order. No network access
    (spec §3.3 offline-first, §9.2 no runtime downloads).

Output: work/01_raw_centerline.json

Run untrusted OSM files safely: this script only reads the XML you pass and
writes JSON; invoke with `python3 -I` when the .osm came from the internet.
"""
from __future__ import annotations
import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))


def load_config(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def from_synthetic(cfg: dict) -> list[dict]:
    pts = cfg["centerline_latlon"]
    if len(pts) < 2:
        raise SystemExit("synthetic centerline needs at least 2 points")
    return [dict(p) for p in pts]


def from_osm(cfg: dict, osm_path: str) -> list[dict]:
    way_ids = set(str(w) for w in cfg["source"].get("osm_way_ids", []))
    if not way_ids:
        raise SystemExit("source.type == 'osm' but no osm_way_ids listed in config")
    tree = ET.parse(osm_path)
    root = tree.getroot()

    nodes: dict[str, tuple[float, float]] = {}
    for n in root.findall("node"):
        nodes[n.get("id")] = (float(n.get("lat")), float(n.get("lon")))

    ordered: list[dict] = []
    for way in root.findall("way"):
        if way.get("id") not in way_ids:
            continue
        for nd in way.findall("nd"):
            ref = nd.get("ref")
            if ref in nodes:
                lat, lon = nodes[ref]
                ordered.append({"lat": lat, "lon": lon, "elev_m": 0.0, "on_bridge": True})
    if len(ordered) < 2:
        raise SystemExit("OSM extract produced < 2 centerline points; check way ids")
    return ordered


def main() -> None:
    ap = argparse.ArgumentParser(description="Extract road centerline for the Lagos bridge chunk.")
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--out", default=os.path.join(HERE, "work", "01_raw_centerline.json"))
    args = ap.parse_args()

    cfg = load_config(args.config)
    src = cfg["source"]["type"]
    if src == "synthetic":
        pts = from_synthetic(cfg)
    elif src == "osm":
        osm_file = cfg["source"].get("osm_file", "")
        if not osm_file or not os.path.exists(osm_file):
            raise SystemExit(f"source.osm_file not found: {osm_file!r}")
        pts = from_osm(cfg, osm_file)
    else:
        raise SystemExit(f"unknown source type: {src!r}")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"source_type": src, "points": pts}, f, indent=2)
    print(f"[extract_osm] {len(pts)} centerline points ({src}) -> {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
