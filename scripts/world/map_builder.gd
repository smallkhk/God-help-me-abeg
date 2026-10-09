@tool
class_name MapBuilder
extends Node3D
## Builds the Lagos bridge chunk geometry in-engine from the pipeline JSON
## (spec §8.2 steps 10-13, §8.3, §4.3). Road surface, raised barriers, bridge
## piers, lagoon water and a distant skyline are generated procedurally so the
## map regenerates from data and never needs hand-rebuilding (spec §21).
##
## Road topology (centerline), visuals (meshes) and collision (trimesh) are kept
## as separate concerns but built from one source of truth (spec §4.3).
## Runs in the editor (@tool) via the `build` checkbox, and at runtime in _ready.

@export_file("*.json") var chunk_path: String = "res://data/map/lagos_bridge/third_mainland_bridge.json"
## Tick in the editor to (re)generate. Also rebuilds automatically at runtime.
@export var build: bool = false:
	set(v):
		build = false
		_build()

var chunk: Dictionary = {}

const GEN_NAME := "Generated"


func _ready() -> void:
	# At RUNTIME always rebuild fresh, so the game never depends on whatever the
	# @tool may have baked into the scene in the editor (which can be stale, empty
	# or version-specific — a cause of "the bridge has no floor"). In the editor,
	# only build if nothing is there yet.
	if not Engine.is_editor_hint():
		_build()
	elif get_node_or_null(GEN_NAME) == null:
		_build()


func get_chunk() -> Dictionary:
	if chunk.is_empty():
		chunk = MapLoader.load_chunk(chunk_path)
	return chunk


func _build() -> void:
	var old := get_node_or_null(GEN_NAME)
	if old:
		old.free()

	chunk = MapLoader.load_chunk(chunk_path)
	if chunk.is_empty():
		return

	var root := Node3D.new()
	root.name = GEN_NAME
	add_child(root)
	if Engine.is_editor_hint() and get_tree():
		root.owner = get_tree().edited_scene_root

	_build_road(root)
	_build_markings(root)
	_build_streetlights(root)
	_build_piers(root)
	_build_water(root)
	_build_skyline(root)
	_build_land(root)
	_build_osm_buildings(root)
	_build_street_props(root)


func _frames() -> Array:
	# Per-sample (center, perpendicular, y) frames along the route.
	var samples: Array = chunk["road"]["samples"]
	var out: Array = []
	for s in samples:
		var h: float = s["heading_rad"]
		var center := Vector3(s["x"], s["elev_m"], s["z"])
		var perp := Vector3(cos(h), 0.0, -sin(h))  # right of travel
		out.append({"c": center, "p": perp, "bridge": s.get("on_bridge", true)})
	return out


func _build_road(root: Node3D) -> void:
	var hw: float = chunk["road"]["half_width_m"]
	var barrier_h: float = chunk["road"]["barrier_height_m"]
	var frames := _frames()

	var st := SurfaceTool.new()
	st.begin(Mesh.PrimitiveType.PRIMITIVE_TRIANGLES)
	# Collision triangle soup, built from the exact same triangles as the visual
	# mesh. We set it on a ConcavePolygonShape3D directly rather than via
	# mesh.create_trimesh_shape(), which proved unreliable for a runtime
	# SurfaceTool mesh (the baked shape failed to register with the physics
	# server). This keeps collision identical to the visible surface (spec §8.3).
	var soup := PackedVector3Array()

	for i in range(frames.size() - 1):
		var a = frames[i]
		var b = frames[i + 1]
		var al: Vector3 = a["c"] - a["p"] * hw
		var ar: Vector3 = a["c"] + a["p"] * hw
		var bl: Vector3 = b["c"] - b["p"] * hw
		var br: Vector3 = b["c"] + b["p"] * hw

		var up := Vector3.UP * barrier_h
		# Road surface quad (two tris, CCW so the normal faces up), then raised
		# barriers on each edge. Visual tris go to SurfaceTool; the same tris go
		# to the collision soup (soup must be appended here, not inside a helper —
		# PackedVector3Array passes by value in GDScript).
		for q in [
			[al, bl, br, ar],            # road surface
			[al, al + up, bl + up, bl],  # left barrier
			[ar, br, br + up, ar + up],  # right barrier
		]:
			_quad(st, q[0], q[1], q[2], q[3])
			soup.push_back(q[0]); soup.push_back(q[1]); soup.push_back(q[2])
			soup.push_back(q[0]); soup.push_back(q[2]); soup.push_back(q[3])

	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.name = "RoadMesh"
	mi.mesh = mesh
	mi.material_override = _road_material()
	root.add_child(mi)
	_own(mi)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(soup)
	# Hit the road from either side: without this, a downward wheel ray that
	# strikes the back of a face (winding-dependent) passes straight through and
	# the car falls through the deck.
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = "RoadCollision"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	_own(body)
	_own(cs)


func _build_markings(root: Node3D) -> void:
	# Lane lines derived from the chunk's lane layout (spec §5/§4.1 road furniture):
	# solid yellow either side of the median, dashed white lane dividers, solid
	# white outer edges. Flat quads laid just above the road, unshaded.
	var r: Dictionary = chunk["road"]
	var lanes: int = r["lanes_per_direction"]
	var lane_w: float = r["lane_width_m"]
	var median_half: float = r["median_width_m"] * 0.5
	var frames := _frames()
	var yellow := Color(0.92, 0.80, 0.12)
	var white := Color(0.90, 0.90, 0.90)

	# Build the list of marking lines as {offset, dashed, color}.
	var lines: Array = []
	lines.append({"o": -median_half, "dash": false, "col": yellow})
	lines.append({"o": median_half, "dash": false, "col": yellow})
	for side in [-1.0, 1.0]:
		for k in range(1, lanes):
			lines.append({"o": side * (median_half + k * lane_w), "dash": true, "col": white})
		lines.append({"o": side * (median_half + lanes * lane_w), "dash": false, "col": white})

	var st := SurfaceTool.new()
	st.begin(Mesh.PrimitiveType.PRIMITIVE_TRIANGLES)
	var lift := Vector3.UP * 0.03
	var hw_line := 0.09
	for i in range(frames.size() - 1):
		var a = frames[i]
		var b = frames[i + 1]
		for ln in lines:
			if ln["dash"] and (i % 6) >= 3:
				continue  # gap in the dash
			var o: float = ln["o"]
			var col: Color = ln["col"]
			var ai: Vector3 = a["c"] + a["p"] * (o - hw_line) + lift
			var ao: Vector3 = a["c"] + a["p"] * (o + hw_line) + lift
			var bi: Vector3 = b["c"] + b["p"] * (o - hw_line) + lift
			var bo: Vector3 = b["c"] + b["p"] * (o + hw_line) + lift
			st.set_color(col); st.add_vertex(ai)
			st.set_color(col); st.add_vertex(bi)
			st.set_color(col); st.add_vertex(bo)
			st.set_color(col); st.add_vertex(ai)
			st.set_color(col); st.add_vertex(bo)
			st.set_color(col); st.add_vertex(ao)

	var mi := MeshInstance3D.new()
	mi.name = "RoadMarkings"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/road_markings.gdshader")
	mi.material_override = mat
	root.add_child(mi)
	_own(mi)


func _build_streetlights(root: Node3D) -> void:
	# Light poles every ~45 m along both outer edges (spec §4.1). MultiMesh for
	# cheap instancing; the lamp head is a small emissive box atop each pole.
	var hw: float = chunk["road"]["half_width_m"]
	var frames := _frames()
	var pole_positions: Array = []
	var acc := 999.0  # force one at the start
	for i in range(frames.size()):
		if i > 0:
			acc += frames[i]["c"].distance_to(frames[i - 1]["c"])
		if acc < 45.0:
			continue
		acc = 0.0
		for side in [-1.0, 1.0]:
			pole_positions.append(frames[i]["c"] + frames[i]["p"] * (hw - 0.4))
	if pole_positions.is_empty():
		return

	var pole_h := 8.0
	var poles := MultiMesh.new()
	poles.transform_format = MultiMesh.TRANSFORM_3D
	var pbox := BoxMesh.new()
	pbox.size = Vector3(0.22, pole_h, 0.22)
	poles.mesh = pbox
	poles.instance_count = pole_positions.size()
	var heads := MultiMesh.new()
	heads.transform_format = MultiMesh.TRANSFORM_3D
	var hbox := BoxMesh.new()
	hbox.size = Vector3(0.9, 0.3, 0.5)
	heads.mesh = hbox
	heads.instance_count = pole_positions.size()
	for i in pole_positions.size():
		var p: Vector3 = pole_positions[i]
		poles.set_instance_transform(i, Transform3D(Basis(), p + Vector3(0, pole_h * 0.5, 0)))
		heads.set_instance_transform(i, Transform3D(Basis(), p + Vector3(0, pole_h + 0.15, 0)))

	var pole_mi := MultiMeshInstance3D.new()
	pole_mi.name = "StreetlightPoles"
	pole_mi.multimesh = poles
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.3, 0.3, 0.32)
	pmat.roughness = 0.7
	pole_mi.material_override = pmat
	root.add_child(pole_mi)
	_own(pole_mi)

	var head_mi := MultiMeshInstance3D.new()
	head_mi.name = "StreetlightHeads"
	head_mi.multimesh = heads
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(1.0, 0.85, 0.55)
	hmat.emission_enabled = true
	hmat.emission = Color(1.0, 0.8, 0.5)
	hmat.emission_energy_multiplier = 2.0
	head_mi.material_override = hmat
	root.add_child(head_mi)
	_own(head_mi)


func _build_piers(root: Node3D) -> void:
	var bridge: Dictionary = chunk["bridge"]
	var spacing: float = bridge["support_spacing_m"]
	var width: float = bridge["support_width_m"]
	var foot_y: float = bridge["pier_foot_y"]
	var deck_t: float = bridge["deck_thickness_m"]
	var frames := _frames()

	var body := StaticBody3D.new()
	body.name = "Piers"
	root.add_child(body)
	_own(body)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.70, 0.66)
	mat.roughness = 0.9

	var acc := 0.0
	var samples: Array = chunk["road"]["samples"]
	for i in range(frames.size()):
		if i > 0:
			acc += frames[i]["c"].distance_to(frames[i - 1]["c"])
		if not frames[i]["bridge"]:
			continue
		if acc < spacing and i != 0:
			continue
		acc = 0.0
		var c: Vector3 = frames[i]["c"]
		var top := c.y - deck_t
		var height := top - foot_y
		if height <= 1.0:
			continue
		var pier := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width, height, width)
		pier.mesh = bm
		pier.material_override = mat
		pier.position = Vector3(c.x, foot_y + height * 0.5, c.z)
		body.add_child(pier)
		_own(pier)
		# simple box collision for the pier
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = bm.size
		cs.shape = box
		cs.position = pier.position
		body.add_child(cs)
		_own(cs)


func _build_water(root: Node3D) -> void:
	var bounds: Dictionary = chunk["bounds_local_m"]
	var level: float = chunk["bridge"]["water_level_y"]
	var pad := 400.0
	var w: float = (bounds["max_x"] - bounds["min_x"]) + pad * 2.0
	var d: float = (bounds["max_z"] - bounds["min_z"]) + pad * 2.0
	var cx: float = (bounds["max_x"] + bounds["min_x"]) * 0.5
	var cz: float = (bounds["max_z"] + bounds["min_z"]) * 0.5

	var mi := MeshInstance3D.new()
	mi.name = "Lagoon"
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	mi.mesh = pm
	mi.position = Vector3(cx, level, cz)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mi.material_override = mat
	root.add_child(mi)
	_own(mi)


func _build_skyline(root: Node3D) -> void:
	var buildings: Array = chunk.get("buildings", [])
	if buildings.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	mm.mesh = bm
	mm.instance_count = buildings.size()
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		var h: float = b["h"]
		var t := Transform3D(
			Basis().scaled(Vector3(b["w"], h, b["d"])),
			Vector3(b["x"], b.get("y_base", 0.0) + h * 0.5, b["z"]))
		mm.set_instance_transform(i, t)
		var shade := 0.45 + float(i % 5) * 0.06
		mm.set_instance_color(i, Color(shade, shade * 0.98, shade * 0.95))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Skyline"
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mmi.material_override = mat
	root.add_child(mmi)
	_own(mmi)


## Ground under real-world built-up areas (from the chunk's land grid), so the
## OSM buildings stand on land instead of in the lagoon.
func _build_land(root: Node3D) -> void:
	var lc: Dictionary = chunk.get("land_cells", {})
	var cells: Array = lc.get("cells", [])
	if cells.is_empty():
		return
	var s: float = lc.get("cell_m", 50.0)
	var y := 0.25
	var st := SurfaceTool.new()
	st.begin(Mesh.PrimitiveType.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	st.set_color(Color(0.80, 0.70, 0.52))
	for c in cells:
		var x0: float = c[0] * s
		var z0: float = c[1] * s
		var a := Vector3(x0, y, z0); var b := Vector3(x0 + s, y, z0)
		var cc := Vector3(x0 + s, y, z0 + s); var d := Vector3(x0, y, z0 + s)
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(cc)
		st.add_vertex(a); st.add_vertex(cc); st.add_vertex(d)
	var mi := MeshInstance3D.new()
	mi.name = "Land"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	root.add_child(mi)
	_own(mi)


## Real Lagos buildings (Google Open Buildings footprints) dressed in a bright
## stylised Lagos look: painted walls with windows, clay-tile / zinc gable roofs or
## flat roofs with parapets + water tanks, and shop awnings near the road.
## Vertex alpha tells the shader the surface type:
##   0.0 wall with windows · 0.25 concrete roof · 0.5 zinc · 0.75 clay tile · 1.0 plain colour
const _WALLS := [
	Color(0.95, 0.89, 0.74), Color(0.97, 0.84, 0.52), Color(0.96, 0.74, 0.60),
	Color(0.66, 0.80, 0.90), Color(0.74, 0.88, 0.74), Color(0.96, 0.96, 0.93),
	Color(0.93, 0.76, 0.78), Color(0.88, 0.62, 0.46), Color(0.90, 0.90, 0.80),
]
const _AWNINGS := [
	Color(0.15, 0.55, 0.35), Color(0.20, 0.40, 0.75), Color(0.80, 0.22, 0.20),
	Color(0.95, 0.70, 0.15), Color(0.55, 0.25, 0.55),
]
const _TANKS := [Color(0.10, 0.11, 0.13), Color(0.18, 0.35, 0.70), Color(0.92, 0.92, 0.90)]


func _build_osm_buildings(root: Node3D) -> void:
	var blds: Array = chunk.get("osm_buildings", [])
	if blds.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PrimitiveType.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	var base := 0.25
	for i in blds.size():
		var b: Dictionary = blds[i]
		rng.seed = i * 7919 + 13
		var poly := PackedVector2Array()
		for p in b["pts"]:
			poly.append(Vector2(p[0], p[1]))
		if poly.size() < 3:
			continue
		var h: float = b["h"]
		var near: bool = float(b.get("d", 9999.0)) < 160.0
		var wc: Color = _WALLS[rng.randi() % _WALLS.size()]
		var top := base + h
		var ob := _obb(poly)
		var w := float(ob["v1"]) - float(ob["v0"])
		var l := float(ob["u1"]) - float(ob["u0"])
		var roof_roll := rng.randf()

		# walls (with windows)
		var run := 0.0
		for k in poly.size():
			var p0 := poly[k]; var p1 := poly[(k + 1) % poly.size()]
			var seg := p0.distance_to(p1)
			var sh := 0.86 + 0.14 * absf(sin(p0.angle_to_point(p1)))
			var col := Color(wc.r * sh, wc.g * sh, wc.b * sh, 0.0)
			_bq(st, Vector3(p0.x, base, p0.y), Vector3(p1.x, base, p1.y),
				Vector3(p1.x, top, p1.y), Vector3(p0.x, top, p0.y), col,
				Vector2(run, 0), Vector2(run + seg, 0), Vector2(run + seg, h), Vector2(run, h))
			run += seg

		var pitched := h < 11.0 and w < 22.0 and roof_roll < 0.72
		if pitched:
			var clay := roof_roll < 0.45
			_gable(st, ob, top, clay, wc)
		else:
			_flat_roof(st, poly, top, wc, rng)
			if l > 5.0 and w > 5.0:
				var tanks := 1 + rng.randi() % 2
				for t in tanks:
					var u := lerpf(float(ob["u0"]) + 1.5, float(ob["u1"]) - 1.5, rng.randf())
					var v := lerpf(float(ob["v0"]) + 1.5, float(ob["v1"]) - 1.5, rng.randf())
					var c2d: Vector2 = ob["c"] * u + ob["n"] * v
					_box(st, Vector3(c2d.x, top + 0.9, c2d.y), Vector3(1.3, 1.6, 1.3),
						_TANKS[rng.randi() % _TANKS.size()])

		if near and h < 16.0:
			_awning(st, poly, _AWNINGS[rng.randi() % _AWNINGS.size()], base)

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "LagosBuildings"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/building.gdshader")
	mat.set_shader_parameter("tex_plaster", load("res://assets/textures/wall_plaster.jpg"))
	mat.set_shader_parameter("tex_concrete", load("res://assets/textures/concrete.jpg"))
	mat.set_shader_parameter("tex_zinc", load("res://assets/textures/roof_zinc.jpg"))
	mat.set_shader_parameter("tex_clay", load("res://assets/textures/roof_clay.jpg"))
	for nm in [["tex_plaster_n", "wall_plaster_n"], ["tex_concrete_n", "concrete_n"], ["tex_zinc_n", "roof_zinc_n"], ["tex_clay_n", "roof_clay_n"]]:
		mat.set_shader_parameter(nm[0], load("res://assets/textures/%s.jpg" % nm[1]))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	_own(mi)


func _obb(poly: PackedVector2Array) -> Dictionary:
	var best := 0.0
	var ang := 0.0
	for k in poly.size():
		var e := poly[(k + 1) % poly.size()] - poly[k]
		if e.length() > best:
			best = e.length(); ang = e.angle()
	var c := Vector2(cos(ang), sin(ang))
	var n := Vector2(-c.y, c.x)
	var u0 := INF; var u1 := -INF; var v0 := INF; var v1 := -INF
	for p in poly:
		u0 = minf(u0, p.dot(c)); u1 = maxf(u1, p.dot(c))
		v0 = minf(v0, p.dot(n)); v1 = maxf(v1, p.dot(n))
	return {"c": c, "n": n, "u0": u0, "u1": u1, "v0": v0, "v1": v1}


func _gable(st: SurfaceTool, ob: Dictionary, top: float, clay: bool, wc: Color) -> void:
	var c: Vector2 = ob["c"]; var n: Vector2 = ob["n"]
	var pad := 0.45
	var u0 := float(ob["u0"]) - pad; var u1 := float(ob["u1"]) + pad
	var v0 := float(ob["v0"]) - pad; var v1 := float(ob["v1"]) + pad
	var vm := (v0 + v1) * 0.5
	var rh := minf((v1 - v0) * (0.38 if clay else 0.2), 3.5)
	var P := func(u: float, v: float, y: float) -> Vector3:
		var q: Vector2 = c * u + n * v
		return Vector3(q.x, y, q.y)
	var a: Vector3 = P.call(u0, v0, top); var b: Vector3 = P.call(u1, v0, top)
	var cc: Vector3 = P.call(u1, v1, top); var d: Vector3 = P.call(u0, v1, top)
	var r0: Vector3 = P.call(u0, vm, top + rh); var r1: Vector3 = P.call(u1, vm, top + rh)
	var kind := 0.75 if clay else 0.5
	var rc := Color(0.78, 0.38, 0.24, kind) if clay else Color(0.62, 0.64, 0.66, kind)
	var sl := sqrt(pow((v1 - v0) * 0.5, 2) + rh * rh)
	_bq(st, a, b, r1, r0, rc, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, sl), Vector2(u0, sl))
	_bq(st, cc, d, r0, r1, rc, Vector2(u1, 0), Vector2(u0, 0), Vector2(u0, sl), Vector2(u1, sl))
	var gc := Color(wc.r * 0.92, wc.g * 0.92, wc.b * 0.92, 1.0)
	_btri(st, a, r0, d, gc)
	_btri(st, b, cc, r1, gc)


func _flat_roof(st: SurfaceTool, poly: PackedVector2Array, top: float, wc: Color, rng: RandomNumberGenerator) -> void:
	var zinc := rng.randf() < 0.25
	var rc := Color(0.62, 0.64, 0.66, 0.5) if zinc else Color(0.6, 0.58, 0.55, 0.25)
	for t in Geometry2D.triangulate_polygon(poly):
		var q := poly[t]
		st.set_color(rc); st.set_uv(q)
		st.add_vertex(Vector3(q.x, top, q.y))
	# parapet
	var pc := Color(wc.r * 0.9, wc.g * 0.9, wc.b * 0.9, 1.0)
	for k in poly.size():
		var p0 := poly[k]; var p1 := poly[(k + 1) % poly.size()]
		_bq(st, Vector3(p0.x, top, p0.y), Vector3(p1.x, top, p1.y),
			Vector3(p1.x, top + 0.9, p1.y), Vector3(p0.x, top + 0.9, p0.y), pc,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


func _awning(st: SurfaceTool, poly: PackedVector2Array, col: Color, base: float) -> void:
	var best := 0.0; var k0 := 0
	for k in poly.size():
		var e := poly[k].distance_to(poly[(k + 1) % poly.size()])
		if e > best:
			best = e; k0 = k
	if best < 4.0:
		return
	var p0 := poly[k0]; var p1 := poly[(k0 + 1) % poly.size()]
	var cen := Vector2.ZERO
	for p in poly: cen += p
	cen /= poly.size()
	var dir := (p1 - p0).normalized()
	var out := Vector2(-dir.y, dir.x)
	if out.dot((p0 + p1) * 0.5 - cen) < 0.0:
		out = -out
	var i0 := p0 + dir * 0.4; var i1 := p1 - dir * 0.4
	var o0 := i0 + out * 1.8; var o1 := i1 + out * 1.8
	var y0 := base + 3.3; var y1 := base + 2.8
	var c := Color(col.r, col.g, col.b, 1.0)
	_bq(st, Vector3(i0.x, y0, i0.y), Vector3(i1.x, y0, i1.y),
		Vector3(o1.x, y1, o1.y), Vector3(o0.x, y1, o0.y), c,
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var col1 := Color(col.r, col.g, col.b, 1.0)
	var h := s * 0.5
	var v := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
		c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	var z := Vector2.ZERO
	for f in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]:
		_bq(st, v[f[0]], v[f[1]], v[f[2]], v[f[3]], col1, z, z, z, z)


func _bq(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	st.set_color(col)
	st.set_uv(ua); st.add_vertex(a); st.set_uv(ub); st.add_vertex(b); st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ua); st.add_vertex(a); st.set_uv(uc); st.add_vertex(c); st.set_uv(ud); st.add_vertex(d)


func _btri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	for p in [a, b, c]:
		st.set_uv(Vector2.ZERO); st.add_vertex(p)


## Street life along the route: utility poles + wires, palm trees, telecom masts,
## bus shelters, billboards (fictional brands), traffic cones, and a solid centre
## median barrier (with collision). Scenery is merged into one vertex-coloured mesh.
const _BRANDS := ["ZOBO COLA", "EKO BANK", "GIDI TELECOM", "SUYA KING", "LAGOS FM 97.3",
	"OGA DATA 5G", "MAMA PUT FOODS", "JOLLOF EXPRESS", "NAIJA PAINTS", "KEKE INSURANCE"]


func _build_street_props(root: Node3D) -> void:
	var frames := _frames()
	if frames.size() < 2:
		return
	var hw: float = chunk["road"]["half_width_m"]
	var land := {}
	var lc: Dictionary = chunk.get("land_cells", {})
	var cs: float = lc.get("cell_m", 50.0)
	for c in lc.get("cells", []):
		land[Vector2i(int(c[0]), int(c[1]))] = true
	var is_land := func(p: Vector3) -> bool:
		return land.has(Vector2i(int(floor(p.x / cs)), int(floor(p.z / cs))))

	var st := SurfaceTool.new()
	st.begin(Mesh.PrimitiveType.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var dist := 0.0
	var next_pole := 0.0; var next_palm := 0.0; var next_mast := 400.0
	var next_board := 150.0; var next_stop := 120.0; var next_cones := 300.0
	var last_pole := {-1.0: null, 1.0: null}
	var boards: Array = []
	# real CC0 3D models (Poly Haven), instanced: model name -> Array[Transform3D]
	var inst := {}
	var put := func(model: String, pos: Vector3, yaw: float, sc: float) -> void:
		if not inst.has(model):
			inst[model] = []
		inst[model].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), pos))
	var next_junk := 20.0

	for i in frames.size():
		if i > 0:
			dist += frames[i]["c"].distance_to(frames[i - 1]["c"])
		var c: Vector3 = frames[i]["c"]
		var p: Vector3 = frames[i]["p"]
		var fwd := Vector3(-p.z, 0, p.x)
		var on_bridge: bool = frames[i]["bridge"]

		# utility poles + wires (land approaches)
		if not on_bridge and dist >= next_pole:
			next_pole = dist + 32.0
			for side in [-1.0, 1.0]:
				var base: Vector3 = c + p * side * (hw + 2.5)
				base.y = 0.25 if is_land.call(base) else c.y
				var top: Vector3 = base + Vector3(0, 9.0, 0)
				_obox(st, base + Vector3(0, 4.5, 0), Vector3(0.28, 9.0, 0.28), Basis(), Color(0.36, 0.26, 0.18))
				_obox(st, top + Vector3(0, -0.6, 0), Vector3(1.8, 0.12, 0.12), Basis(Vector3.UP, atan2(p.x, p.z)), Color(0.3, 0.22, 0.15))
				var prev = last_pole[side]
				if prev != null:
					for off in [-0.7, 0.0, 0.7]:
						var a: Vector3 = prev + p * off + Vector3(0, -0.6, 0)
						var b2: Vector3 = top + p * off + Vector3(0, -0.6, 0)
						_wire(st, a, b2)
				last_pole[side] = top
		elif on_bridge:
			last_pole = {-1.0: null, 1.0: null}

		# palm trees on land near the road
		if dist >= next_palm:
			next_palm = dist + 20.0
			for side in [-1.0, 1.0]:
				if rng.randf() < 0.45:
					var pos: Vector3 = c + p * side * (hw + rng.randf_range(10.0, 220.0)) + fwd * rng.randf_range(-6.0, 6.0)
					if is_land.call(pos):
						pos.y = 0.25
						put.call(["island_tree_01", "island_tree_02", "island_tree_03"][rng.randi() % 3], pos, rng.randf() * TAU, rng.randf_range(0.8, 1.2))
						if rng.randf() < 0.5:
							var sp: Vector3 = pos + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
							put.call("shrub_01" if rng.randf() < 0.5 else "shrub_02", sp, rng.randf() * TAU, rng.randf_range(0.8, 1.5))

		# telecom masts (red/white), visible from far
		if dist >= next_mast:
			next_mast = dist + rng.randf_range(700.0, 1100.0)
			var side: float = -1.0 if rng.randf() < 0.5 else 1.0
			var pos: Vector3 = c + p * side * rng.randf_range(120.0, 450.0)
			if is_land.call(pos):
				pos.y = 0.25
				_mast(st, pos)

		# billboards
		if dist >= next_board:
			next_board = dist + rng.randf_range(350.0, 650.0)
			var side: float = -1.0 if rng.randf() < 0.5 else 1.0
			var pos: Vector3 = c + p * side * (hw + rng.randf_range(14.0, 30.0))
			if is_land.call(pos):
				pos.y = 0.25
				boards.append([pos, atan2(p.x, p.z) + (PI * 0.5 if side < 0 else -PI * 0.5)])

		# bus shelters on the approaches
		if not on_bridge and dist >= next_stop:
			next_stop = dist + 280.0
			var side: float = -1.0 if rng.randf() < 0.5 else 1.0
			var pos: Vector3 = c + p * side * (hw + 4.0)
			pos.y = 0.25 if is_land.call(pos) else c.y
			_bus_stop(st, pos, Basis(Vector3.UP, atan2(p.x, p.z)))

		# roadside Lagos clutter: chairs, gens, crates, tyres, jerrycans, bins, AC units
		if not on_bridge and dist >= next_junk:
			next_junk = dist + rng.randf_range(12.0, 30.0)
			var side: float = -1.0 if rng.randf() < 0.5 else 1.0
			var base: Vector3 = c + p * side * (hw + rng.randf_range(3.0, 9.0)) + fwd * rng.randf_range(-4.0, 4.0)
			if is_land.call(base):
				base.y = 0.25
				var junk := ["plastic_monobloc_chair_01", "portable_generator", "plastic_crate_01",
					"old_tyre", "metal_jerrycan", "metal_trash_can", "propane_tank", "wooden_crate_01",
					"utility_box_01", "exterior_aircon_unit", "utility_box_02", "fire_hydrant",
					"security_light", "covered_car"]
				for k in rng.randi_range(1, 4):
					var jp: Vector3 = base + Vector3(rng.randf_range(-2.0, 2.0), 0, rng.randf_range(-2.0, 2.0))
					put.call(junk[rng.randi() % junk.size()], jp, rng.randf() * TAU, 1.0)

		# boats on the lagoon beside the bridge
		if on_bridge and rng.randf() < 0.012:
			var side: float = -1.0 if rng.randf() < 0.5 else 1.0
			var bp: Vector3 = c + p * side * rng.randf_range(60.0, 400.0)
			if not is_land.call(bp):
				bp.y = 0.0
				put.call("dutch_ship_medium", bp, rng.randf() * TAU, 0.6)

		# real street lamps + concrete barriers on land roads
		if not on_bridge and i % 7 == 0:
			for side in [-1.0, 1.0]:
				var lp: Vector3 = c + p * side * (hw + 1.2)
				if is_land.call(lp):
					lp.y = 0.25
					put.call("street_lamp_02", lp, atan2(p.x, p.z) + (PI if side > 0 else 0.0), 1.0)
		if not on_bridge and rng.randf() < 0.01:
			var bp2: Vector3 = c + p * (hw - 0.8) * (-1.0 if rng.randf() < 0.5 else 1.0)
			put.call("concrete_road_barrier_02", bp2, atan2(fwd.x, fwd.z), 1.0)

		# traffic cones on the shoulder
		if dist >= next_cones:
			next_cones = dist + rng.randf_range(350.0, 700.0)
			var side: float = -1.0 if rng.randf() < 0.5 else 1.0
			for k in 4:
				var pos: Vector3 = c + p * side * (hw - 0.6) + fwd * (k * 2.5)
				_cone(st, pos)

	var mi := MeshInstance3D.new()
	mi.name = "StreetProps"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	root.add_child(mi)
	_own(mi)

	_spawn_model_instances(root, inst)

	for bd in boards:
		_billboard(root, bd[0], bd[1], _BRANDS[rng.randi() % _BRANDS.size()], rng)

	_build_median(root, frames)


## One MultiMesh per mesh part of each glb model (cheap to draw thousands).
func _spawn_model_instances(root: Node3D, inst: Dictionary) -> void:
	for model in inst:
		var path := "res://assets/models/%s.glb" % model
		if not ResourceLoader.exists(path):
			continue
		var scene := (load(path) as PackedScene).instantiate()
		var xforms: Array = inst[model]
		var far := 600.0 if model.begins_with("island_tree") else 180.0
		for m in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh_i := m as MeshInstance3D
			var local := _local_to(scene, mesh_i)
			# split into 300 m cells so off-screen / far groups are culled
			var cells := {}
			for xf in xforms:
				var key := Vector2i(int(floor(xf.origin.x / 300.0)), int(floor(xf.origin.z / 300.0)))
				if not cells.has(key):
					cells[key] = []
				cells[key].append(xf)
			for key in cells:
				var list: Array = cells[key]
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = mesh_i.mesh
				mm.instance_count = list.size()
				for k in list.size():
					mm.set_instance_transform(k, list[k] * local)
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "%s_%s_%d_%d" % [model, mesh_i.name, key.x, key.y]
				mmi.multimesh = mm
				mmi.visibility_range_end = far + 300.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if far > 200.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(mmi)
				_own(mmi)
		scene.free()


func _local_to(top: Node, n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != top:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	if top is Node3D:
		t = (top as Node3D).transform * t
	return t


func _build_median(root: Node3D, frames: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PrimitiveType.PRIMITIVE_TRIANGLES)
	var soup := PackedVector3Array()
	var hwm := 0.35
	var mh := 0.85
	for i in range(frames.size() - 1):
		var a = frames[i]; var b = frames[i + 1]
		var al: Vector3 = a["c"] - a["p"] * hwm; var ar: Vector3 = a["c"] + a["p"] * hwm
		var bl: Vector3 = b["c"] - b["p"] * hwm; var br: Vector3 = b["c"] + b["p"] * hwm
		var up := Vector3.UP * mh
		for q in [[al, bl, bl + up, al + up], [ar, ar + up, br + up, br], [al + up, bl + up, br + up, ar + up]]:
			_quad(st, q[0], q[1], q[2], q[3])
			soup.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Median"
	mi.mesh = st.commit()
	mi.material_override = _road_material()
	root.add_child(mi)
	_own(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(soup)
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = "MedianCollision"
	var csh := CollisionShape3D.new()
	csh.shape = shape
	body.add_child(csh)
	root.add_child(body)
	_own(body); _own(csh)


func _palm(st: SurfaceTool, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(6.0, 11.0)
	var lean := Basis(Vector3(1, 0, 0), rng.randf_range(-0.12, 0.12))
	var trunk_c := Color(0.48, 0.38, 0.26)
	_obox(st, pos + lean * Vector3(0, h * 0.5, 0), Vector3(0.35, h, 0.35), lean, trunk_c)
	var top := pos + lean * Vector3(0, h, 0)
	var green := Color(0.22, 0.55, 0.22).lerp(Color(0.40, 0.62, 0.20), rng.randf())
	for k in 7:
		var yaw := TAU * k / 7.0 + rng.randf() * 0.3
		var bas := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), 0.55)
		_obox(st, top + bas * Vector3(0, 0, 1.6), Vector3(0.9, 0.08, 3.4), bas, green)


func _mast(st: SurfaceTool, pos: Vector3) -> void:
	var segs := 10
	var seg_h := 4.5
	for k in segs:
		var w := lerpf(2.4, 0.8, float(k) / segs)
		var col := Color(0.85, 0.15, 0.12) if k % 2 == 0 else Color(0.95, 0.95, 0.95)
		_obox(st, pos + Vector3(0, seg_h * (k + 0.5), 0), Vector3(w, seg_h, w), Basis(), col)
	for k in 3:
		_obox(st, pos + Vector3(0, seg_h * segs - 3.0 - k * 4.0, 0.7), Vector3(0.5, 1.6, 0.3), Basis(), Color(0.9, 0.9, 0.9))


func _bus_stop(st: SurfaceTool, pos: Vector3, bas: Basis) -> void:
	var post := Color(0.2, 0.2, 0.22)
	for dx in [-2.0, 2.0]:
		_obox(st, pos + bas * Vector3(dx, 1.3, 0), Vector3(0.12, 2.6, 0.12), bas, post)
	_obox(st, pos + bas * Vector3(0, 2.65, 0), Vector3(4.8, 0.12, 1.8), bas, Color(0.15, 0.35, 0.75))
	_obox(st, pos + bas * Vector3(0, 0.5, 0.5), Vector3(3.6, 0.1, 0.5), bas, Color(0.75, 0.75, 0.75))
	_obox(st, pos + bas * Vector3(2.6, 2.0, 0), Vector3(0.1, 1.2, 0.8), bas, Color(0.95, 0.75, 0.10))


func _cone(st: SurfaceTool, pos: Vector3) -> void:
	_obox(st, pos + Vector3(0, 0.05, 0), Vector3(0.5, 0.1, 0.5), Basis(), Color(0.15, 0.15, 0.15))
	_obox(st, pos + Vector3(0, 0.35, 0), Vector3(0.32, 0.5, 0.32), Basis(), Color(1.0, 0.45, 0.05))
	_obox(st, pos + Vector3(0, 0.38, 0), Vector3(0.34, 0.1, 0.34), Basis(), Color(0.95, 0.95, 0.95))


func _wire(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var mid := (a + b) * 0.5 + Vector3(0, -0.5, 0)  # sag
	for pair in [[a, mid], [mid, b]]:
		var d: Vector3 = pair[1] - pair[0]
		var l := d.length()
		if l < 0.01:
			continue
		var z := d / l
		var x := Vector3.UP.cross(z).normalized()
		if x.length() < 0.5:
			x = Vector3.RIGHT
		var y := z.cross(x)
		_obox(st, (pair[0] + pair[1]) * 0.5, Vector3(0.04, 0.04, l), Basis(x, y, z), Color(0.08, 0.08, 0.08))


func _billboard(root: Node3D, pos: Vector3, yaw: float, brand: String, rng: RandomNumberGenerator) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	root.add_child(n)
	_own(n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PrimitiveType.PRIMITIVE_TRIANGLES)
	var cols := [Color(0.85, 0.12, 0.12), Color(0.10, 0.45, 0.20), Color(0.95, 0.70, 0.05),
		Color(0.10, 0.25, 0.65), Color(0.55, 0.15, 0.55)]
	var bg: Color = cols[rng.randi() % cols.size()]
	for dx in [-3.0, 3.0]:
		_obox(st, Vector3(dx, 4.0, 0), Vector3(0.3, 8.0, 0.3), Basis(), Color(0.3, 0.3, 0.32))
	_obox(st, Vector3(0, 9.5, 0), Vector3(10.0, 4.0, 0.3), Basis(), bg)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	n.add_child(mi)
	_own(mi)
	for face in [1.0, -1.0]:
		var lbl := Label3D.new()
		lbl.text = brand
		lbl.font_size = 96
		lbl.pixel_size = 0.012
		lbl.modulate = Color(1, 1, 1)
		lbl.outline_size = 0
		lbl.position = Vector3(0, 9.5, 0.17 * face)
		if face < 0:
			lbl.rotation.y = PI
		n.add_child(lbl)
		_own(lbl)


## Oriented box (vertex colours, alpha 1) for props.
func _obox(st: SurfaceTool, c: Vector3, s: Vector3, bas: Basis, col: Color) -> void:
	var h := s * 0.5
	var corners := []
	for v in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1),
			Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		corners.append(c + bas * (v * h))
	var z := Vector2.ZERO
	for f in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7], [3, 2, 1, 0]]:
		_bq(st, corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]], Color(col.r, col.g, col.b, 1.0), z, z, z, z)


func _road_material() -> Material:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/road.gdshader")
	sm.set_shader_parameter("tex_asphalt", load("res://assets/textures/asphalt.jpg"))
	sm.set_shader_parameter("tex_concrete", load("res://assets/textures/concrete.jpg"))
	sm.set_shader_parameter("tex_asphalt_n", load("res://assets/textures/asphalt_n.jpg"))
	sm.set_shader_parameter("tex_asphalt_r", load("res://assets/textures/asphalt_r.jpg"))
	sm.set_shader_parameter("tex_concrete_n", load("res://assets/textures/concrete_n.jpg"))
	return sm


func _road_material_flat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.29, 0.31)
	mat.roughness = 0.95
	# Double-sided: the generated road triangles can wind either way, so cull
	# nothing or the deck is invisible from above (you'd see through to the water
	# and the car looks like it's floating).
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	st.add_vertex(v0); st.add_vertex(v1); st.add_vertex(v2)
	st.add_vertex(v0); st.add_vertex(v2); st.add_vertex(v3)


func _own(n: Node) -> void:
	if Engine.is_editor_hint() and get_tree():
		n.owner = get_tree().edited_scene_root
