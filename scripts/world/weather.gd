extends Node3D
class_name Weather
## Lagos rain: streaks around the camera, wet/puddled roads (global `wetness`),
## rain + thunder sound and lightning flashes. Press Y to toggle; races with
## weather = "rain" start wet.

var raining := false
var _wet := 0.0
var _particles: GPUParticles3D
var _rain_snd: AudioStreamPlayer
var _thunder: AudioStreamPlayer
var _flash_t := 0.0
var _next_bolt := 12.0
var _env: Environment
var _base_amb := 0.4
var _base_fog := 0.0005


func _ready() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = 2500 if _hi_gfx() else 900
	_particles.lifetime = 1.2
	_particles.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 1, 30)
	pm.direction = Vector3(0.08, -1, 0.02)
	pm.spread = 3.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 28.0
	pm.gravity = Vector3(0, -9.8, 0)
	_particles.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.7)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.78, 0.82, 0.88, 0.35)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = mat
	_particles.draw_pass_1 = q
	_particles.emitting = false
	add_child(_particles)
	_rain_snd = AudioStreamPlayer.new()
	var rs: AudioStream = load("res://assets/audio/sfx/rain.ogg")
	if rs is AudioStreamOggVorbis:
		rs.loop = true
	_rain_snd.stream = rs
	_rain_snd.volume_db = -60.0
	add_child(_rain_snd)
	_thunder = AudioStreamPlayer.new()
	_thunder.stream = load("res://assets/audio/sfx/thunder.ogg")
	add_child(_thunder)
	await get_tree().process_frame
	var we := _scene_root().find_children("*", "WorldEnvironment", true, false)
	if not we.is_empty():
		_env = (we[0] as WorldEnvironment).environment
	for rm in _scene_root().find_children("*", "Node", true, false):
		var ev = rm.get("event")
		if ev is RaceEvent and ev.weather == "rain":
			set_rain(true)
			break


func set_rain(on: bool) -> void:
	raining = on
	_particles.emitting = on
	if on and not _rain_snd.playing:
		_rain_snd.play()
	if _env:
		_base_amb = _env.ambient_light_energy if not on else _base_amb
		_base_fog = _env.fog_density if not on else _base_fog


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_Y:
		if _env:
			_base_amb = _env.ambient_light_energy
			_base_fog = _env.fog_density
		set_rain(not raining)


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		_particles.global_position = cam.global_position + Vector3(0, 14, 0) - cam.global_basis.z * 10.0
	_wet = move_toward(_wet, 1.0 if raining else 0.0, dt / (8.0 if raining else 25.0))
	RenderingServer.global_shader_parameter_set("wetness", _wet)
	# rain makes tyres slide: feed wetness into every car's grip model
	for car in get_tree().get_nodes_in_group(&"vehicles"):
		car.set("wetness", _wet)
	_rain_snd.volume_db = linear_to_db(maxf(_wet if raining else _wet * 0.3, 0.0001)) - 4.0
	if _wet < 0.01 and not raining and _rain_snd.playing:
		_rain_snd.stop()
	if _env:
		_env.fog_density = lerpf(_base_fog, maxf(_base_fog * 4.0, 0.003), _wet)
		_env.ambient_light_energy = lerpf(_base_amb, _base_amb * 0.7, _wet) + _flash_t * 3.0
	_flash_t = maxf(_flash_t - dt * 4.0, 0.0)
	if raining and _wet > 0.6:
		_next_bolt -= dt
		if _next_bolt <= 0.0:
			_next_bolt = randf_range(14.0, 35.0)
			_flash_t = 1.0
			get_tree().create_timer(randf_range(0.6, 2.5)).timeout.connect(_thunder.play)


func _hi_gfx() -> bool:
	var g := get_node_or_null("/root/Game")
	return g == null or bool(g.get("high_graphics"))


func _scene_root() -> Node:
	var cs := get_tree().current_scene
	return cs if cs else get_tree().root
