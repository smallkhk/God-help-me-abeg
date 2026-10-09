extends Node
## Spawns ambient traffic on the bridge (spec §10). Reuses the player car scene
## but swaps the human input driver for a TrafficDriver, so traffic runs on the
## same VehicleController physics. Density is capped and configurable (spec §10
## "reduce density based on hardware performance").

@export var map_builder_path: NodePath
@export var car_scene: PackedScene
@export var count: int = 6
@export var spacing_samples: int = 70   # ~ count * spacing along the route
@export var lane_offsets: Array[float] = [4.1, 7.6]
@export var min_speed: float = 11.0
@export var max_speed: float = 18.0

const TrafficDriverScript := preload("res://scripts/vehicles/traffic_driver.gd")

var _route: Array = []


func _ready() -> void:
	var builder := get_node_or_null(map_builder_path) as MapBuilder
	if builder == null or car_scene == null:
		push_warning("traffic_manager: missing map builder or car scene.")
		return
	var chunk := builder.get_chunk()
	if chunk.is_empty():
		return
	_route = chunk["road"]["samples"]
	_spawn_all()


func _spawn_all() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20251009
	for i in count:
		var si := (i + 1) * spacing_samples
		if si >= _route.size() - 5:
			break
		var lane: float = lane_offsets[i % lane_offsets.size()]
		var speed := rng.randf_range(min_speed, max_speed)
		_spawn_one(si, lane, speed, rng)


func _spawn_one(sample_index: int, lane: float, speed: float, rng: RandomNumberGenerator) -> void:
	var car := car_scene.instantiate() as VehicleController
	car.is_player = false  # reuse of the player scene; make sure it's not treated as the player
	# Strip player-only children; attach the AI driver.
	for child_name in ["PlayerDriver", "VehicleDebug"]:
		var c := car.get_node_or_null(child_name)
		if c:
			c.free()

	var driver := TrafficDriverScript.new()
	driver.name = "TrafficDriver"
	driver.route = _route
	driver.lane_offset = lane
	driver.cruise_speed = speed
	driver.start_index = sample_index

	# Position on the road in-lane, facing along the route.
	var s = _route[sample_index]
	var h: float = s["heading_rad"]
	var perp := Vector3(cos(h), 0.0, -sin(h))
	var pos := Vector3(s["x"], float(s["elev_m"]) + 0.5, s["z"]) + perp * lane
	car.transform = Transform3D(Basis(Vector3.UP, h), pos)

	_recolor(car, rng)
	add_child(car)
	car.add_child(driver)


func _recolor(car: VehicleController, rng: RandomNumberGenerator) -> void:
	var palette := [
		Color(0.85, 0.85, 0.86), Color(0.1, 0.1, 0.12), Color(0.2, 0.35, 0.6),
		Color(0.7, 0.2, 0.2), Color(0.3, 0.5, 0.35), Color(0.75, 0.7, 0.2),
	]
	var col: Color = palette[rng.randi() % palette.size()]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.2
	mat.roughness = 0.45
	for n in ["Body", "Cabin"]:
		var m := car.get_node_or_null(n) as MeshInstance3D
		if m:
			m.material_override = mat
