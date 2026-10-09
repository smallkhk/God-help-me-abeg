#!/usr/bin/env python3
"""Stage 2 — normalise + clean + resample the centerline (spec §8.2 steps 2-4).

  * Convert lat/lon -> local metres about the documented origin (geo.py).
  * Drop duplicate / near-coincident points while preserving topology.
  * Resample to a uniform spacing so road segments and checkpoints are even.
  * Carry elevation + on_bridge flags (interpolated), and compute cumulative
    distance + heading for each sample.

Output: work/02_local_centerline.json
"""
from __future__ import annotations
import argparse
import json
import math
import os
import sys

import geo

HERE = os.path.dirname(os.path.abspath(__file__))


def _resample(pts: list[dict], spacing: float) -> list[dict]:
    # pts carry x,z,elev_m,on_bridge. Walk the polyline at fixed spacing.
    out: list[dict] = []
    # cumulative length of the source polyline
    seg_lens = []
    total = 0.0
    for i in range(len(pts) - 1):
        d = math.dist((pts[i]["x"], pts[i]["z"]), (pts[i + 1]["x"], pts[i + 1]["z"]))
        seg_lens.append(d)
        total += d
    n = max(1, int(round(total / spacing)))
    for k in range(n + 1):
        target = min(total, k * (total / n))
        # locate segment
        acc = 0.0
        seg = 0
        while seg < len(seg_lens) and acc + seg_lens[seg] < target:
            acc += seg_lens[seg]
            seg += 1
        seg = min(seg, len(seg_lens) - 1)
        local_t = 0.0 if seg_lens[seg] == 0 else (target - acc) / seg_lens[seg]
        a, b = pts[seg], pts[seg + 1]
        out.append({
            "x": a["x"] + (b["x"] - a["x"]) * local_t,
            "z": a["z"] + (b["z"] - a["z"]) * local_t,
            "elev_m": a["elev_m"] + (b["elev_m"] - a["elev_m"]) * local_t,
            "on_bridge": a["on_bridge"] if local_t < 0.5 else b["on_bridge"],
        })
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--inp", default=os.path.join(HERE, "work", "01_raw_centerline.json"))
    ap.add_argument("--out", default=os.path.join(HERE, "work", "02_local_centerline.json"))
    args = ap.parse_args()

    with open(args.config, encoding="utf-8") as f:
        cfg = json.load(f)
    with open(args.inp, encoding="utf-8") as f:
        raw = json.load(f)["points"]

    lat0 = cfg["geo_origin"]["lat"]
    lon0 = cfg["geo_origin"]["lon"]
    spacing = float(cfg["road"]["resample_spacing_m"])

    # project + dedupe
    projected: list[dict] = []
    for p in raw:
        x, z = geo.latlon_to_local(p["lat"], p["lon"], lat0, lon0)
        item = {"x": x, "z": z, "elev_m": float(p.get("elev_m", 0.0)),
                "on_bridge": bool(p.get("on_bridge", True))}
        if projected and math.dist((projected[-1]["x"], projected[-1]["z"]), (x, z)) < 0.5:
            continue  # drop near-duplicate (spec §8.2 step 3)
        projected.append(item)

    if len(projected) < 2:
        raise SystemExit("not enough distinct points after projection")

    samples = _resample(projected, spacing)

    # cumulative distance + heading
    cum = 0.0
    for i, s in enumerate(samples):
        if i > 0:
            cum += math.dist((samples[i - 1]["x"], samples[i - 1]["z"]), (s["x"], s["z"]))
        s["dist_m"] = cum
        if i < len(samples) - 1:
            dx = samples[i + 1]["x"] - s["x"]
            dz = samples[i + 1]["z"] - s["z"]
        else:
            dx = s["x"] - samples[i - 1]["x"]
            dz = s["z"] - samples[i - 1]["z"]
        s["heading_rad"] = math.atan2(dx, dz)  # bearing from +Z (north) toward +X (east)

    # distance-preservation check vs great-circle (spec §18)
    gc = geo.haversine_m(raw[0]["lat"], raw[0]["lon"], raw[-1]["lat"], raw[-1]["lon"])
    straight_local = math.dist((samples[0]["x"], samples[0]["z"]), (samples[-1]["x"], samples[-1]["z"]))
    err = abs(gc - straight_local)

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({
            "origin": {"lat": lat0, "lon": lon0},
            "length_m": round(samples[-1]["dist_m"], 2),
            "spacing_m": spacing,
            "samples": samples,
        }, f, indent=2)
    print(f"[process_roads] {len(samples)} samples, length {samples[-1]['dist_m']:.1f} m; "
          f"endpoint distance check: great-circle {gc:.1f} m vs local {straight_local:.1f} m "
          f"(delta {err:.2f} m) -> {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
