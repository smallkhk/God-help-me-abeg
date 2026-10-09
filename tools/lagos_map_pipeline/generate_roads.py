#!/usr/bin/env python3
"""Stage 3 — turn the processed centerline into road-build data (spec §8.2 5-7).

We do NOT bake a mesh here. The road width, elevation and per-sample frames are
written out, and the Godot @tool `map_builder.gd` extrudes the actual mesh +
collision in-engine (keeps in-game geometry in GDScript, spec §9.2, and keeps
road topology / visuals / collision as separate concerns, spec §4.3).

Also derives ordered checkpoint positions in the correct travel direction
(spec §8.3) from config["checkpoints_along_route"].

Output: work/03_road.json
"""
from __future__ import annotations
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--inp", default=os.path.join(HERE, "work", "02_local_centerline.json"))
    ap.add_argument("--out", default=os.path.join(HERE, "work", "03_road.json"))
    args = ap.parse_args()

    with open(args.config, encoding="utf-8") as f:
        cfg = json.load(f)
    with open(args.inp, encoding="utf-8") as f:
        proc = json.load(f)

    r = cfg["road"]
    half_width = (r["lanes_per_direction"] * r["lane_width_m"] * 2
                  + r["median_width_m"]) / 2.0 + r["shoulder_width_m"]
    samples = proc["samples"]
    length = proc["length_m"]

    checkpoints = []
    for i, frac in enumerate(cfg.get("checkpoints_along_route", [])):
        target = frac * length
        # nearest sample at/after target
        s = min(samples, key=lambda q: abs(q["dist_m"] - target))
        checkpoints.append({
            "index": i,
            "x": s["x"], "z": s["z"],
            "y": s["elev_m"],
            "heading_rad": s["heading_rad"],
            "dist_m": s["dist_m"],
        })

    out = {
        "half_width_m": round(half_width, 3),
        "barrier_height_m": r["barrier_height_m"],
        "lanes_per_direction": r["lanes_per_direction"],
        "lane_width_m": r["lane_width_m"],
        "median_width_m": r["median_width_m"],
        "length_m": length,
        "samples": samples,
        "checkpoints": checkpoints,
    }
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
    print(f"[generate_roads] half-width {half_width:.2f} m, {len(checkpoints)} checkpoints -> {args.out}",
          file=sys.stderr)


if __name__ == "__main__":
    main()
