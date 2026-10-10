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

## 3D models (assets/models/)

From Poly Haven (https://polyhaven.com), CC0 1.0 public domain: island_tree_01,
island_tree_02, shrub_01, shrub_02, plastic_monobloc_chair_01, portable_generator,
plastic_crate_01, old_tyre, metal_jerrycan, metal_trash_can, propane_tank,
wooden_crate_01, utility_box_01, exterior_aircon_unit, street_lamp_01,
concrete_road_barrier. Decimated and converted to .glb with Blender.

## Car models (assets/vehicles/)

- rosso.glb — "Ferrari 458 Italia" by vicent091036 (via three.js examples), CC BY 4.0.
  Draco-decoded and re-materialed in Blender. Shown in-game as "Rosso 458".
- concept.glb — "Car Concept" from KhronosGroup glTF-Sample-Assets, CC BY 4.0
  (Khronos trademarks/logos excluded).
Additional Poly Haven CC0 models: island_tree_03, street_lamp_02, concrete_road_barrier_02,
covered_car, water_manhole_cover, fire_hydrant, security_light, dutch_ship_medium,
rollershutter_door, utility_box_02 (high detail, lightly decimated).

## Audio (assets/audio/)

- engine/engine_0..5.wav — "Racing car engine sound loops", OpenGameArt, CC0.
- horn.ogg, engine_start.ogg — "Car sound effects pack", OpenGameArt, CC0.

## Landmark photo textures (assets/textures/landmarks/)

Cropped from Wikimedia Commons photos (credit to the photographers; CC BY-SA licences —
derived textures are shared under the same licence):
- civic_glass.jpg — "Civic Centre Towers, Victoria Island, Lagos.jpg" (CC BY-SA 4.0)
- eko_facade.jpg — "Eko Hotels 01.jpg" (CC BY-SA 4.0)
- toll_fascia.jpg — "Lekki Toll Gate Lagos.jpg" (CC BY-SA 4.0)
- makoko_wall.jpg, makoko_roof.jpg — "Makoko 3.jpg" (CC BY-SA 4.0)
- theatre_facade.jpg — "National Arts Theatre, Iganmu - Lagos.jpg" (CC BY-SA 4.0)

## Building heights

Google Open Buildings 2.5D Temporal (2023 epoch), CC BY 4.0 — measured building
heights applied to footprints by tools/lagos_map_pipeline/apply_google_25d_heights.py.

## Kenney Car Kit (assets/vehicles/kenney/) — CC0, https://kenney.nl/assets/car-kit
## Ground textures (ground_sand/dirt/grass.jpg) — ambientCG Ground080/054/068, CC0
## Kenney Nature Kit palms/bushes (assets/models/k_*.glb) — CC0, https://kenney.nl/assets/nature-kit
## Sky3D (addons/sky_3d/) — MIT, TokisanGames/Sky3D v2.1.0 (third-party textures: see addons/sky_3d/ThirdParty.md)
## Terrain3D (addons/terrain_3d/) — MIT, TokisanGames, v1.0.2 (Godot Asset Store)
## SimpleGrassTextured (addons/simplegrasstextured/) — MIT, IcterusGames, v2.1.0 (Godot Asset Store)
## Kenney Nature Kit trees (k_tree_*) — CC0
## AI-generated assets (fal.ai, generated for this project)
- assets/vehicles/danfo/danfo.glb — Tripo v2.5 text-to-3D (PBR), Lagos danfo.
- assets/vehicles/keke/keke.glb — Tripo v2.5 text-to-3D (PBR), Keke Napep.
- assets/models/lagos_house/house.glb — Tripo v2.5 text-to-3D (PBR), Lagos 2-storey house.
- assets/vehicles/okada, assets/vehicles/brt, assets/models/{plaza,kiosk,unfinished,billboard} — Tripo v2.5 text-to-3D (PBR) via fal.ai, generated for this project.
- assets/vehicles/{hilux,landcruiser}, assets/models/people/* — Tripo v2.5 text-to-3D (PBR) via fal.ai, generated for this project.
- assets/audio/sfx/*.ogg — CassetteAI sound-effects generator via fal.ai, generated for this project.
