extends Node3D
## Validates the Bridge Test Sprint flow (spec §11): the race starts, the car is
## driven through all checkpoints in order, the race finishes, a time is recorded
## and the best-time save round-trips. Runs headless by driving the car directly
## (bypassing the human-input driver) and feeding the RaceManager a synthetic
## "accelerate" press to trigger the countdown.
## Run: godot --headless --path . res://tests/race_flow/race_flow_test.tscn

const STEP := 1.0 / 60.0

var _bridge: Node3D
var _car: VehicleController
var _race: Node
var _samples: Array = []
var _checkpoints: Array = []
var _t := 0.0
var _started := false
var _failures: Array[String] = []
var _done := false
var _seen_states := {}


func _ready() -> void:
	# Clear any prior best time so the "new best" path is deterministic.
	var data := SaveManager.load_data()
	data["best_times"] = {}
	SaveManager.save_data(data)

	_bridge = $LagosBridge
	_car = _bridge.get_node("PlayerCar") as VehicleController
	var driver := _bridge.get_node_or_null("PlayerCar/PlayerDriver")
	if driver:
		driver.set_physics_process(false)
	_race = _bridge.get_node("RaceManager")
	var chunk := (_bridge.get_node("MapBuilder") as MapBuilder).get_chunk()
	_samples = chunk["road"]["samples"]
	_checkpoints = chunk["checkpoints"]
	print("[race_flow_test] %d checkpoints to clear" % _checkpoints.size())


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_t += STEP
	_seen_states[_race._state] = true

	# Kick off the countdown once (same entry point the accelerate key triggers).
	if not _started and _t > 0.5:
		_started = true
		_race._start_countdown()

	# Follow the road centerline (keeps the car on the curving deck); checkpoints
	# trigger as it passes through their gates. Moderate throttle for control.
	_car.set_driver_input(0.8, 0.0, _steer(), false)

	# Win condition / timeout.
	if _race._state == _race.State.FINISHED:
		_finish(true)
	elif _t > 320.0:
		_finish(false)


func _steer() -> float:
	var pos := _car.global_position
	var best_i := 0
	var best_d := INF
	for i in _samples.size():
		var s = _samples[i]
		var d: float = Vector2(s["x"] - pos.x, s["z"] - pos.z).length_squared()
		if d < best_d:
			best_d = d
			best_i = i
	var ahead = _samples[mini(best_i + 4, _samples.size() - 1)]
	var ah: float = ahead["heading_rad"]
	var lane := Vector3(cos(ah), 0, -sin(ah)) * MapLoader.LANE_OFFSET
	var to_t := Vector3(ahead["x"] + lane.x - pos.x, 0, ahead["z"] + lane.z - pos.z)
	var fwd := _car.global_transform.basis.z
	var right := _car.global_transform.basis.x
	return clampf(atan2(to_t.dot(right), maxf(to_t.dot(fwd), 0.1)) * 1.4, -1.0, 1.0)


func _finish(finished: bool) -> void:
	_done = true
	print("[race_flow_test] car pos=%s speed=%.1f" % [_car.global_position, _car.linear_velocity.length()])
	var best := SaveManager.get_best_time("bridge_test_sprint")
	print("[race_flow_test] final state=%d  next=%d/%d  best_saved=%.3f  t=%.1fs" % [
		_race._state, _race._next, _checkpoints.size(), best, _t])

	if not finished:
		_fail("race did not reach FINISHED within 320 s (stuck at checkpoint %d)" % _race._next)
	if not _seen_states.has(_race.State.COUNTDOWN):
		_fail("countdown state was never entered")
	if not _seen_states.has(_race.State.RUNNING):
		_fail("running state was never entered")
	if finished and best <= 0.0:
		_fail("finished but no best time was saved")

	# Verify the save round-trips from disk.
	if finished and best > 0.0:
		var reloaded := SaveManager.get_best_time("bridge_test_sprint")
		if absf(reloaded - best) > 0.001:
			_fail("best time did not round-trip through save file")

	if _failures.is_empty():
		print("[race_flow_test] PASS")
		get_tree().quit(0)
	else:
		for m in _failures:
			printerr("[race_flow_test] FAIL: ", m)
		get_tree().quit(1)


func _fail(m: String) -> void:
	_failures.append(m)
