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

@export_file("*.json") var chunk_path: String = "res://data/map/lagos_bridge/tmb_south_prototype.json"
## Tick in the editor to (re)generate. Also rebuilds automatically at runtime.
@export var build: bool = false:
	set(v):
		build = false
		_build()

var chunk: Dictionary = {}

const GEN_NAME := "Generated"


func _ready() -> void:
	if get_node_or_null(GEN_NAME) == null:
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

	for i in range(frames.size() - 1):
		var a = frames[i]
		var b = frames[i + 1]
		var al: Vector3 = a["c"] - a["p"] * hw
		var ar: Vector3 = a["c"] + a["p"] * hw
		var bl: Vector3 = b["c"] - b["p"] * hw
		var br: Vector3 = b["c"] + b["p"] * hw

		# Road surface quad (two tris), wound CCW so the normal faces up.
		_quad(st, al, bl, br, ar)

		# Raised barriers on each edge (inner faces drivers can hit).
		var up := Vector3.UP * barrier_h
		# left barrier
		_quad(st, al, al + up, bl + up, bl)
		# right barrier
		_quad(st, ar, br, br + up, ar + up)

	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.name = "RoadMesh"
	mi.mesh = mesh
	mi.material_override = _road_material()
	root.add_child(mi)
	_own(mi)

	var body := StaticBody3D.new()
	body.name = "RoadCollision"
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	root.add_child(body)
	_own(body)
	_own(cs)


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
