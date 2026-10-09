# Source data & asset licensing

Spec references: §3.3, §8.1, §22. **Review this before distribution.**

## Current map data

The committed bridge alignment
(`tools/lagos_map_pipeline/config.json` → `data/map/lagos_bridge/*.json`) is a
**synthetic approximation authored for this project**. It is not surveyed data
and is not derived from any third party. The chunk JSON carries
`"approximate": true`. Nothing in the game should present it as an exact
representation of Third Mainland Bridge.

## If you use OpenStreetMap

If you swap in OpenStreetMap data (see `docs/map_pipeline.md`):

- OSM data is licensed under the **Open Database License (ODbL)**. It carries
  **attribution** and potentially **share-alike** obligations for the database.
- Add visible attribution: **“© OpenStreetMap contributors”** and review the
  current terms before shipping:
  - https://www.openstreetmap.org/copyright
  - https://osmfoundation.org/wiki/Licence/Licence_and_Legal_FAQ
- Package the generated, legally usable assets for **offline** play. Do not make
  the game depend on live map tiles (spec §9.2).

## Prohibited sources

- **Do not** scrape or convert Google Maps / Google Earth imagery or 3D geometry
  unless the exact use is permitted by their terms (spec §3.3).

## Branding & assets

- Use **fictional** company names, sign designs, vehicle names and badges. Avoid
  real manufacturer logos, trademarks and copied vehicle models unless licensed
  (spec §4.1, §6.2).
- Ship no copyrighted songs or unlicensed vehicle recordings (spec §14).

## Third-party runtime

- Engine: **Godot 4.4** (MIT). Verify API against the pinned minor version before
  edits (spec §9.4, §22).

## Google Open Buildings (building footprints)

Building footprints around Third Mainland Bridge come from **Google Open Buildings
v3** (https://sites.research.google/open-buildings/), licensed **CC BY 4.0** (also
available under ODbL). Required attribution: *"Building footprints © Google Open
Buildings, CC BY 4.0."* Heights are NOT in this dataset; they are estimated from
footprint size. Road geometry remains © OpenStreetMap contributors (ODbL).

## Textures (assets/textures/)

Photo textures from ambientCG (https://ambientcg.com), CC0 1.0 public domain —
no attribution required: Plaster001, Asphalt026C, RoofingTiles006,
CorrugatedSteel005, Concrete034 (colour maps, resized to 512px).
