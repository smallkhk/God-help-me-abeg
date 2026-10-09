extends Node
## Bridge Test Sprint (spec §11): start marker, countdown, ordered checkpoints,
## timer, finish and a results panel with retry + best-time persistence. Built
## from reusable chunk route data (spec §11 "data-driven with stable IDs").

@export var event_id: String = "bridge_test_sprint"
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


func _ready() -> void:
	_player = get_node_or_null(player_path) as VehicleController
	_hud = get_node_or_null(hud_path) as CanvasLayer
	_builder = get_node_or_null(map_builder_path) as MapBuilder
	_build_ui()

	if _builder:
		var chunk := _builder.get_chunk()
		if not chunk.is_empty():
			_spawn = MapLoader.spawn_transform(chunk)
			_spawn_gates(chunk.get("checkpoints", []))
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		_reset_to_idle()
		return
	if _state == State.IDLE and event.is_action_pressed("accelerate"):
		_start_countdown()


func _start_countdown() -> void:
	_state = State.COUNTDOWN
	_countdown = 3.0


func _process(delta: float) -> void:
	match _state:
		State.COUNTDOWN:
			_countdown -= delta
			if _countdown <= 0.0:
				_begin_run()
			else:
				_center_label.text = str(int(ceil(_countdown)))
		State.RUNNING:
			_elapsed += delta
			_center_label.text = ""


func _begin_run() -> void:
	_state = State.RUNNING
	_elapsed = 0.0
	_next = 0
	_center_label.text = "GO!"
	for g in _gates:
		g.set_target(g.index == 0)
	if _hud and _hud.has_method("start_timer"):
		_hud.start_timer()


func _on_checkpoint_passed(index: int) -> void:
	if _state != State.RUNNING or index != _next:
		return
	_gates[index].set_target(false)
	_next += 1
	if _next >= _gates.size():
		_finish()
	else:
		_gates[_next].set_target(true)


func _finish() -> void:
	_state = State.FINISHED
	var final_time := _elapsed
	if _hud and _hud.has_method("stop_timer"):
		final_time = _hud.stop_timer()
	var is_best := SaveManager.record_time(event_id, final_time)
	var best := SaveManager.get_best_time(event_id)
	_center_label.text = ""
	_results.visible = true
	_results.text = "FINISH\n\nTime: %s\nBest: %s%s\n\nPress R to retry" % [
		_fmt(final_time), _fmt(best),
		"   (NEW BEST!)" if is_best else "",
	]


static func _fmt(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	var ms := int((t - int(t)) * 1000.0)
	return "%02d:%02d.%03d" % [m, s, ms]
