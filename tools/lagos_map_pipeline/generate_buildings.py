#!/usr/bin/env python3
"""Stage 4 — synthetic shoreline skyline footprints (spec §8.4, §4.1).

Until building footprints come from an OSM extract, we scatter simple extruded
boxes in two bands offset from the road to read as a distant Lagos shoreline
silhouette (spec §4.1). Deterministic from config["skyline"]["seed"] so the map
regenerates identically (spec §8.2 step 14). Heights are bounded placeholders,
not real building data.

Output: work/04_buildings.json
"""
from __future__ import annotations
import argparse
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--inp", default=os.path.join(HERE, "work", "02_local_centerline.json"))
    ap.add_argument("--out", default=os.path.join(HERE, "work", "04_buildings.json"))
    args = ap.parse_args()

    with open(args.config, encoding="utf-8") as f:
        cfg = json.load(f)
    sky = cfg.get("skyline", {"enabled": False})
    buildings = []

    if sky.get("enabled"):
        with open(args.inp, encoding="utf-8") as f:
            samples = json.load(f)["samples"]
        rng = random.Random(sky["seed"])
        offset = sky["band_offset_m"]
        per_side = sky["count_each_side"]
        for side in (-1, 1):
            for _ in range(per_side):
                s = rng.choice(samples)
                h = s["heading_rad"]
                # perpendicular to heading, pushed out to the shoreline band
                px = math.cos(h) * side
                pz = -math.sin(h) * side
                jitter = rng.uniform(-60.0, 60.0)
                dist = offset + rng.uniform(0.0, 180.0)
                bx = s["x"] + px * dist + math.sin(h) * jitter
                bz = s["z"] + pz * dist + math.cos(h) * jitter
                height = rng.uniform(sky["min_height_m"], sky["max_height_m"])
                w = rng.uniform(8.0, 22.0)
                d = rng.uniform(8.0, 22.0)
                buildings.append({
                    "x": round(bx, 2), "z": round(bz, 2),
                    "w": round(w, 2), "d": round(d, 2), "h": round(height, 2),
                    "y_base": 0.0,
                })

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"buildings": buildings}, f, indent=2)
    print(f"[generate_buildings] {len(buildings)} skyline boxes -> {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
