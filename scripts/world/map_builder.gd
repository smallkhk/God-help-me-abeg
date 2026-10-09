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
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.11, 0.26, 0.30, 0.86)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.3
	mat.roughness = 0.15
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


func _road_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.29, 0.31)
	mat.roughness = 0.95
	return mat


func _quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	st.add_vertex(v0); st.add_vertex(v1); st.add_vertex(v2)
	st.add_vertex(v0); st.add_vertex(v2); st.add_vertex(v3)


func _own(n: Node) -> void:
	if Engine.is_editor_hint() and get_tree():
		n.owner = get_tree().edited_scene_root
