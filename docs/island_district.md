# Lagos Island street circuit (compact district)

The Lagos Island map was reworked from a 2.6 × 1.6 km slab of land with a
rounded-rectangle loop through a grid of 5,204 blocks into a compact street
circuit built around the road. The other maps (Third Mainland Bridge, Lekki,
Hills, Bush Trail, Mountain Valley) are unchanged: everything new is switched on
by `"district": true` / `"loop": true` in the chunk JSON.

Regenerate the map data (and its menu preview + map-screen route):

```bash
python3 tools/lagos_map_pipeline/generate_island_district.py
```

## 1. Audit (before)

| Area | Finding |
|---|---|
| Generation | Procedural Python generator → chunk JSON → `MapBuilder` (GDScript) builds road, land, buildings, props, traffic at load. |
| Route | 5.5 km rounded rectangle: two 1.8 km straights, four similar corners. |
| Land | 50 m land cells for the whole 2.6 × 1.6 km island **plus** a 300 m band each side of the road. |
| Buildings | Footprints on a block grid; within 150 m of the road they became instanced Tripo models, a second row of house models was placed at hw + 9.6 m, churches/petrol stations/banks up to 40 m out. **No collision on any building**. |
| Race | Ordered checkpoint gates (skipping is impossible) but `event.laps` was ignored and races were cut to the first 2.5 km. Rival AI could not wrap round a loop and used fixed 2.4/5.9/9.4 m lane offsets (9.4 m is past the kerb of a 9 m road). |
| Performance | ~2.1–2.5 M primitives and 226–298 draw calls per frame; 2,186 MultiMesh nodes (small multi-part props: a fire hydrant is 6 meshes, a bin 5, one draw call per part per 80 m cell). Building models drawn to ~530 m with shadows. Road, ground and lagoon cast shadows. |
| Physics | Ambient traffic is moved kinematically and never braked, so it could drive into the player and push the car through the road. A fall reset the car to the start grid. |

## 2. What changed

**Route** — a 2.93 km closed centripetal Catmull-Rom spline sampled every 3 m:
start/finish straight (Broad Street), a 90° right (R 49 m), sweepers, a 450 m
Marina acceleration straight on the lagoon, a hairpin (R 42 m), a chicane, and a
run of linked bends back to the line — 13 distinct corners. Width 16 m kerb to
kerb (2 lanes each way + median), flat at 2 m. Road mesh, markings and
collision are generated from the same samples, so there are no gaps or kinks.

**Footprint** — ground only where the district is: 5 m cells within 39 m of the
road (0.22 km² instead of the whole island + 300 m bands), a no-collision
background ground band behind it, the lagoon beyond. Along the Marina the ground
stops at the promenade railing so the water is right there.

**Frontage** — both sides are walked along a line 4 m behind the kerb (pavement
width) and filled lot by lot with no gaps: real Lagos house, shop-row and
uncompleted-building models scaled *uniformly* from their true size (so doors and
windows keep their scale), procedural 2–5 storey mixed-use blocks with shop
shutters, awnings and signboards, and walled compounds with steel gates and a
house set back in the yard. Setbacks vary 0–1.4 m. Lots are checked against the
whole road (≥ 11.2 m from the centre line everywhere) and against each other
(0.5 m occupancy raster), so nothing overlaps the road or another building;
where a lot can't fit on the inside of a bend a compound wall closes the gap.
Corners use solid blocks so the row continues round the bend. Thirteen short
side streets have walls down both sides and a building across the end, so no
view opens onto empty land. Concrete-slab pavements, zebra crossings with stop
lines, a chequered start/finish line and a START · FINISH gantry.

**Collision** — one static trimesh of low wall quads for all buildings and
walls (not per-building bodies), the road + kerbs, pavements and ground.
Decorative props have no collision.

**Race** — chunk `"loop": true` makes a lap race: every gate is used, the last
gate is the start/finish line, `event.laps` laps (2 for the Island event), lap
banner, `LAP x/2` + current lap time + best lap on screen and in the results.
Gates must be taken in order. Positions count laps for the player and rivals.
Rivals wrap round the loop, use the road's real lanes, change lane / brake for
street traffic, and reset onto the racing line if they are wedged for 4 s.
A car that drops below the road is put back on the road where it was (any map),
not at the start grid.

**Traffic** — street traffic brakes for any car or traffic ahead in its lane and,
if jammed for 5 s, is moved off-screen.

**Materials** — new compound-wall (rendered sandcrete blocks, 45 × 22.5 cm
courses, worn patches, grime) and painted-steel gate surfaces in
`building.gdshader`, new `pavement.gdshader` (60 cm concrete slabs). All
textures are the existing 1–2K PBR set with mipmaps and VRAM compression; UVs on
walls, pavements and road are in metres, so nothing stretches round curves.

## 3. Performance (same bench, same viewpoints)

Measured with `xvfb` + software rendering at 640×360 (frame times are only
comparable to each other, not to a real GPU; draw calls / primitives are what a
GPU would actually process). Stationary at the grid, then teleporting the car
round the whole lap.

| Metric | Before | After | Change |
|---|---|---|---|
| Primitives / frame (stationary · driving) | 2,482k · 2,109k | 1,063k · 1,138k | −57 % · −46 % |
| Draw calls (stationary · driving) | 298 · 226 | 191 · 215 | −36 % · −5 % |
| Frame time avg (stationary · driving) | 1,439 · 1,426 ms | 859 · 936 ms | −40 % · −34 % |
| Frame time p95 driving | 3,776 ms | 1,385 ms | −63 % |
| Generated nodes | 2,308 | 886 | −62 % |
| MultiMesh nodes | 2,186 | 645 | −70 % |
| Video / texture memory | 675 / 604 MB | 586 / 527 MB | −13 % |
| Physics time | 2.3–3.0 ms | 2.6–2.7 ms | ≈ |
| Load time | 8.0 s | 7.0 s | −12 % |

Main savings: house models drawn only within 140 m with cheap procedural
stand-ins beyond (houses went from ~1.03 M to ~0.29 M primitives), buildings
merged per 120 m cell with a 480 m draw distance, single-mesh clutter props
only, and no shadows from flat road / ground / water.

## 4. Testing

`tests/map_validation/island_circuit_test.tscn` (headless): ray-casts the road
under every sample (centre + both lane edges), checks nothing static lies across
the road at car height, then lets an AI driver race the full 2-lap event and
fails on a fall, a stuck car or an unfinished race.

## 5. Limitations

- The circuit is flat; elevation changes would need ground that follows the road.
- Side streets are visual only (the kerb runs across them).
- Occlusion culling is not used (draw distance + cell culling instead).
- Frame-time numbers come from a software renderer; real-device numbers on the
  HP x360 / iPhone 13 Pro still need checking in play.
