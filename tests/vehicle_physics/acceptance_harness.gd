extends Node3D
## Automated subset of the spec §5.7 acceptance tests, run headless, printing
## real measured numbers (0-100 km/h, top speed, braking distances dry vs wet,
## handbrake yaw, determinism). Produces the baseline figures for
## docs/physics_baselines.md. Exits 0 if all sanity checks pass, 1 otherwise.
##
## Run: godot --headless --path . res://tests/vehicle_physics/acceptance_harness.tscn

const KMH := 3.6
const STEP := 1.0 / 60.0

var _car: VehicleController
var _driver: Node
var _spawn := Transform3D(Basis(), Vector3(0, 0.7, 0))

enum P { ACCEL, BRAKE_DRY, BRAKE_WET, HANDBRAKE, DETERMINISM, DONE }
var _phase: int = P.ACCEL
var _t := 0.0
var _phase_t := 0.0
var _failures: Array[String] = []

# measurements
var _t_0_100 := -1.0
var _top_speed := 0.0
var _brake_start_pos := Vector3.ZERO
var _brake_start_speed := 0.0
var _dist_dry := -1.0
var _dist_wet := -1.0
var _max_yaw := 0.0
var _top_gear := 0
var _top_rpm := 0.0
var _det_samples: Array = []
var _det_run := 0
var _det_first: Array = []


func _ready() -> void:
	_car = $PlayerCar as VehicleController
	_driver = $PlayerCar/PlayerDriver
	if _driver:
		_driver.set_physics_process(false)  # we drive directly
	_reset()


func _reset() -> void:
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
	_car.global_transform = _spawn
	_car.wetness = 0.0
	_car.reset_state()
	_phase_t = 0.0


func _physics_process(_delta: float) -> void:
	_t += STEP
	_phase_t += STEP
	var speed := _car.linear_velocity.length()
	if speed > _top_speed:
		_top_speed = speed
		_top_gear = _car.transmission.gear
		_top_rpm = _car.transmission.engine_rpm

	match _phase:
		P.ACCEL:
			_car.set_driver_input(1.0, 0.0, 0.0, false)
			if _t_0_100 < 0.0 and speed * KMH >= 100.0:
				_t_0_100 = _phase_t
			# Telemetry once per second so the accel curve / gearing is visible.
			if int(_phase_t) != int(_phase_t - STEP):
				var a_exp := (_car.dbg_long_force - _car.dbg_drag_force) / _car.mass
				var a_act := (speed - _last_speed) / 1.0
				print("  accel t=%2ds  %6.1f km/h  gear %d  long=%.0fN drag=%.0fN  a_exp=%.2f a_act=%.2f  y=%.2f grnd=%d" % [
					int(_phase_t), speed * KMH, _car.transmission.gear,
					_car.dbg_long_force, _car.dbg_drag_force, a_exp, a_act,
					_car.global_position.y, _car.wheels_on_ground])
				_last_speed = speed
			# Fixed 45 s pull; the true top speed is the running max.
			if _phase_t > 45.0:
				_next(P.BRAKE_DRY)
		P.BRAKE_DRY:
			_brake_phase(false)
		P.BRAKE_WET:
			_brake_phase(true)
		P.HANDBRAKE:
			# get to ~50 km/h then handbrake + steer
			if _phase_t < 6.0 and speed * KMH < 50.0:
				_car.set_driver_input(1.0, 0.0, 0.0, false)
			else:
				_car.set_driver_input(0.3, 0.0, 1.0, true)
				_max_yaw = maxf(_max_yaw, absf(_car.angular_velocity.y))
				if _phase_t > 10.0:
					_next(P.DETERMINISM)
		P.DETERMINISM:
			# Two identical 2 s full-throttle runs; positions must match exactly.
			_car.set_driver_input(1.0, 0.0, 0.0, false)
			if _phase_t <= 2.0:
				(_det_first if _det_run == 0 else _det_samples).append(_car.global_position)
			else:
				if _det_run == 0:
					_det_run = 1
					_reset()
				else:
					_finish()
		P.DONE:
			pass


var _last_speed := 0.0
func _accel_flat(speed: float) -> bool:
	var flat := absf(speed - _last_speed) < 0.002
	_last_speed = speed
	return flat


func _brake_phase(wet: bool) -> void:
	var speed := _car.linear_velocity.length()
	var target := 50.0 / KMH
	if _brake_start_speed == 0.0:
		# spin up to target first
		if speed < target:
			_car.set_driver_input(1.0, 0.0, 0.0, false)
			return
		_car.wetness = 1.0 if wet else 0.0
		_brake_start_speed = speed
		_brake_start_pos = _car.global_position
	# braking
	_car.set_driver_input(0.0, 1.0, 0.0, false)
	if speed < 0.5:
		var dist := _car.global_position.distance_to(_brake_start_pos)
		if wet:
			_dist_wet = dist
			_brake_start_speed = 0.0
			_next(P.HANDBRAKE)
		else:
			_dist_dry = dist
			_brake_start_speed = 0.0
			_next(P.BRAKE_WET)
	elif _phase_t > 30.0:
		_fail("brake phase (wet=%s) did not stop in 30 s" % wet)
		_next(P.BRAKE_WET if not wet else P.HANDBRAKE)


func _next(p: int) -> void:
	_phase = p
	_reset()


func _fail(m: String) -> void:
	_failures.append(m)


func _finish() -> void:
	_phase = P.DONE
	# Determinism check
	var det_ok := _det_first.size() == _det_samples.size() and _det_first.size() > 0
	if det_ok:
		for i in _det_first.size():
			if _det_first[i].distance_to(_det_samples[i]) > 0.001:
				det_ok = false
				break

	# Sanity assertions
	if _t_0_100 < 0.0:
		_fail("never reached 100 km/h")
	if _dist_dry < 0.0:
		_fail("no dry braking distance")
	if _dist_wet >= 0.0 and _dist_dry >= 0.0 and _dist_wet <= _dist_dry:
		_fail("wet braking (%.1f m) not longer than dry (%.1f m)" % [_dist_wet, _dist_dry])
	if _max_yaw > 6.0:
		_fail("handbrake yaw too violent (%.2f rad/s) — looks like an auto-spin" % _max_yaw)
	if not det_ok:
		_fail("physics not deterministic across identical runs")

	print("\n========== ACCEPTANCE RESULTS (camry_01) ==========")
	print("0-100 km/h time      : %s" % ("%.2f s" % _t_0_100 if _t_0_100 > 0 else "n/a"))
	print("Top speed (observed) : %.1f km/h  (gear %d @ %.0f rpm)" % [_top_speed * KMH, _top_gear, _top_rpm])
	print("Braking 50->0 dry    : %.1f m" % _dist_dry)
	print("Braking 50->0 wet    : %.1f m" % _dist_wet)
	print("Handbrake peak yaw   : %.2f rad/s" % _max_yaw)
	print("Deterministic        : %s" % ("yes" if det_ok else "NO"))
	print("===================================================\n")

	if _failures.is_empty():
		print("[acceptance_harness] PASS")
		get_tree().quit(0)
	else:
		for m in _failures:
			printerr("[acceptance_harness] FAIL: ", m)
		get_tree().quit(1)
