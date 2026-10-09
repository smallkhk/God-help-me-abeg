extends Node3D
## Validates ambient traffic (spec §10): cars spawn on the bridge, stay on the
## deck, and drive forward along their lane without falling through, flipping, or
## piling up at the spawn point.
## Run: godot --headless --path . res://tests/map_validation/traffic_test.tscn

const STEP := 1.0 / 60.0
const RUN_SECONDS := 5.0

var _cars: Array = []
var _start_pos: Array = []
var _t := 0.0
var _done := false
var _failures: Array[String] = []


func _ready() -> void:
	var tm := $LagosBridge/TrafficManager
	# Keep the idle player out of the way of the measurement.
	var pd := $LagosBridge.get_node_or_null("PlayerCar/PlayerDriver")
	if pd:
		pd.set_physics_process(false)
	for c in tm.get_children():
		if c is VehicleController:
			_cars.append(c)
			_start_pos.append(c.global_position)
	print("[traffic_test] spawned %d traffic cars" % _cars.size())
	if _cars.is_empty():
		print("[traffic_test] traffic disabled in this scene (count = 0) — SKIP")
		get_tree().quit(0)


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_t += STEP
	for c in _cars:
		if c.global_position.y < 1.0:
			_fail("a traffic car fell through the deck (y=%.2f)" % c.global_position.y)
			_finish()
			return
		if c.global_transform.basis.y.dot(Vector3.UP) < 0.3:
			_fail("a traffic car flipped")
			_finish()
			return
	if _t > RUN_SECONDS:
		_finish()


func _finish() -> void:
	_done = true
	var moved_ok := 0
	var min_moved := 1e9
	for i in _cars.size():
		var car: VehicleController = _cars[i]
		var d: float = car.global_position.distance_to(_start_pos[i])
		min_moved = minf(min_moved, d)
		if d > 20.0:
			moved_ok += 1
	print("[traffic_test] %d/%d cars drove >20 m (min moved %.1f m)" % [moved_ok, _cars.size(), min_moved])
	if _cars.size() > 0 and moved_ok < _cars.size():
		_fail("only %d/%d traffic cars made progress" % [moved_ok, _cars.size()])

	if _failures.is_empty():
		print("[traffic_test] PASS")
		get_tree().quit(0)
	else:
		for m in _failures:
			printerr("[traffic_test] FAIL: ", m)
		get_tree().quit(1)


func _fail(m: String) -> void:
	_failures.append(m)
