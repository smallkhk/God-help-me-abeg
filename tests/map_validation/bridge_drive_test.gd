extends Node3D
## End-to-end map validation (spec §18, §8.3 "roads must be driveable").
## Instances the real lagos_bridge scene, drives the player car along the
## centerline with simple pure-pursuit, and asserts it stays on the deck
## (grounded, above the water, no long airborne stretch from a mesh gap).
## Run: godot --headless --path . res://tests/map_validation/bridge_drive_test.tscn

const KMH := 3.6
const STEP := 1.0 / 60.0
const DRIVE_SECONDS := 6.0

var _car: VehicleController
var _samples: Array = []
var _t := 0.0
var _started := false
var _failures: Array[String] = []
var _max_airborne := 0
var _airborne := 0
var _min_y := 1e9
var _dist := 0.0
var _last := Vector3.ZERO
var _done := false


func _ready() -> void:
	var bridge := $LagosBridge
	_car = bridge.get_node("PlayerCar") as VehicleController
	var driver := bridge.get_node_or_null("PlayerCar/PlayerDriver")
	if driver:
		driver.set_physics_process(false)
	var chunk := (bridge.get_node("MapBuilder") as MapBuilder).get_chunk()
	_samples = chunk["road"]["samples"]
	print("[bridge_drive_test] road %.0f m, %d samples, spawn y=%.2f" % [
		chunk["road"]["length_m"], _samples.size(), _car.global_position.y])


func _physics_process(_delta: float) -> void:
	if _done:
		return
	if not _started:
		_started = true
		_last = _car.global_position
	_t += STEP
	var pos := _car.global_position
	_dist += pos.distance_to(_last)
	_last = pos

	_car.set_driver_input(0.6, 0.0, _steer(pos), false)

	if _t > 1.0:  # let it settle
		_min_y = minf(_min_y, pos.y)
		if _car.wheels_on_ground == 0:
			_airborne += 1
			_max_airborne = maxi(_max_airborne, _airborne)
		else:
			_airborne = 0
		if pos.y < 1.0:
			_fail("car dropped to y=%.2f at t=%.1fs (fell through road)" % [pos.y, _t])
			_finish()
			return

	if _t > DRIVE_SECONDS:
		_finish()


func _steer(pos: Vector3) -> float:
	var best_i := 0
	var best_d := INF
	for i in _samples.size():
		var s = _samples[i]
		var d: float = Vector2(s["x"] - pos.x, s["z"] - pos.z).length_squared()
		if d < best_d:
			best_d = d
			best_i = i
	var ahead = _samples[mini(best_i + 3, _samples.size() - 1)]
	var ah: float = ahead["heading_rad"]
	var lane := Vector3(cos(ah), 0, -sin(ah)) * MapLoader.LANE_OFFSET
	var to_t := Vector3(ahead["x"] + lane.x - pos.x, 0, ahead["z"] + lane.z - pos.z)
	var fwd := _car.global_transform.basis.z
	var right := _car.global_transform.basis.x
	return clampf(atan2(to_t.dot(right), maxf(to_t.dot(fwd), 0.1)) * 1.5, -1.0, 1.0)


func _fail(m: String) -> void:
	_failures.append(m)


func _finish() -> void:
	_done = true
	print("[bridge_drive_test] drove %.0f m, lowest y=%.2f, max airborne %d ticks" % [
		_dist, _min_y, _max_airborne])
	if _max_airborne > 45:
		_fail("airborne %d consecutive ticks — likely a road gap" % _max_airborne)
	if _dist < 30.0:
		_fail("car barely moved (%.0f m)" % _dist)
	if _failures.is_empty():
		print("[bridge_drive_test] PASS")
		get_tree().quit(0)
	else:
		for m in _failures:
			printerr("[bridge_drive_test] FAIL: ", m)
		get_tree().quit(1)
