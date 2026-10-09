#!/usr/bin/env python3
"""Run the full Lagos bridge map pipeline end-to-end (spec §8.2).

    python3 tools/lagos_map_pipeline/build_all.py [--config path]

Each stage is also runnable on its own (see the individual scripts). The output
is res://data/map/lagos_bridge/<chunk_id>.json, which the Godot @tool
map_builder.gd turns into road mesh, collision, bridge deck and skyline.

Regenerating after editing config.json (or swapping in a real OSM extract)
proves the pipeline is repeatable (spec §8.2 step 14, §21).
"""
from __future__ import annotations
import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PY = sys.executable


def run(script: str, extra: list[str]) -> None:
    cmd = [PY, os.path.join(HERE, script)] + extra
    print(f"\n=== {script} ===", file=sys.stderr)
    subprocess.run(cmd, check=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    args = ap.parse_args()
    cfg = ["--config", args.config]
    run("extract_osm.py", cfg)
    run("process_roads.py", cfg)
    run("generate_roads.py", cfg)
    run("generate_buildings.py", cfg)
    run("export_chunks.py", cfg)
    print("\n[build_all] pipeline complete.", file=sys.stderr)


if __name__ == "__main__":
    main()
