extends Node3D
## Drop-in slot for a Blender/OSM track (spec §8, §9.2). Point `track_scene` at an
## imported .glb (or .tscn) and `track_config_path` at a small JSON of spawn +
## checkpoints; this bakes drivable collision from the mesh and wires up the car,
## camera, HUD, pause menu and race. No code changes needed to add a new track.
##
## Config JSON format:
## {
##   "spawn": { "x": 0, "y": 1, "z": 0, "heading_rad": 0 },
##   "checkpoints": [ { "x":..,"y":..,"z":..,"heading_rad":.. }, ... ]
## }

@export var track_scene: PackedScene
@export_file("*.json") var track_config_path: String = ""
@export var bake_collision: bool = true

@export_group("Wiring (defaults provided)")
@export var player_scene: PackedScene
@export var hud_scene: PackedScene
@export var pause_scene: PackedScene
@export var checkpoint_scene: PackedScene
@export var race_event: RaceEvent

var _pause_menu: CanvasLayer
var _player: VehicleController


func _ready() -> void:
	if track_scene == null:
		push_warning("external_track: no track_scene set — nothing to load.")
		return

	var track := track_scene.instantiate()
	track.name = "Track"
	add_child(track)

	if bake_collision and track is Node3D:
		var body := CollisionBaker.bake(track, "TrackCollision")
		add_child(body)

	_ensure_lighting()

	var cfg := _load_config()
	var spawn := _spawn_transform(cfg)
	var checkpoints := _checkpoints(cfg)

	_player = _spawn_player(spawn)
	_spawn_camera()
	_spawn_hud()
	_spawn_pause()
	_spawn_race(spawn, checkpoints)


func _load_config() -> Dictionary:
	if track_config_path == "" or not FileAccess.file_exists(track_config_path):
		push_warning("external_track: no track_config — using origin spawn, no checkpoints.")
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(track_config_path))
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _spawn_transform(cfg: Dictionary) -> Transform3D:
	var s: Dictionary = cfg.get("spawn", {})
	var pos := Vector3(s.get("x", 0.0), s.get("y", 1.0), s.get("z", 0.0))
	return Transform3D(Basis(Vector3.UP, float(s.get("heading_rad", 0.0))), pos)


func _checkpoints(cfg: Dictionary) -> Array:
	var out: Array = []
	var raw: Array = cfg.get("checkpoints", [])
	for i in raw.size():
		var c: Dictionary = raw[i]
		out.append({
			"index": i, "x": c.get("x", 0.0), "y": c.get("y", 0.0),
			"z": c.get("z", 0.0), "heading_rad": c.get("heading_rad", 0.0),
		})
	return out


func _spawn_player(spawn: Transform3D) -> VehicleController:
	var p := player_scene.instantiate() as VehicleController
	p.name = "PlayerCar"
	p.is_player = true
	p.transform = spawn
	add_child(p)
	return p


func _spawn_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "ChaseCamera"
	cam.set_script(load("res://scripts/camera/chase_camera.gd"))
	cam.far = 4000.0
	add_child(cam)
	cam.target_path = NodePath("../PlayerCar")


func _spawn_hud() -> void:
	if hud_scene == null:
		return
	var hud := hud_scene.instantiate()
	hud.name = "HUD"
	add_child(hud)
	if hud.has_method("set_vehicle"):
		hud.set_vehicle(_player)


func _spawn_pause() -> void:
	if pause_scene == null:
		return
	_pause_menu = pause_scene.instantiate()
	_pause_menu.name = "PauseMenu"
	add_child(_pause_menu)


func _spawn_race(spawn: Transform3D, checkpoints: Array) -> void:
	var race := Node.new()
	race.name = "RaceManager"
	race.set_script(load("res://scripts/races/race_manager.gd"))
	race.player_path = NodePath("../PlayerCar")
	race.hud_path = NodePath("../HUD")
	race.checkpoint_scene = checkpoint_scene
	race.event = race_event
	add_child(race)
	race.configure_external(spawn, checkpoints)


func _ensure_lighting() -> void:
	# A basic sun + sky so an untextured track is still visible; a track that
	# ships its own lighting/environment can ignore this.
	if get_node_or_null("Sun") == null:
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(40), 0)
		sun.light_energy = 1.2
		sun.shadow_enabled = true
		add_child(sun)
	if get_node_or_null("WorldEnvironment") == null:
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		sky.sky_material = ProceduralSkyMaterial.new()
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		var we := WorldEnvironment.new()
		we.name = "WorldEnvironment"
		we.environment = env
		add_child(we)


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("pause") and _pause_menu and _pause_menu.has_method("toggle"):
		_pause_menu.toggle()
	elif ev.is_action_pressed("interact") and _player:
		_player.wetness = 0.0 if _player.wetness > 0.5 else 1.0
