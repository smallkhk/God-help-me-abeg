extends Node3D
class_name AmbientTraffic
## Lagos street life that moves: danfos (stopping to pick up passengers), kekes,
## okadas weaving between lanes, BRT buses and private cars, driving both ways
## along the race road. Each vehicle is a kinematic AnimatableBody3D (no physics
## sim — cheap enough for phones) placed around the player and recycled when it
## falls too far behind or ahead. Also plays the city ambience sounds.

const MODELS := {
	# model: [path, lift, yaw offset, scale, length m, weight]
	"danfo": ["res://assets/vehicles/danfo/danfo.glb", 1.0, PI * 0.5, 1.0, 4.8, 5],
	"keke": ["res://assets/vehicles/keke/keke.glb", 0.9, -PI * 0.5, 1.0, 2.7, 3],
	"okada": ["res://assets/vehicles/okada/okada.glb", 0.66, -PI * 0.5, 1.1, 2.0, 4],
	"brt": ["res://assets/vehicles/brt/brt.glb", 2.0, -PI * 0.5, 1.25, 12.0, 1],
	"accord": ["res://assets/vehicles/sf_accord08/accord08.glb", 0.0, 0.0, 1.0, 4.85, 2],
	"p406": ["res://assets/vehicles/p406/p406.glb", 0.0, -PI * 0.5, 1.0, 4.7, 2],
	"golf3": ["res://assets/vehicles/golf3/golf3.glb", 0.0, PI * 0.5, 1.0, 4.05, 2],
	"molue": ["res://assets/models/lagos/molue.glb", 0.0, -PI * 0.5, 1.0, 11.0, 2],
	"tanker": ["res://assets/models/lagos/tanker.glb", 0.0, -PI * 0.5, 1.0, 12.0, 1],
	"cement": ["res://assets/models/lagos/cement.glb", 0.0, -PI * 0.5, 1.0, 9.0, 1],
	"watertanker": ["res://assets/models/lagos/watertanker.glb", 0.0, -PI * 0.5, 1.0, 8.0, 1],
}

var chunk: Dictionary
var count := 18
var radius := 650.0

var _route: Array = []
var _cum: PackedFloat32Array = PackedFloat32Array()
var _len := 0.0
var _hw := 10.0
var _lane_w := 3.5
var _lanes := 3
var _median := 0.6
var _vehicles: Array = []
var _scenes := {}
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _pick: Array = []
var _horn_t := 6.0
var _horn_player: AudioStreamPlayer3D
var _conductor: AudioStreamPlayer3D
var _okada_snd: AudioStream


func _ready() -> void:
	_rng.seed = 777
	_route = chunk["road"]["samples"]
	if _route.size() < 4:
		return
	var r: Dictionary = chunk["road"]
	_hw = r["half_width_m"]; _lane_w = r.get("lane_width_m", 3.5)
	_lanes = int(r.get("lanes_per_direction", 2)); _median = float(r.get("median_width_m", 1.0)) * 0.5
	_cum.resize(_route.size())
	for i in _route.size():
		if i > 0:
			var a = _route[i - 1]; var b = _route[i]
			_len += Vector2(a["x"], a["z"]).distance_to(Vector2(b["x"], b["z"]))
		_cum[i] = _len
	for k in MODELS:
		_scenes[k] = load(MODELS[k][0])
		for w in MODELS[k][5]:
			_pick.append(k)
	if not _hi_gfx():
		count = 9
	elif OS.has_feature("mobile"):
		count = 12
	_ambience()
	await get_tree().process_frame
	_find_player()
	for i in count:
		_spawn(true)


func _find_player() -> void:
	for n in _scene_root().find_children("*", "VehicleController", true, false):
		if n.get("is_player"):
			_player = n
			return


func _player_d() -> float:
	if _player == null:
		return 0.0
	# nearest route distance to the player
	var pp := _player.global_position
	var best := 0; var bd := INF
	for i in range(0, _route.size(), 4):
		var d := Vector2(_route[i]["x"] - pp.x, _route[i]["z"] - pp.z).length_squared()
		if d < bd:
			bd = d; best = i
	return _cum[best]


func _spawn(initial: bool) -> void:
	var kind: String = _pick[_rng.randi() % _pick.size()]
	var m: Array = MODELS[kind]
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	var vis: Node3D = _scenes[kind].instantiate()
	vis.position = Vector3(0, m[1], 0)
	vis.rotation.y = m[2]
	vis.scale = Vector3.ONE * m[3]
	body.add_child(vis)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var big: bool = kind in ["brt", "molue", "tanker", "cement", "watertanker"]
	var wid := 0.8 if kind == "okada" else (2.6 if big else 1.8)
	box.size = Vector3(wid, 3.0 if big else 1.6, m[4])
	cs.shape = box
	cs.position = Vector3(0, box.size.y * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	var dir := 1.0 if _rng.randf() < 0.55 else -1.0
	var lane := _rng.randi_range(0, maxi(_lanes - 1, 0))
	if kind in ["danfo", "keke", "brt"]:
		lane = maxi(_lanes - 1, 0)   # slow vehicles keep to the kerb lane
	if kind in ["molue", "tanker", "cement", "watertanker"]:
		lane = maxi(_lanes - 1, 0)
	var spd: float = {"molue": 11.0, "tanker": 10.0, "cement": 10.0, "watertanker": 10.0, "danfo": 12.0, "keke": 9.0, "okada": 14.0, "brt": 11.0}.get(kind, 16.0) * _rng.randf_range(0.85, 1.2)
	var pd := _player_d()
	var d := pd + _rng.randf_range(-radius, radius) if initial else pd + (radius * 0.9 if _rng.randf() < 0.6 else -radius * 0.9)
	var v := {"body": body, "kind": kind, "dir": dir, "lane": lane, "speed": spd, "d": fposmod(d, _len),
		"stop": 0.0, "next_stop": _rng.randf_range(80.0, 300.0), "phase": _rng.randf() * TAU, "x": 0.0}
	if kind == "danfo" or kind == "brt":
		var l := SpotLight3D.new()
		l.position = Vector3(0, 1.0, m[4] * 0.5)
		l.rotation.x = -0.12
		l.light_energy = 0.0
		l.spot_range = 28.0
		l.spot_angle = 35.0
		body.add_child(l)
		v["light"] = l
	if kind == "okada" and _okada_snd:
		var au := AudioStreamPlayer3D.new()
		au.stream = _okada_snd
		au.unit_size = 6.0
		au.max_distance = 60.0
		au.volume_db = -6.0
		au.autoplay = true
		body.add_child(au)
	_vehicles.append(v)
	_place(v)


func _sample_at(d: float) -> Array:
	d = fposmod(d, _len)
	var lo := 0; var hi := _cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var a = _route[lo]; var b = _route[hi]
	var seg := maxf(_cum[hi] - _cum[lo], 0.001)
	var t := (d - _cum[lo]) / seg
	var p := Vector3(lerpf(a["x"], b["x"], t), lerpf(float(a["elev_m"]), float(b["elev_m"]), t), lerpf(a["z"], b["z"], t))
	var h := lerp_angle(float(a["heading_rad"]), float(b["heading_rad"]), t)
	return [p, h]


func _place(v: Dictionary) -> void:
	var s := _sample_at(v["d"])
	var h: float = s[1]
	if v["dir"] < 0:
		h += PI
	var perp := Vector3(cos(h), 0.0, -sin(h))   # right of this vehicle's travel
	var off: float = _median + _lane_w * (float(v["lane"]) + 0.5) + v["x"]
	var pos: Vector3 = s[0] + perp * off + Vector3(0, 0.05, 0)
	(v["body"] as Node3D).global_transform = Transform3D(Basis(Vector3.UP, h), pos)


func _physics_process(dt: float) -> void:
	if _vehicles.is_empty():
		return
	var pd := _player_d()
	var gs := get_node_or_null("/root/Game")
	var night: float = float(gs.get("night")) if gs else 0.0
	for v in _vehicles:
		var spd: float = v["speed"]
		if v["kind"] == "danfo":
			# pick-up stops: pull over, wait, shout, go
			if v["stop"] > 0.0:
				v["stop"] -= dt
				spd = 0.0
				v["x"] = lerpf(v["x"], 1.4, dt * 1.5)
			else:
				v["next_stop"] -= spd * dt
				v["x"] = lerpf(v["x"], 0.0, dt)
				if v["next_stop"] <= 0.0:
					v["stop"] = _rng.randf_range(3.0, 7.0)
					v["next_stop"] = _rng.randf_range(150.0, 400.0)
					if _conductor and _player and (v["body"] as Node3D).global_position.distance_to(_player.global_position) < 60.0 and not _conductor.playing:
						_conductor.global_position = (v["body"] as Node3D).global_position
						_conductor.play()
		elif v["kind"] == "okada":
			v["phase"] += dt * 0.7
			v["x"] = sin(v["phase"]) * _lane_w * 0.45   # weaving
		v["d"] = fposmod(float(v["d"]) + spd * dt * float(v["dir"]), _len)
		_place(v)
		if v.has("light"):
			(v["light"] as SpotLight3D).light_energy = 3.0 * night
		# recycle when out of range
		var rel := absf(fposmod(float(v["d"]) - pd + _len * 0.5, _len) - _len * 0.5)
		if rel > radius * 1.1:
			var dd: float = pd + (radius * 0.95 if _rng.randf() < 0.5 else -radius * 0.95)
			v["d"] = fposmod(dd, _len)
	_horn_t -= dt
	if _horn_t <= 0.0 and _horn_player and _player:
		_horn_t = _rng.randf_range(7.0, 18.0)
		var near: Node3D = _vehicles[_rng.randi() % _vehicles.size()]["body"]
		_horn_player.global_position = near.global_position
		_horn_player.play(_rng.randf() * 4.0)


func _ambience() -> void:
	var city := AudioStreamPlayer.new()
	var st: AudioStream = load("res://assets/audio/sfx/city.ogg")
	if st is AudioStreamOggVorbis:
		st.loop = true
	city.stream = st
	city.volume_db = -16.0
	city.autoplay = true
	add_child(city)
	_horn_player = AudioStreamPlayer3D.new()
	_horn_player.stream = load("res://assets/audio/sfx/horns.ogg")
	_horn_player.unit_size = 25.0
	_horn_player.volume_db = -4.0
	add_child(_horn_player)
	_okada_snd = load("res://assets/audio/sfx/okada.ogg")
	if _okada_snd is AudioStreamOggVorbis:
		_okada_snd.loop = true
	_conductor = AudioStreamPlayer3D.new()
	_conductor.stream = load("res://assets/audio/sfx/conductor.ogg")
	_conductor.unit_size = 18.0
	add_child(_conductor)


func _hi_gfx() -> bool:
	var g := get_node_or_null("/root/Game")
	return g == null or bool(g.get("high_graphics"))


func _scene_root() -> Node:
	var cs := get_tree().current_scene
	return cs if cs else get_tree().root
