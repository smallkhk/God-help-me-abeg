extends Node3D
## Headless physics smoke test (spec §5.7 tests 1-3, 11, 12; §18).
##
## Run:  godot --headless --path . res://tests/vehicle_physics/physics_smoke_test.tscn
##
## Drives the player car forward on flat ground for a fixed number of physics
## ticks and asserts: no NaN/inf in state, the car stays upright, it does not
## sink through the floor, and it actually accelerates. Exits with code 0 on
## pass, 1 on failure, so it can gate CI. This is a sanity net, NOT a substitute
## for the in-editor driving-feel tests.

@export var ticks_to_run: int = 1200   # 20 s at 60 Hz

var _car: VehicleController
var _tick := 0
var _max_speed := 0.0
var _failures: Array[String] = []


func _ready() -> void:
	_car = $PlayerCar as VehicleController
	if _car == null:
		_fail("PlayerCar missing or wrong type")
		_done()


func _physics_process(_delta: float) -> void:
	if _car == null:
		return
	# Full throttle, straight.
	_car.set_driver_input(1.0, 0.0, 0.0, false)

	var p := _car.global_position
	var v := _car.linear_velocity
	if not _finite(p) or not _finite(v):
		_fail("non-finite state at tick %d" % _tick)
		_done()
		return
	if p.y < -5.0:
		_fail("car fell through floor at tick %d (y=%.2f)" % [_tick, p.y])
		_done()
		return
	var up_dot := _car.global_transform.basis.y.dot(Vector3.UP)
	if up_dot < 0.3:
		_fail("car flipped at tick %d (up_dot=%.2f)" % [_tick, up_dot])
		_done()
		return

	_max_speed = maxf(_max_speed, v.length())
	_tick += 1
	if _tick >= ticks_to_run:
		if _max_speed < 5.0:
			_fail("car never accelerated (max %.2f m/s)" % _max_speed)
		_done()


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _done() -> void:
	if _failures.is_empty():
		print("[physics_smoke_test] PASS  (max speed %.1f m/s / %.0f km/h over %d ticks)" % [
			_max_speed, _max_speed * 3.6, _tick])
		get_tree().quit(0)
	else:
		for m in _failures:
			printerr("[physics_smoke_test] FAIL: ", m)
		get_tree().quit(1)
