class_name Transmission
extends RefCounted
## Automatic transmission model (spec §5.5).
##
## Owned by VehicleController. Maps wheel speed <-> engine RPM through the
## current gear + final drive, and decides automatic shifts based on RPM,
## throttle and a cooldown that prevents rapid gear hunting. Designed so a
## manual mode can be layered on later (set `automatic = false` and drive
## shift_up()/shift_down() from input).

var data: VehicleData

var gear: int = 0            # -1 reverse, 0 neutral, 1..N forward
var engine_rpm: float = 900.0
var automatic: bool = true

var _shift_timer: float = 0.0


func _init(vehicle_data: VehicleData) -> void:
	data = vehicle_data
	engine_rpm = data.idle_rpm


## Converts forward ground speed (m/s) into engine RPM for the current gear.
func rpm_for_speed(forward_speed: float) -> float:
	var ratio := data.get_gear_ratio(gear)
	if is_zero_approx(ratio):
		return data.idle_rpm
	# wheel angular velocity (rad/s) = speed / radius; wheel rev/s = that / 2pi.
	var wheel_rps := absf(forward_speed) / (TAU * data.wheel_radius)
	var rpm := wheel_rps * 60.0 * absf(ratio) * data.final_drive
	return clampf(rpm, data.idle_rpm, data.max_rpm)


## Normalised drive-force multiplier from the engine's torque characteristic.
## Peaks around peak_power_rpm and tapers toward max_rpm, so acceleration eases
## as the car approaches top speed (spec §5.2).
func torque_factor() -> float:
	var r := engine_rpm
	if r <= data.peak_power_rpm:
		# Rising region: low-end torque is decent, climbs to peak.
		var t := inverse_lerp(data.idle_rpm, data.peak_power_rpm, r)
		return lerpf(0.65, 1.0, clampf(t, 0.0, 1.0))
	else:
		# Falling region past peak power.
		var t := inverse_lerp(data.peak_power_rpm, data.max_rpm, r)
		return lerpf(1.0, 0.55, clampf(t, 0.0, 1.0))


## Advance the transmission one physics step.
## throttle: 0..1, brake: 0..1, forward_speed: m/s (sign = travel direction).
func update(delta: float, throttle: float, brake: float, forward_speed: float, wants_reverse: bool) -> void:
	_shift_timer = maxf(0.0, _shift_timer - delta)

	var nearly_stopped := absf(forward_speed) < 1.0

	if automatic:
		_auto_select(throttle, brake, forward_speed, wants_reverse, nearly_stopped)

	# Engine RPM follows the gear mapping, but idles when in neutral / stopped.
	var target_rpm: float
	if gear == 0 or (nearly_stopped and throttle < 0.05):
		target_rpm = data.idle_rpm + throttle * (data.peak_power_rpm - data.idle_rpm) * 0.5
	else:
		target_rpm = rpm_for_speed(forward_speed)
		# Blend in throttle so revs lift under load even before speed catches up.
		target_rpm = lerpf(target_rpm, maxf(target_rpm, data.peak_power_rpm), throttle * 0.15)
	engine_rpm = lerpf(engine_rpm, clampf(target_rpm, data.idle_rpm, data.max_rpm), 1.0 - exp(-delta * 8.0))


func _auto_select(throttle: float, brake: float, forward_speed: float, wants_reverse: bool, nearly_stopped: bool) -> void:
	# Reverse / launch handling: only change direction when nearly stopped so we
	# never slam from drive to reverse at speed (spec §5.5 stable stop/launch).
	if nearly_stopped:
		if wants_reverse and brake > 0.1:
			gear = -1
			return
		if gear == -1 and not wants_reverse:
			gear = 1 if throttle > 0.05 else 0
			return
		if gear == 0 and throttle > 0.05 and not wants_reverse:
			gear = 1
			return

	if gear <= 0:
		return  # neutral/reverse handled above

	if _shift_timer > 0.0:
		return

	var up_rpm := data.max_rpm * data.upshift_rpm_fraction
	var down_rpm := data.max_rpm * data.downshift_rpm_fraction

	# Upshift when revs are high and we have gears left.
	if engine_rpm >= up_rpm and gear < data.top_gear():
		gear += 1
		_shift_timer = data.shift_cooldown
		return

	# Downshift when revs drop, but not into a gear that would instantly redline.
	if gear > 1:
		var rpm_after_down := _rpm_in_gear(forward_speed, gear - 1)
		if engine_rpm <= down_rpm and rpm_after_down < up_rpm:
			gear -= 1
			_shift_timer = data.shift_cooldown


func _rpm_in_gear(forward_speed: float, g: int) -> float:
	var ratio := data.get_gear_ratio(g)
	if is_zero_approx(ratio):
		return data.idle_rpm
	var wheel_rps := absf(forward_speed) / (TAU * data.wheel_radius)
	return clampf(wheel_rps * 60.0 * absf(ratio) * data.final_drive, data.idle_rpm, data.max_rpm)


func shift_up() -> void:
	if gear < data.top_gear():
		gear += 1
		_shift_timer = data.shift_cooldown


func shift_down() -> void:
	if gear > -1:
		gear -= 1
		_shift_timer = data.shift_cooldown


func gear_label() -> String:
	match gear:
		-1: return "R"
		0: return "N"
		_: return str(gear)
	return "N"
