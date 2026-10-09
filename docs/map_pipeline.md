# Lagos bridge map pipeline

Spec references: §3.3 (geographic accuracy), §8 (road/map pipeline), §4.3 (chunking).

## Principle

The map is **generated from data**, never hand-built mesh-by-mesh, so it can be
regenerated after fixes (spec §8.2 step 14, §21). The pipeline is split so that
**road topology, visuals and collision stay separate concerns** (spec §4.3):

```
config.json / OSM  ──►  Python pipeline  ──►  chunk JSON  ──►  map_builder.gd (Godot @tool)
   (source data)       (offline, no net)     (data/map/…)      (mesh + collision + props)
```

Python runs outside Godot and only writes files Godot reads; there are **no
runtime downloads** (spec §9.2). Mesh + collision are built in-engine in GDScript
from the chunk JSON.

## Stages (`tools/lagos_map_pipeline/`)

| Stage | Script | Output |
|---|---|---|
| 1 Extract | `extract_osm.py` | `work/01_raw_centerline.json` |
| 2 Process | `process_roads.py` | `work/02_local_centerline.json` |
| 3 Roads | `generate_roads.py` | `work/03_road.json` |
| 4 Buildings | `generate_buildings.py` | `work/04_buildings.json` |
| 5 Export | `export_chunks.py` | `data/map/lagos_bridge/<chunk_id>.json` |

Run everything:

```bash
python3 tools/lagos_map_pipeline/build_all.py
```

- **Coordinate transform** (`geo.py`): WGS84 → local metres via a local-tangent
  (equirectangular) projection about a documented origin. Raw lat/lon is never a
  world position (spec §3.3). East→+X, North→+Z, Up→+Y. The processor prints an
  endpoint distance check against the great-circle distance (preserves
  approximate real-world distances, spec §18).
- **Chunk fields** (spec §8.5): id, description, `approximate` flag, geo origin,
  local bounds, road graph (centerline samples with elevation/heading/on_bridge),
  bridge params, building footprints, spawn, ordered checkpoints, source/license.

## Swapping in real OpenStreetMap data

The committed alignment is a **synthetic approximation** so the bridge is
driveable offline today. To use real geometry:

1. Download a **small bounded** OSM extract around the bridge (e.g. an
   `.osm` XML export from openstreetmap.org for a limited bbox — not all of
   Lagos). Do **not** use Google Maps/Earth imagery or 3D content (spec §3.3).
2. In `config.json` set `source.type` to `"osm"`, `source.osm_file` to the
   file path, and `source.osm_way_ids` to the bridge's way id(s).
3. Re-run `build_all.py`. If the extract is untrusted, run with `python3 -I`.
4. OSM gives alignment only — **bridge deck height, deck elevation, pier
   locations and lane markings are not reliable in OSM** (spec §3.3). Keep
   correcting `bridge.*` and the `elev_m` / `on_bridge` values by hand and
   re-exporting.

## In-engine build (`scripts/world/map_builder.gd`)

A `@tool` node. Tick its **build** checkbox in the editor to regenerate, or let
it build at runtime in `_ready`. Produces, under a `Generated` child:

- `RoadMesh` + `RoadCollision` (trimesh matching the visible surface, spec §8.3).
- Raised edge **barriers** welded into the road mesh (so collision covers them).
- `Piers` under on-bridge samples at `support_spacing_m`.
- `Lagoon` water plane at `water_level_y`.
- `Skyline` distant buildings as a MultiMesh (deterministic from the seed).

## Known limitations (be honest, spec §8.3)

- Alignment is approximate until a real OSM extract is wired in — the chunk's
  `approximate` flag is `true` and nothing claims survey accuracy.
- Junctions, approach road connections and adjacent urban streets are not built
  yet (that is Milestone 5 / map expansion §4.3).
- Barriers are a simple raised lip, not modelled railings.
