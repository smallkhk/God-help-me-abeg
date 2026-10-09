#!/usr/bin/env python3
"""Stage 5 — assemble the final map chunk (spec §8.2 step 11, §8.5).

Combines road + buildings + bridge/water params + source/license metadata into
a single chunk JSON with the stable fields the spec lists for a chunk (§8.5):
id, geographic bounds, local origin, road graph, visual/collision references
(here: the build params the Godot @tool reads), spawn + checkpoint metadata,
and license/source metadata.

Output: res://data/map/lagos_bridge/<chunk_id>.json  (consumed by map_builder.gd)
"""
from __future__ import annotations
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--road", default=os.path.join(HERE, "work", "03_road.json"))
    ap.add_argument("--buildings", default=os.path.join(HERE, "work", "04_buildings.json"))
    ap.add_argument("--out-dir", default=os.path.join(REPO, "data", "map", "lagos_bridge"))
    args = ap.parse_args()

    with open(args.config, encoding="utf-8") as f:
        cfg = json.load(f)
    with open(args.road, encoding="utf-8") as f:
        road = json.load(f)
    with open(args.buildings, encoding="utf-8") as f:
        buildings = json.load(f)["buildings"]

    xs = [s["x"] for s in road["samples"]]
    zs = [s["z"] for s in road["samples"]]
    bounds = {"min_x": min(xs), "max_x": max(xs), "min_z": min(zs), "max_z": max(zs)}

    # Spawn a little way INTO the route (not on sample 0, which is the road
    # mesh's leading edge — a car placed exactly on that boundary vertex can
    # fall past it). ~20 m in puts all four wheels firmly on the deck. Height is
    # set so the wheels start within suspension contact range of the surface.
    spawn_s = min(road["samples"], key=lambda q: abs(q["dist_m"] - 20.0))
    spawn = {"x": spawn_s["x"], "y": spawn_s["elev_m"] + 0.5, "z": spawn_s["z"],
             "heading_rad": spawn_s["heading_rad"]}

    chunk = {
        "chunk_id": cfg["chunk_id"],
        "description": cfg["description"],
        "approximate": cfg["source"]["type"] == "synthetic",
        "geo_origin": cfg["geo_origin"],
        "bounds_local_m": bounds,
        "road": {
            "half_width_m": road["half_width_m"],
            "barrier_height_m": road["barrier_height_m"],
            "lanes_per_direction": road["lanes_per_direction"],
            "lane_width_m": road["lane_width_m"],
            "median_width_m": road["median_width_m"],
            "length_m": road["length_m"],
            "samples": road["samples"],
        },
        "bridge": cfg["bridge"],
        "buildings": buildings,
        "spawn": spawn,
        "checkpoints": road["checkpoints"],
        "source": cfg["source"],
    }

    os.makedirs(args.out_dir, exist_ok=True)
    out_path = os.path.join(args.out_dir, cfg["chunk_id"] + ".json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(chunk, f, indent=2)
    print(f"[export_chunks] chunk '{cfg['chunk_id']}' "
          f"({road['length_m']:.0f} m, {len(buildings)} buildings, "
          f"{len(road['checkpoints'])} checkpoints) -> {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
