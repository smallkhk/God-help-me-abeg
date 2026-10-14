extends Node
## Bridge Test Sprint (spec §11): start marker, countdown, ordered checkpoints,
## timer, finish and a results panel with retry + best-time persistence. Built
## from reusable chunk route data (spec §11 "data-driven with stable IDs").

@export var event_id: String = "bridge_test_sprint"
## Optional data-driven event definition (spec §11). When set, its name, countdown
## and best-time key are used; otherwise the fields above/defaults apply.
@export var event: RaceEvent
@export var map_builder_path: NodePath
@export var player_path: NodePath
@export var hud_path: NodePath
@export var checkpoint_scene: PackedScene

enum State { IDLE, COUNTDOWN, RUNNING, FINISHED }
var _state: int = State.IDLE

var _player: VehicleController
var _hud: CanvasLayer
var _builder: MapBuilder
var _spawn: Transform3D

var _gates: Array[Checkpoint] = []
var _next: int = 0
var _countdown: float = 0.0
var _elapsed: float = 0.0

var _layer: CanvasLayer
var _center_label: Label
var _results: Label


# --- rivals ---
const CAR_SCENE := "res://scenes/vehicles/player/player_car.tscn"
const RIVAL_NAMES := ["Tunde", "Chioma", "Emeka", "Bisi", "Femi"]
var _rivals: Array[VehicleController] = []
var _route: Array = []
var _start_idx := 0
var _player_prog := 0
var _finish_order: Array[String] = []
var _pos_label: Label

var _initialized := false
var _free := false
var _ext := false
var _ext_checkpoints: Array = []
const RACE_LEN := 2500.0
var _finish_idx := -1

# --- laps (closed circuits: chunk "loop": true) ---
var _loop := false
var _laps := 1
var _lap := 0                  # completed laps
var _lap_start := 0.0
var _best_lap := 0.0
var _lap_label: Label
var _player_wraps := 0
var _lanes: Array[float] = []
var _elapsed_banner := 0.0
var _fall_check := 0.0


func _ready() -> void:
	_player = get_node_or_null(player_path) as VehicleController
	_hud = get_node_or_null(hud_path) as CanvasLayer
	_builder = get_node_or_null(map_builder_path) as MapBuilder
	if event:
		event_id = event.best_time_key()
	_build_ui()
	# Setup is deferred to the first frame (see _initialize) so an external track
	# loader can call configure_external() after this _ready but before the race
	# actually starts.


## Used by the drop-in external track loader: supply spawn + ordered checkpoints
## directly instead of reading them from a MapBuilder chunk.
func configure_external(spawn: Transform3D, checkpoints: Array) -> void:
	_spawn = spawn
	_ext_checkpoints = checkpoints
	_ext = true


func _initialize() -> void:
	_initialized = true
	var gs := get_node_or_null("/root/Game")
	if gs and gs.get("free_roam") and _builder:
		# free roam: just put the car on the road and get out of the way
		var ch := _builder.get_chunk()
		if not ch.is_empty():
			_spawn = MapLoader.spawn_transform(ch)
			_player.global_transform = _spawn
			_player.reset_state()
		for c in get_children():
			if c is CanvasLayer:
				c.visible = false
		_free = true
		set_process_unhandled_input(false)
		return
	if _builder:
		var chunk := _builder.get_chunk()
		if not chunk.is_empty():
			_spawn = MapLoader.spawn_transform(chunk)
			_route = chunk["road"]["samples"]
			_start_idx = _nearest_sample(_spawn.origin, 0, _route.size())
			_loop = bool(chunk.get("loop", false))
			var r: Dictionary = chunk["road"]
			var lw: float = float(r.get("lane_width_m", 3.5))
			for k in int(r.get("lanes_per_direction", 2)):
				_lanes.append(float(r.get("median_width_m", 1.0)) * 0.5 + lw * (k + 0.5))
			var cps: Array = []
			if _loop:
				# street circuit: every gate, the last one is the start/finish line
				_laps = maxi(1, event.laps if event else 1)
				for cp in chunk.get("checkpoints", []):
					var c2: Dictionary = cp.duplicate()
					c2["index"] = cps.size()
					cps.append(c2)
				_spawn_gates(cps)
				_finish_idx = -1
			else:
				# short, punchy races: keep only the gates within RACE_LEN metres
				var d0: float = float(_route[_start_idx].get("dist_m", 0.0))
				for cp in chunk.get("checkpoints", []):
					if float(cp.get("dist_m", 0.0)) - d0 <= RACE_LEN or cps.size() < 2:
						var c2: Dictionary = cp.duplicate()
						c2["index"] = cps.size()
						cps.append(c2)
				_spawn_gates(cps)
				var last: Dictionary = cps[cps.size() - 1] if not cps.is_empty() else {}
				_finish_idx = _nearest_sample(Vector3(last.get("x", 0.0), 0, last.get("z", 0.0)), 0, _route.size()) if not last.is_empty() else _route.size() - 1
			_spawn_rivals()
	elif _ext:
		_spawn_gates(_ext_checkpoints)
	_reset_to_idle()


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 10
	add_child(_layer)

	_center_label = Label.new()
	_center_label.anchors_preset = Control.PRESET_CENTER
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 64)
	_center_label.position = Vector2(540, 300)
	_center_label.size = Vector2(200, 100)
	_layer.add_child(_center_label)

	_results = Label.new()
	_results.anchors_preset = Control.PRESET_CENTER
	_results.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results.add_theme_font_size_override("font_size", 28)
	_results.position = Vector2(440, 240)
	_results.size = Vector2(400, 220)
	_results.visible = false
	_layer.add_child(_results)

	_pos_label = Label.new()
	_pos_label.add_theme_font_size_override("font_size", 40)
	_pos_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_pos_label.add_theme_constant_override("outline_size", 8)
	_pos_label.anchor_left = 1.0; _pos_label.anchor_right = 1.0
	_pos_label.offset_left = -260; _pos_label.offset_right = -24; _pos_label.offset_top = 20
	_pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_layer.add_child(_pos_label)

	_lap_label = Label.new()
	_lap_label.add_theme_font_size_override("font_size", 30)
	_lap_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_lap_label.add_theme_constant_override("outline_size", 8)
	_lap_label.anchor_left = 1.0; _lap_label.anchor_right = 1.0
	_lap_label.offset_left = -360; _lap_label.offset_right = -24; _lap_label.offset_top = 68
	_lap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_layer.add_child(_lap_label)


func _spawn_gates(checkpoints: Array) -> void:
	if checkpoint_scene == null:
		push_warning("race_manager: no checkpoint_scene assigned.")
		return
	for cp in checkpoints:
		var gate := checkpoint_scene.instantiate() as Checkpoint
		gate.index = int(cp["index"])
		var pos := Vector3(cp["x"], float(cp["y"]) + 0.1, cp["z"])
		gate.transform = Transform3D(Basis(Vector3.UP, float(cp["heading_rad"])), pos)
		add_child(gate)
		gate.passed.connect(_on_checkpoint_passed)
		_gates.append(gate)


func _reset_to_idle() -> void:
	_state = State.IDLE
	_next = 0
	_elapsed = 0.0
	_lap = 0
	_lap_start = 0.0
	_best_lap = 0.0
	_player_wraps = 0
	if _lap_label:
		_lap_label.text = ("LAP 1/%d" % _laps) if _loop else ""
	_results.visible = false
	for g in _gates:
		g.set_target(g.index == 0)
	_center_label.text = "Press W / Accelerate to start"
	if _player:
		_player.linear_velocity = Vector3.ZERO
		_player.angular_velocity = Vector3.ZERO
		_player.global_transform = _spawn
		_player.transmission.gear = 0
		_player.set_driver_input(0, 0, 0, false)
	_finish_order.clear()
	_player_prog = _start_idx
	_place_rivals()


func _unhandled_input(ev: InputEvent) -> void:
	if not _initialized:
		return
	if ev.is_action_pressed("restart"):
		_reset_to_idle()
		return
	if _state == State.IDLE and ev.is_action_pressed("accelerate"):
		_start_countdown()


func _start_countdown() -> void:
	_state = State.COUNTDOWN
	_countdown = event.countdown if event else 3.0


func _process(delta: float) -> void:
	if not _initialized:
		_initialize()
	if _free:
		if _player and _player.global_position.y < -25.0:
			_player.global_transform = _spawn
			_player.reset_state()
		return

	# Safety net: if the car ever ends up below the road (fell through a seam, got
	# shoved by traffic, or a track with no floor), put it back on the road where
	# it was, facing along the route — not back at the start grid.
	if _player and _route.size() > 1:
		_fall_check -= delta
		if _player.global_position.y < -25.0:
			_recover_player()
		elif _fall_check <= 0.0:
			_fall_check = 0.25
			var i := _nearest_sample(_player.global_position, 0, _route.size())
			if _player.global_position.y < float(_route[i]["elev_m"]) - 2.5:
				_recover_player()
	elif _player and _player.global_position.y < -25.0:
		_player.linear_velocity = Vector3.ZERO
		_player.angular_velocity = Vector3.ZERO
		_player.global_transform = _spawn
		_player.reset_state()

	match _state:
		State.COUNTDOWN:
			_countdown -= delta
			if _countdown <= 0.0:
				_begin_run()
			else:
				_center_label.text = str(int(ceil(_countdown)))
		State.RUNNING:
			_elapsed += delta
			if _center_label.text != "" and _elapsed - _elapsed_banner > 1.5:
				_center_label.text = ""
			_update_positions()
			if _loop:
				_lap_label.text = "LAP %d/%d   %s" % [mini(_lap + 1, _laps), _laps, _fmt(_elapsed - _lap_start)]
				if _best_lap > 0.0:
					_lap_label.text += "\nBEST LAP %s" % _fmt(_best_lap)


func _begin_run() -> void:
	_state = State.RUNNING
	_elapsed = 0.0
	_next = 0
	_center_label.text = "GO!"
	_elapsed_banner = 0.0
	for g in _gates:
		g.set_target(g.index == 0)
	for r in _rivals:
		var d := r.get_node("RivalDriver") as RivalDriver
		d.active = true
	if _hud and _hud.has_method("start_timer"):
		_hud.start_timer(not _loop)   # lap races show the lap time instead


func _on_checkpoint_passed(index: int) -> void:
	if _state != State.RUNNING or index != _next:
		return
	_gates[index].set_target(false)
	_next += 1
	if _next >= _gates.size():
		if _loop:
			var lt := _elapsed - _lap_start
			if _best_lap <= 0.0 or lt < _best_lap:
				_best_lap = lt
			_lap += 1
			_lap_start = _elapsed
			if _lap < _laps:
				_next = 0
				_gates[0].set_target(true)
				_center_label.text = "FINAL LAP" if _lap == _laps - 1 else "LAP %d" % (_lap + 1)
				_elapsed_text_hold()
				return
		_finish()
	else:
		_gates[_next].set_target(true)


func _elapsed_text_hold() -> void:
	# show the lap banner for a moment (cleared in _process)
	_elapsed_banner = _elapsed


func _finish() -> void:
	_state = State.FINISHED
	var final_time := _elapsed
	if _hud and _hud.has_method("stop_timer"):
		final_time = _hud.stop_timer()
	var is_best := SaveManager.record_time(event_id, final_time)
	var best := SaveManager.get_best_time(event_id)
	_center_label.text = ""
	_results.visible = true
	_finish_order.append("YOU")
	var place := _finish_order.size()
	var place_txt := ""
	if not _rivals.is_empty():
		place_txt = "%s place of %d\n" % [_ordinal(place), _rivals.size() + 1]
	var base_reward: int = event.reward_naira if event else 500000
	var mult := 0.5
	if not _rivals.is_empty():
		mult = [1.0, 0.6, 0.4, 0.25, 0.15, 0.1][mini(place - 1, 5)]
	var reward := int(base_reward * mult)
	var g := get_node_or_null("/root/Game")
	if g:
		g.add_money(reward)
	place_txt += "Prize: %s\n" % Game.naira(reward)
	if _loop and _best_lap > 0.0:
		place_txt += "Best lap: %s\n" % _fmt(_best_lap)
	_results.text = "FINISH\n\n%sTime: %s\nBest: %s%s\n\nR = retry    Esc = menu" % [
		place_txt, _fmt(final_time), _fmt(best),
		"   (NEW BEST!)" if is_best else "",
	]


static func _fmt(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	var ms := int((t - int(t)) * 1000.0)
	return "%02d:%02d.%03d" % [m, s, ms]


# ---------------- rivals ----------------

func _spawn_rivals() -> void:
	var n := int(Game.get_setting("rivals", 4))
	if n <= 0 or _route.size() < 50:
		return
	var ids := CarDatabase.ORDER
	var scene := load(CAR_SCENE) as PackedScene
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var colors := [Color(0.1, 0.3, 0.8), Color(0.95, 0.75, 0.1), Color(0.1, 0.6, 0.3),
		Color(0.9, 0.9, 0.92), Color(0.5, 0.15, 0.6)]
	for i in mini(n, RIVAL_NAMES.size()):
		var car := scene.instantiate() as VehicleController
		car.is_player = false
		for c in ["PlayerDriver", "VehicleDebug"]:
			var node := car.get_node_or_null(c)
			if node:
				node.free()
		var d := CarDatabase.get_data(ids[rng.randi() % ids.size()])
		if d:
			car.data = d
		car.name = "Rival_" + RIVAL_NAMES[i]
		var drv := RivalDriver.new()
		drv.name = "RivalDriver"
		drv.route = _route
		drv.player = _player
		if _loop:
			drv.loop = true
			drv.laps_needed = _laps + 1    # first wrap = crossing the start line
			if not _lanes.is_empty():
				drv.lanes.assign(_lanes)
		drv.skill = rng.randf_range(0.75, 1.0)
		drv.aggression = [0.85, 0.35, 0.6, 0.2, 0.7][i % 5]   # Tunde dirty, Bisi clean...
		drv.road_half = float(_builder.get_chunk()["road"]["half_width_m"]) if _builder else 8.0
		car.add_child(drv)
		var au := CarAudio.new()
		au.vehicle = car
		au.is_player = false
		car.add_child(au)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i % colors.size()]
		mat.metallic = 0.3; mat.roughness = 0.35
		for mn in ["Body", "Cabin"]:
			var m := car.get_node_or_null(mn) as MeshInstance3D
			if m:
				m.material_override = mat
		var tag := Label3D.new()
		tag.text = RIVAL_NAMES[i]
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 2.2, 0)
		tag.font_size = 48
		tag.outline_size = 10
		tag.no_depth_test = true
		car.add_child(tag)
		get_parent().add_child.call_deferred(car)
		_rivals.append(car)
	_place_rivals.call_deferred()


## Starting grid: player front-left; rivals fill the other lanes and rows behind.
func _place_rivals() -> void:
	var slots := [[0, 5.9], [0, 9.4], [-1, 2.4], [-1, 5.9], [-1, 9.4]]
	var row_step := 2
	if _loop and _lanes.size() >= 2:
		var l0: float = _lanes[0]; var l1: float = _lanes[_lanes.size() - 1]
		slots = [[0, l0], [-1, l1], [-1, l0], [-2, l1], [-2, l0]]
		var sp: float = float(_route[1]["dist_m"]) - float(_route[0]["dist_m"])
		row_step = maxi(1, int(ceil(8.0 / maxf(sp, 0.5))))
	var m := _route.size() - 1
	for i in _rivals.size():
		var car := _rivals[i]
		if not car.is_inside_tree():
			continue
		var row: int = slots[i][0]; var lane: float = slots[i][1]
		var si := posmod(_start_idx + row * row_step, m) if _loop else clampi(_start_idx + row * 2, 0, _route.size() - 1)
		var smp = _route[si]
		var h: float = smp["heading_rad"]
		var pos := Vector3(smp["x"], float(smp["elev_m"]) + 0.6, smp["z"]) + Vector3(cos(h), 0, -sin(h)) * lane
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.global_transform = Transform3D(Basis(Vector3.UP, h), pos)
		car.reset_state()
		var d := car.get_node("RivalDriver") as RivalDriver
		d.active = false
		d.finished = false
		d.progress = si
		d.wraps = 0
		d.lane_offset = lane
		if _finish_idx > 0:
			d.finish_idx = _finish_idx


func _update_positions() -> void:
	if _rivals.is_empty() or _player == null:
		_pos_label.text = ""
		return
	var ahead := 0
	if _loop:
		var m := _route.size() - 1
		var prev := _player_prog
		_player_prog = _nearest_loop(_player.global_position, prev, m)
		if prev > m * 3 / 4 and _player_prog < m / 4:
			_player_wraps += 1
		elif prev < m / 4 and _player_prog > m * 3 / 4:
			_player_wraps -= 1
		var mine := _player_wraps * m + _player_prog
		for r in _rivals:
			var d := r.get_node("RivalDriver") as RivalDriver
			if d.finished:
				if not _finish_order.has(String(r.name)):
					_finish_order.append(String(r.name))
				ahead += 1
			elif d.wraps * m + d.progress > mine:
				ahead += 1
		_pos_label.text = "POS %d/%d" % [ahead + 1, _rivals.size() + 1]
		return
	_player_prog = _nearest_sample(_player.global_position, maxi(_player_prog - 20, 0), mini(_player_prog + 60, _route.size()))
	for r in _rivals:
		var d := r.get_node("RivalDriver") as RivalDriver
		if d.finished:
			if not _finish_order.has(String(r.name)):
				_finish_order.append(String(r.name))
			ahead += 1
		elif d.progress > _player_prog:
			ahead += 1
	_pos_label.text = "POS %d/%d" % [ahead + 1, _rivals.size() + 1]


func _recover_player() -> void:
	var i := _nearest_sample(_player.global_position, 0, _route.size())
	var smp = _route[i]
	var h: float = smp["heading_rad"]
	var lane: float = _lanes[_lanes.size() - 1] if not _lanes.is_empty() else 0.0
	var pos := Vector3(smp["x"], float(smp["elev_m"]) + 0.8, smp["z"]) + Vector3(cos(h), 0, -sin(h)) * lane
	_player.linear_velocity = Vector3.ZERO
	_player.angular_velocity = Vector3.ZERO
	_player.global_transform = Transform3D(Basis(Vector3.UP, h), pos)
	_player.reset_state()


## Nearest route sample on a closed loop, searching a window that wraps.
func _nearest_loop(p: Vector3, around: int, m: int) -> int:
	var best := around; var bd := INF
	for k in range(-20, 61):
		var i := posmod(around + k, m)
		var s = _route[i]
		var d := Vector2(s["x"] - p.x, s["z"] - p.z).length_squared()
		if d < bd:
			bd = d; best = i
	return best


func _nearest_sample(p: Vector3, a: int, b: int) -> int:
	var best := a; var bd := INF
	for i in range(a, b):
		var s = _route[i]
		var d := Vector2(s["x"] - p.x, s["z"] - p.z).length_squared()
		if d < bd:
			bd = d; best = i
	return best


static func _ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
	return "%dth" % n
