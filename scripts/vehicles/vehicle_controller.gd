class_name VehicleController
extends RigidBody3D
## Custom raycast vehicle controller (spec §5.1–§5.3).
##
## A RigidBody3D with four raycast "wheels". Suspension is a spring+damper along
## each ray; tyre forces are a slip-based lateral model plus a longitudinal
## drive/brake force, clamped together by a friction circle so combined cornering
## and braking can exceed grip and the car slides (spec §5.2). Weight transfer is
## emergent: body pitch/roll changes per-corner spring compression, which changes
## normal load, which changes available grip — no faked position/rotation.
##
## Conventions (spec §5.3): forward is +Z (local), up is +Y, right is +X.
## All forces run through _physics_process + apply_force. Visual wheel meshes are
## positioned from physics each step; they never drive movement.
##
## Scene contract: this node has four Marker3D children named WheelFL, WheelFR,
## WheelRL, WheelRR (suspension anchor points), an optional visual mesh child per
## wheel named <marker>_mesh, and a CollisionShape3D for the body.

@export var data: VehicleData
## Marks the human-driven car. When true, _ready swaps in the garage-selected
## car's data (spec §6.2/§13). Traffic/AI cars leave this false and keep the data
## they were assigned.
@export var is_player: bool = false
## Road wetness 0 (dry) .. 1 (fully wet). Rain sets this (spec §4.2, §5.2).
@export_range(0.0, 1.0) var wetness: float = 0.0
## Assist preset (spec §5.6). All presets share this same physics.
@export_enum("Assisted", "Standard", "Expert") var assist_mode: int = 1

class Wheel:
	var marker: Marker3D
	var mesh: Node3D
	var model_pivot: Node3D = null     # wheel node inside the imported car model
	var model_rest: Basis = Basis()     # its rest orientation in car space
	var is_front: bool
	var is_driven: bool
	var is_rear: bool
	# Per-step telemetry (read by the debug overlay).
	var grounded: bool = false
	var compression: float = 0.0
	var normal_load: float = 0.0
	var slip_angle: float = 0.0
	var contact_point: Vector3 = Vector3.ZERO
	var spin_angle: float = 0.0  # visual wheel roll
	var omega: float = 0.0       # wheel angular speed (rad/s), drives slip ratio
	var slip_ratio: float = 0.0
	var dbg_fx: float = 0.0          # last tyre forces (N), for telemetry
	var dbg_fy: float = 0.0

var wheels: Array[Wheel] = []

# --- Driver input (0..1 / -1..1), set each frame from InputMap. ---
var throttle_input: float = 0.0
var brake_input: float = 0.0
var steer_input: float = 0.0
var handbrake_input: bool = false

# --- State exposed for HUD / debug (spec §7). ---
var transmission: Transmission
var forward_speed: float = 0.0        # m/s along local +Z
var lateral_speed: float = 0.0        # m/s along local +X
var current_steer_angle: float = 0.0  # radians, smoothed
var wheels_on_ground: int = 0

var _com_global: Vector3 = Vector3.ZERO

# Debug force accounting (summed per physics step, read by test harnesses).
var dbg_long_force: float = 0.0
var dbg_drag_force: float = 0.0

const INPUT_SMOOTH := 10.0


# --- nitro ---
var nitro_input := false
var nitro_amount := 1.0          # 0..1 tank
var nitro_active := false
var nitro_capacity_s := 2.5      # seconds of boost on a full tank
var nitro_power := 0.55          # extra drive force fraction while boosting

## Player car hit something hard: world point + speed change (m/s). CarFX
## throws sparks, the chase camera jolts.
signal impact(point: Vector3, strength: float)

# --- knocks (PIT / side slam): the player's hits unsettle rivals ---
var knocked_t := 0.0             # > 0: off balance, no anti-spin, loose rear
var spun_out := false            # set when a knock leaves the car sideways (RaceFlair reads + clears)
var _knock_beta := false
var _knock_k := 0.0              # 0..1 how hard the last knock was
var _prev_vel := Vector3.ZERO
var _knock_cd := {}              # rival instance id -> time of last knock
var _impact_t := -9.0


## Player upgrades (garage): engine = more drive force, tyres = more grip,
## nitro = bigger tank + stronger boost. Works on a copy of the shared data.
func _apply_upgrades(g: Node) -> void:
	var id: StringName = g.selected_car_id
	var e: int = g.upgrade_level(id, "engine")
	var t: int = g.upgrade_level(id, "tyres")
	var n: int = g.upgrade_level(id, "nitro")
	data = data.duplicate()
	data.max_drive_force *= 1.0 + 0.09 * e
	data.max_rpm += 250.0 * e
	data.lateral_grip_front *= 1.0 + 0.05 * t
	data.lateral_grip_rear *= 1.0 + 0.05 * t
	data.longitudinal_grip *= 1.0 + 0.05 * t
	nitro_capacity_s = 2.5 + 1.5 * n
	nitro_power = 0.55 + 0.15 * n
	# brakes + suspension upgrades
	var b: int = g.upgrade_level(id, "brakes")
	var su: int = g.upgrade_level(id, "suspension")
	data.brake_force *= 1.0 + 0.1 * b
	data.suspension_stiffness *= 1.0 + 0.06 * su
	data.anti_roll_stiffness *= 1.0 + 0.15 * su
	# TUNING (garage sliders)
	var tn: Dictionary = g.tuning(String(id))
	var gb: float = tn["grip_balance"]
	data.lateral_grip_front *= 1.0 - 0.06 * gb
	data.lateral_grip_rear *= 1.0 + 0.06 * gb
	data.suspension_stiffness *= tn["stiffness"]
	data.suspension_damping *= sqrt(tn["stiffness"])
	brake_bias = tn["brake_bias"]
	data.steer_rate *= tn["steer_speed"]


func _ready() -> void:
	add_to_group(&"vehicles")
	# The player car uses whatever was picked in the garage (if the Game autoload
	# is present and that car's data exists). AI cars keep their assigned data.
	if is_player:
		var g := get_node_or_null("/root/Game")
		if g and CarDatabase.exists(g.selected_car_id):
			data = CarDatabase.get_data(g.selected_car_id)
			_apply_upgrades(g)

	if data == null:
		push_warning("VehicleController has no VehicleData assigned; using defaults.")
		data = VehicleData.new()

	mass = data.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, data.center_of_mass_y, data.center_of_mass_z)
	# Driving-game feel: stop the body from going to sleep, and REPLACE (not
	# combine with) the project's default damping so the tyre + aero model is the
	# only source of resistance. Leaving the default combine mode silently adds
	# ~0.1 linear damp, which saps drive force and caps top speed far too low.
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.2
	# Continuous CD is intentionally OFF: the wheels are raycasts (which never
	# tunnel), and sweeping the chassis against a large concave road trimesh
	# every step is extremely expensive. Fixed-tick discrete collision is fine at
	# the speeds involved.
	continuous_cd = false

	transmission = Transmission.new(data)
	_collect_wheels()
	if handling_v2 and not wheels.is_empty():
		# real CoM height above the tyre contact plane (the data's -0.4 put it at
		# road level, so braking / cornering moved no weight between the tyres)
		var sag := mass * 9.81 / float(wheels.size()) / maxf(data.suspension_stiffness, 1.0)
		var contact_y := wheels[0].marker.position.y - (data.suspension_rest_length - sag) - data.wheel_radius
		var cg := data.cg_height_m if data.cg_height_m > 0.0 else 0.52
		center_of_mass = Vector3(0.0, contact_y + cg, data.center_of_mass_z)
	_mount_model()


## Swaps the placeholder box for the car's .glb model (spec §6.2). Cosmetic only;
## physics is untouched. Alignment (offset/rotation/scale) comes from VehicleData
## so each model is fitted without code.
var brake_bias := 0.6   # front share of brake force (garage TUNING)


## Global handling tune (owner feedback: too slidey, too fast)
const GRIP_BONUS := 1.3
const ARB_SCALE := 3.0   # flatter cornering (less body lean)
const SPEED_SCALE := 0.75

## Handling v2 (simcade), ON in the game. Island two-lap test with the rival
## AI: PASS, 4 hard hits, best lap 199 s (v1: 6 hits, 192 s). The lab and the
## island test take V2=0 to run the old handling (tests/vehicle_physics/handling_lab.tscn, env V2=1). Replaces the
## quick fixes above with physically based behaviour:
## - street-tyre grip: the car data's grip x V2_LAT_MU / V2_LONG_MU (keeps each
##   car's relative grip) instead of +30 % for everyone -> ~1 g braking/cornering
## - no fixed "glue" downforce: only the car's own downforce_coefficient
## - steering lock follows the tyres: enough angle to reach the grip limit at
##   any speed (kinematic angle for the limit + the front tyre's peak slip),
##   instead of ~4 degrees at speed
## - stability assist steps back during a handbrake slide (drift window) and
##   when the driver countersteers; traction control off in the drift window
static var handling_v2 := true
const V2_LAT_MU := 0.82
const V2_LONG_MU := 0.90
const V2_DRIFT_WINDOW := 1.4
const V2_SPEED_SCALE := 0.85
var _drift_t := 0.0


func _mount_model() -> void:
	if data.model_scene == null:
		return
	var m := data.model_scene.instantiate()
	m.name = "CarModel"
	add_child(m)
	if m is Node3D:
		m.position = data.model_offset
		m.rotation = Vector3(
			deg_to_rad(data.model_rotation_deg.x),
			deg_to_rad(data.model_rotation_deg.y),
			deg_to_rad(data.model_rotation_deg.z))
		m.scale = Vector3.ONE * data.model_scale
		# car bodies live on render layer 2: road decals (contact shadows) and the
		# car's reflection probe only see layer 1
		for vi in m.find_children("*", "VisualInstance3D", true, false):
			(vi as VisualInstance3D).layers = 2
		var g := get_node_or_null("/root/Game")
		_finish_materials(m, float(g.call("window_tint", String(data.vehicle_id))) if g else 0.55)
		if g and is_player:
			var col = g.call("car_color", String(data.vehicle_id))
			if col != null:
				paint_model(m, col)
	if m is Node3D:
		_auto_ground(m as Node3D)
	if data.hide_placeholder_when_model:
		for n in ["Body", "Cabin", "WheelFL_mesh", "WheelFR_mesh", "WheelRL_mesh", "WheelRR_mesh"]:
			var node := get_node_or_null(NodePath(n)) as Node3D
			if node:
				node.visible = false


func _collect_wheels() -> void:
	wheels.clear()
	var defs := [
		{"name": "WheelFL", "front": true, "rear": false},
		{"name": "WheelFR", "front": true, "rear": false},
		{"name": "WheelRL", "front": false, "rear": true},
		{"name": "WheelRR", "front": false, "rear": true},
	]
	var dt := data.drivetrain
	for d in defs:
		var marker := get_node_or_null(NodePath(d["name"])) as Marker3D
		if marker == null:
			push_warning("VehicleController missing wheel marker: %s" % d["name"])
			continue
		var w := Wheel.new()
		w.marker = marker
		w.mesh = get_node_or_null(NodePath(str(d["name"]) + "_mesh")) as Node3D
		w.is_front = d["front"]
		w.is_rear = d["rear"]
		match dt:
			VehicleData.Drivetrain.FWD: w.is_driven = w.is_front
			VehicleData.Drivetrain.RWD: w.is_driven = w.is_rear
			_: w.is_driven = true
		wheels.append(w)


## Fully reset the controller's internal state to a clean standstill. Callers
## that teleport the body (spawn, restart, deterministic tests) should also zero
## linear/angular velocity and set the transform themselves.
func reset_state() -> void:
	nitro_amount = 1.0
	nitro_active = false
	nitro_input = false
	current_steer_angle = 0.0
	forward_speed = 0.0
	lateral_speed = 0.0
	throttle_input = 0.0
	brake_input = 0.0
	steer_input = 0.0
	handbrake_input = false
	if transmission:
		transmission.reset()
	for w in wheels:
		w.spin_angle = 0.0
		w.slip_angle = 0.0
		w.normal_load = 0.0
		w.grounded = false


var steer_lock := 0.6       # current full-lock angle (rad), speed dependent
var _legacy_lock := 0.6


## AI drivers were tuned on the old steering lock: give them the same wheel
## angle for the same command, whatever the current lock is.
func ai_steer(frac: float) -> float:
	return clampf(frac * _legacy_lock / maxf(steer_lock, 0.001), -1.0, 1.0)


func set_driver_input(throttle: float, brake: float, steer: float, handbrake: bool) -> void:
	throttle_input = clampf(throttle, 0.0, 1.0)
	brake_input = clampf(brake, 0.0, 1.0)
	steer_input = clampf(steer, -1.0, 1.0)
	handbrake_input = handbrake


static var prof_us := 0      # controller cost, summed (handling lab)
static var prof_steps := 0
var _last_good := Transform3D()
var _nan_logged := false


func _physics_process(delta: float) -> void:
	# safety net: a physics blow-up (NaN / infinite state) would otherwise fling
	# the car out of the world and flood every system that reads its position
	if not (global_transform.origin.is_finite() and linear_velocity.is_finite() and angular_velocity.is_finite()):
		if not _nan_logged:
			_nan_logged = true
			push_warning("VehicleController: invalid physics state on %s, restored" % name)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		global_transform = _last_good
		return
	_last_good = global_transform
	var _t0 := Time.get_ticks_usec()
	var up := global_transform.basis.y
	var fwd := global_transform.basis.z
	var right := global_transform.basis.x
	# Global centre of mass: force offsets and point velocities are relative to
	# this, not the body origin, so torque arms (weight transfer) are correct.
	_com_global = global_transform * center_of_mass

	var vel := linear_velocity
	forward_speed = vel.dot(fwd)
	lateral_speed = vel.dot(right)
	var speed := vel.length()

	_update_steering(delta, speed)

	# Nitro: drains while held with throttle, refills slowly otherwise.
	nitro_active = nitro_input and nitro_amount > 0.0 and throttle_input > 0.1 and forward_speed > 1.0
	if nitro_active:
		nitro_amount = maxf(nitro_amount - delta / nitro_capacity_s, 0.0)
	else:
		nitro_amount = minf(nitro_amount + delta * 0.02, 1.0)   # slow trickle: style (drift, near miss, overtake) earns the rest

	# Driven-wheel count for splitting drive force.
	var driven_count := 0
	for w in wheels:
		if w.is_driven:
			driven_count += 1
	driven_count = maxi(driven_count, 1)

	# Transmission: wants_reverse when the brake is held while stopped/rolling back.
	var wants_reverse := brake_input > 0.1 and forward_speed < 0.5
	transmission.update(delta, throttle_input, brake_input, forward_speed, wants_reverse)

	var grip_scale := lerpf(1.0, data.wet_grip_multiplier, wetness)
	wheels_on_ground = 0
	dbg_long_force = 0.0

	# Per-wheel suspension first pass to know compressions (for anti-roll).
	var hit_info := {}
	for i in wheels.size():
		hit_info[i] = _cast_wheel(wheels[i], up)

	for i in wheels.size():
		var w: Wheel = wheels[i]
		var info = hit_info[i]
		if not info["grounded"]:
			w.grounded = false
			w.normal_load = 0.0
			w.slip_angle = 0.0
			w.omega *= 0.99
			continue

		w.grounded = true
		wheels_on_ground += 1
		var contact: Vector3 = info["point"]
		w.contact_point = contact

		# --- Suspension (spring + damper + anti-roll) ---
		var compression: float = info["compression"]
		w.compression = compression
		var offset := contact - _com_global

		# Compression velocity = how fast this corner is being pushed up.
		var point_vel := _velocity_at(offset)
		var compress_speed := -point_vel.dot(up)
		var spring := data.suspension_stiffness * compression
		var damp := data.suspension_damping * compress_speed

		# Anti-roll: couple left/right partner.
		var partner_i := _partner_index(i)
		var anti := 0.0
		if partner_i >= 0 and hit_info[partner_i]["grounded"]:
			anti = data.anti_roll_stiffness * ARB_SCALE * (compression - hit_info[partner_i]["compression"])

		var susp_mag := maxf(0.0, spring + damp + anti)
		w.normal_load = susp_mag
		apply_force(up * susp_mag, offset)

		# --- Tyre forces in the ground plane ---
		_apply_tyre_force(w, offset, up, driven_count, grip_scale, delta)

	_apply_body_aero(delta, speed, fwd, up)
	if knocked_t > 0.0:
		_knocked_step(delta)
	else:
		_apply_stability_assist(delta, up)
	if is_player and contact_monitor:
		_check_hits()
	_prev_vel = linear_velocity
	if handling_v2:
		_roll_stabiliser()
	_update_wheel_visuals(delta, hit_info)
	prof_us += Time.get_ticks_usec() - _t0
	prof_steps += 1


func _update_steering(delta: float, speed: float) -> void:
	# Speed-sensitive steering (spec §5.2): big angles slow, restrained fast.
	# owner feedback: hard steer at speed swung the car ~90°. Lock falls off
	# much sooner and further with speed, and the wheel turns in slower.
	var t := clampf(speed / minf(data.steer_speed_falloff, 22.0), 0.0, 1.0)
	t = sqrt(t)
	var max_angle := lerpf(data.max_steer_angle * 0.85, data.max_steer_angle * minf(data.high_speed_steer_fraction, 0.11), t)
	_legacy_lock = max_angle
	if handling_v2:
		# angle that puts the car on its cornering limit at this speed, plus the
		# front tyre's peak slip: full lock = maximum grip, never far past it
		var a_lim := data.lateral_grip_front * V2_LAT_MU * 9.81
		var kin := atan(data.wheelbase * a_lim / maxf(speed * speed, 1.0))
		# extra turn-in for slow bends, shrinking at speed: a full tap at 150+
		# km/h is a lane change, not a slide
		var hi := clampf((speed - 15.0) / 30.0, 0.0, 1.0)
		max_angle = clampf(kin * 1.15 + data.peak_slip_angle * lerpf(1.3, 0.55, hi), data.max_steer_angle * lerpf(0.18, 0.06, hi), data.max_steer_angle * 0.85)
		if _drift_t > 0.0:
			max_angle = data.max_steer_angle * 0.85   # sliding: full lock to hold / catch it
	steer_lock = max_angle
	var target := steer_input * max_angle
	var rate := data.steer_rate * 0.65 if absf(steer_input) > 0.01 else data.steer_return_rate
	if handling_v2:
		rate *= 2.2 if _drift_t > 0.0 else lerpf(1.3, 0.45, t)   # a flick into a slide, quick but calm hands at speed
	current_steer_angle = move_toward(current_steer_angle, target, rate * delta)


func _apply_tyre_force(w: Wheel, offset: Vector3, up: Vector3, driven_count: int, grip_scale: float, _delta: float) -> void:
	# Wheel's own forward/right, including steer on the front axle.
	var fwd := global_transform.basis.z
	var right := global_transform.basis.x
	if w.is_front and not is_zero_approx(current_steer_angle):
		var rot := Basis(up, current_steer_angle)
		fwd = rot * fwd
		right = rot * right

	var point_vel := _velocity_at(offset)
	# Flatten to the ground plane.
	var plane_vel := point_vel - up * point_vel.dot(up)
	var vf := plane_vel.dot(fwd)
	var vr := plane_vel.dot(right)

	var load := w.normal_load
	if load <= 0.0:
		return

	# --- Lateral (cornering) force: slip-angle model ---
	var slip_angle := atan2(vr, absf(vf) + 0.5)
	w.slip_angle = slip_angle
	# GRIP_BONUS: planted, arcade-sim handling (no random sliding); rear a bit
	# grippier than front so the car understeers slightly instead of spinning
	var lat_grip := (data.lateral_grip_front * GRIP_BONUS if w.is_front else data.lateral_grip_rear * GRIP_BONUS * 1.08) * grip_scale
	if handling_v2:
		lat_grip = (data.lateral_grip_front if w.is_front else data.lateral_grip_rear * 1.04) * V2_LAT_MU * grip_scale
	if w.is_rear and knocked_t > 0.0:
		lat_grip *= lerpf(0.85, 0.5, _knock_k)   # knocked: the rear lets go
	if w.is_rear and handbrake_input:
		lat_grip *= data.handbrake_grip_fraction * (0.6 if handling_v2 else 1.0)
	# Load sensitivity (real tyres): grip coefficient drops as load rises, so
	# weight transfer in corners/braking actually changes the balance.
	var nominal := mass * 9.81 / 4.0
	var load_mu := clampf(1.0 - 0.12 * (load / maxf(nominal, 1.0) - 1.0), 0.75, 1.15)
	lat_grip *= load_mu
	var max_lat := lat_grip * load
	var lat_curve := _pacejka(slip_angle, data.peak_slip_angle)
	var lat_force := -lat_curve * max_lat  # opposes lateral slip

	# --- Longitudinal (drive / brake / engine-brake) force ---
	var long_grip := data.longitudinal_grip * (V2_LONG_MU if handling_v2 else 1.0) * grip_scale * clampf(1.0 - 0.12 * (load / maxf(mass * 9.81 / 4.0, 1.0) - 1.0), 0.75, 1.15)
	var max_long := long_grip * load
	# --- Longitudinal: spinning wheel + Pacejka slip-ratio tyre ------------
	# (ported from AdvancedPhysicsCar) Torques spin the wheel; the tyre force
	# comes from the slip ratio σ = (ω·r − v)/|v|, so wheelspin, lock-ups and
	# traction limits emerge instead of being scripted.
	var r := data.wheel_radius
	var inertia := 0.5 * WHEEL_MASS * r * r
	var drive_t := 0.0
	if w.is_driven and transmission.gear != 0:
		var ratio := data.get_gear_ratio(transmission.gear)
		var first := data.get_gear_ratio(1)
		var gear_mult := absf(ratio) / maxf(absf(first), 0.001)
		# reverse: holding BRAKE alone backs the car up (no gas needed)
		var pedal := maxf(throttle_input, brake_input) if transmission.gear == -1 else throttle_input
		var drive := data.max_drive_force * (V2_SPEED_SCALE if handling_v2 else SPEED_SCALE) * transmission.torque_factor() * pedal * gear_mult / driven_count
		if nitro_active and transmission.gear > 0:
			drive *= 1.0 + nitro_power
		if transmission.gear == -1:
			drive = -drive
		# Traction control: trim torque while the wheel is already spinning up
		var tc := _assist(data.traction_control_strength, 0.0, 0.5, 1.0)
		if handling_v2 and _drift_t > 0.0:
			tc = 0.0   # let the rear spin up to hold a drift
		if tc > 0.0 and w.slip_ratio * signf(drive) > (0.16 if handling_v2 else 0.12):
			drive *= 1.0 - tc * (0.35 if handling_v2 else 0.6)
		drive_t = drive * r
	var brake_t := 0.0
	if brake_input > 0.0 and not (brake_input > 0.1 and forward_speed < 0.5 and transmission.gear == -1):
		var front_bias := brake_bias if w.is_front else 1.0 - brake_bias
		# v2: brakes always able to give ~0.9 g for the car's weight (heavy SUVs'
		# data was sized like a sedan's; the old wheel solve hid that)
		var bf := maxf(data.brake_force, mass * 9.0) if handling_v2 else data.brake_force
		brake_t = bf * brake_input * front_bias * r
		# ABS: ease the brake while the tyre is locking (σ well below 0)
		var abs_s := _assist(data.abs_strength, 0.0, 0.6, 1.0)
		if w.slip_ratio < -0.12:
			brake_t *= 1.0 - abs_s * 0.7
	if handbrake_input and w.is_rear:
		brake_t += data.handbrake_force * r
	if throttle_input < 0.05 and w.is_driven and transmission.gear > 0:
		brake_t += data.engine_brake_force / driven_count * r * clampf(absf(vf) / 3.0, 0.0, 1.0)

	# Implicit (stable at 60 Hz) wheel-speed solve on the tyre's linear slope:
	#   I·dω/dt = T_drive − Fx·r,  Fx ≈ k·(ω·r − v)  with k = D·B·C / |v|
	var denom := maxf(absf(vf), 3.0)
	var k := max_long * LONG_B * LONG_C / denom
	var dt := _delta
	if handling_v2:
		# brake torque inside the same implicit solve: it opposes the spin and
		# can lock the wheel, but can't overshoot into a fake skid (applying it
		# after the solve turned even light engine braking into a near-maximum
		# tyre braking force)
		var sgn := signf(w.omega) if absf(w.omega) > 0.01 else signf(vf)
		var om := (w.omega + dt / inertia * (drive_t - sgn * brake_t + k * r * vf)) / (1.0 + dt / inertia * k * r * r)
		if brake_t > 0.0 and sgn != 0.0 and signf(om) != sgn:
			om = 0.0   # locked
		w.omega = om
	else:
		w.omega = (w.omega + dt / inertia * (drive_t + k * r * vf)) / (1.0 + dt / inertia * k * r * r)
		# brakes oppose the spin and can stop it, never reverse it
		var d_om := brake_t / inertia * dt
		w.omega = 0.0 if absf(w.omega) <= d_om else w.omega - signf(w.omega) * d_om
	# crawling with no torque: roll freely with the ground (no jitter)
	if absf(vf) < 1.0 and absf(drive_t) < 1.0 and brake_t <= 0.0:
		w.omega = vf / r
	w.slip_ratio = (w.omega * r - vf) / denom
	var long_force := max_long * _pacejka_long(w.slip_ratio)
	# Standstill hold: brakes/handbrake keep a parked car parked
	if absf(vf) < 1.0 and brake_t > 0.0:
		long_force = clampf(-vf * mass * 0.25 / maxf(dt, 0.001), -max_long, max_long)

	# Rolling resistance.
	long_force += -sign(vf) * data.rolling_resistance * minf(absf(vf), 1.0)

	# --- Friction circle: combined demand can't exceed the tyre (spec §5.2) ---
	var fx := long_force
	var fy := lat_force
	var demand := Vector2(fx / maxf(max_long, 1.0), fy / maxf(max_lat, 1.0))
	if demand.length() > 1.0:
		demand = demand.normalized()
		fx = demand.x * max_long
		fy = demand.y * max_lat

	w.dbg_fx = fx
	w.dbg_fy = fy
	var force := fwd * fx + right * fy
	apply_force(force, offset)
	dbg_long_force += fx


## Pacejka "Magic Formula" (as used by real racing sims): normalised lateral
## force for a slip angle. Peaks (=1) at `peak` rad, then falls to ~0.75 when
## sliding — progressive, catchable breakaway instead of an on/off grip switch.
const WHEEL_MASS := 20.0
const LONG_B := 11.0
const LONG_C := 1.65
const LONG_E := 0.1
## Pacejka longitudinal curve (normalised, peak 1 near σ ≈ 0.1).
func _pacejka_long(sr: float) -> float:
	var bx := LONG_B * sr
	return sin(LONG_C * atan(bx - LONG_E * (bx - atan(bx))))


const PAC_C := 1.45
const PAC_E := -0.3
func _pacejka(slip: float, peak: float) -> float:
	var b := tan(PI / (2.0 * PAC_C)) / maxf(peak, 0.01)
	var bx := b * slip
	return sin(PAC_C * atan(bx - PAC_E * (bx - atan(bx))))


## Shapes the normalized slip into a grip coefficient that rises to 1.0 at the
## peak slip angle then falls off (tyre lets go progressively, not a cliff).
func _grip_curve(norm: float) -> float:
	var a := absf(norm)
	var s := signf(norm)
	if a <= 1.0:
		return s * a
	# Past the peak: gentle decline toward a sliding plateau.
	return s * maxf(0.65, 1.0 - (a - 1.0) * 0.25)


var _air_t := 0.0
func _apply_body_aero(_delta: float, speed: float, _fwd: Vector3, up: Vector3) -> void:
	if speed < 0.1:
		return
	var dir := linear_velocity.normalized()
	var drag := data.drag_coefficient * 1.35 * speed * speed
	apply_central_force(-dir * drag)
	dbg_drag_force = drag
	# Baseline downforce so bumps/seams at top speed don't launch the car.
	var df := data.downforce_coefficient if handling_v2 else maxf(data.downforce_coefficient, 0.9)
	apply_central_force(-up * df * speed * speed)
	# Anti-launch: when wheels leave the deck at speed, kill upward velocity
	# and pull the car back down quickly.
	# Only when the car is properly airborne (not on every bump: that made
	# the car feel glued and twitchy over kerbs and rough ground).
	if wheels_on_ground == 0:
		_air_t += get_physics_process_delta_time()
	else:
		_air_t = 0.0
	if _air_t > 0.2 and speed > 20.0:
		if linear_velocity.y > 0.0:
			linear_velocity.y *= 0.95
		apply_central_force(Vector3.DOWN * mass * 4.0)


func _apply_stability_assist(_delta: float, up: Vector3) -> void:
	var s := _assist(data.stability_assist_strength, 0.0, 0.35, 0.8)
	if handling_v2:
		_drift_t = V2_DRIFT_WINDOW if handbrake_input else maxf(_drift_t - _delta, 0.0)
		if _drift_t > 0.0:
			return   # the driver is drifting on purpose
	if handling_v2:
		_v2_stability(up)
		return
	if s <= 0.0:
		return
	# Only fight yaw BEYOND what the steering asks for (a spin / snap
	# oversteer). The old version damped all yaw, so the car felt lazy into a
	# corner and then snapped when grip ran out.
	var yaw_rate := angular_velocity.dot(up)
	var wanted := forward_speed * tan(current_steer_angle) / maxf(data.wheelbase, 1.0)
	var excess := yaw_rate - wanted
	if absf(excess) < 0.15 or absf(forward_speed) < 3.0:
		return
	if handling_v2 and current_steer_angle * yaw_rate < 0.0:
		s *= 0.4   # countersteering: help, don't take over
	var correction := -(excess - signf(excess) * 0.15) * s * data.mass * 1.2
	apply_torque(up * correction)


## v2 anti-spin (simcade): yaw the steering doesn't ask for - a knock from
## traffic or a small car, a snap of oversteer - is damped hard, and a car
## sliding sideways more than ~8 deg is turned back toward where it's going.
## Off during a handbrake slide (drift window); softer when countersteering.
func _v2_stability(up: Vector3) -> void:
	if absf(forward_speed) < 3.0:
		return
	var s: float = [1.0, 0.85, 0.45][clampi(assist_mode, 0, 2)]
	var yaw_rate := angular_velocity.dot(up)
	var wanted := forward_speed * tan(current_steer_angle) / maxf(data.wheelbase, 1.0)
	# no car can turn faster than its tyres allow (yaw = a_lat / v): at speed
	# the steering "asks" for far more, which hid snap oversteer from the assist
	var lim := data.lateral_grip_front * V2_LAT_MU * 9.81 / maxf(absf(forward_speed), 1.0)
	wanted = clampf(wanted, -lim, lim)
	var excess := yaw_rate - wanted
	if current_steer_angle * yaw_rate < 0.0:
		s *= 0.5   # countersteering: help, don't take over
	var torque := 0.0
	if absf(excess) > 0.08:
		torque -= (excess - signf(excess) * 0.08) * s * mass * 4.5
	# body slip: nose pointing away from the direction of travel
	var v := linear_velocity - up * linear_velocity.dot(up)
	if v.length() > 5.0:
		var beta := atan2(v.dot(global_transform.basis.x), v.dot(global_transform.basis.z))
		if absf(beta) > 0.14:
			torque += (beta - signf(beta) * 0.14) * s * mass * 3.0
	apply_torque(up * torque)


## The player rammed another car: judge the hit from the speeds just before
## contact. A sideways shove or a hit on a rear quarter (PIT) knocks the AI car
## off balance; the push is applied at the contact point so it yaws for real.
func _check_hits() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if get_contact_count() > 0:
		# sudden change of velocity (not gravity / tyres) = a hit
		var dv := linear_velocity - _prev_vel
		dv.y = 0.0
		var hit := dv.length()
		if hit > 1.2 and now - _impact_t > 0.25:
			_impact_t = now
			var dir := -dv.normalized()          # the push came from that side
			impact.emit(global_position + dir * 1.1 + global_transform.basis.y * 0.45, hit)
	for b in get_colliding_bodies():
		var r := b as VehicleController
		if r == null or r.is_player or now - float(_knock_cd.get(r.get_instance_id(), -9.0)) < 1.2:
			continue
		var rb := r.global_transform.basis
		var rel := _prev_vel - r._prev_vel
		var lat := rel.dot(rb.x)                        # how hard we shove it sideways
		var off := (global_position - r.global_position).dot(rb.z)   # + front, - rear of it
		var closing := rel.dot((r.global_position - global_position).normalized())
		if closing < 0.6 or (absf(lat) < 0.9 and not (off < -1.0 and closing > 3.0)):
			continue
		_knock_cd[r.get_instance_id()] = now
		if now - _impact_t > 0.25:
			_impact_t = now
			impact.emit((global_position + r.global_position) * 0.5 + rb.y * 0.5, maxf(absf(lat) * 3.0, 3.0))
		r.knock(clampf(maxf(absf(lat) * 3.5, closing * 1.5), 0.0, 12.0), signf(lat) if absf(lat) > 0.5 else signf((global_position - r.global_position).dot(rb.x)) * -1.0, off)


## Hit by the player: stability control "trips" for a moment and the car
## gets a yaw kick that grows with the hit and with how far back it landed.
func knock(strength: float, side: float, off: float) -> void:
	if is_player or strength < 1.5:
		return
	var up := global_transform.basis.y
	var rb := global_transform.basis
	_knock_k = clampf((strength - 2.5) / 4.5, 0.0, 1.0)
	knocked_t = lerpf(0.6, 2.0, _knock_k)
	_knock_beta = false
	# sideways shove at the contact point (rear hit -> it rotates round its nose)
	var lever := clampf(-off, -2.0, 2.0)
	if lever < -0.3:
		_knock_k *= 0.45       # a hit on the nose turns it, the rear keeps its grip
		knocked_t = lerpf(0.6, 2.0, _knock_k)
	apply_impulse(rb.x * side * mass * minf(strength, 8.0) * 0.18, rb.z * -lever)
	# yaw: a push on the rear right swings the tail left (nose right), and so on
	var yaw := side * (1.2 + maxf(lever, 0.0) * 0.3) * lerpf(0.25, 1.4, _knock_k)
	angular_velocity += up * yaw * (-1.0 if lever >= -0.3 else 0.3)


func _knocked_step(delta: float) -> void:
	knocked_t -= delta
	var v := linear_velocity - global_transform.basis.y * linear_velocity.dot(global_transform.basis.y)
	if not _knock_beta and v.length() > 4.0:
		var beta := atan2(v.dot(global_transform.basis.x), v.dot(global_transform.basis.z))
		if absf(beta) > 0.9:
			_knock_beta = true
			spun_out = true


## v2: with the CoM at its real height a car trips easily over a kerb or a
## side hit. Real cars resist that with suspension geometry and stability
## control: normal body lean (< ~7 deg) is left alone, beyond it a strong
## restoring + damping torque about the car's long axis.
func _roll_stabiliser() -> void:
	var fwd := global_transform.basis.z
	var roll := asin(clampf(global_transform.basis.x.y, -1.0, 1.0))
	var roll_rate := angular_velocity.dot(fwd)
	var over := absf(roll) - 0.12
	var k := mass * 9.81 * 2.5
	var torque := 0.0
	if over > 0.0:
		torque -= signf(roll) * over * k      # +rotation about forward lifts the right side
	torque -= roll_rate * mass * 0.9 * (1.0 if over > 0.0 or wheels_on_ground < 4 else 0.25)
	apply_torque(fwd * torque)


## Assist strength per mode (spec §5.6): Assisted strongest, Expert weakest.
func _assist(base: float, expert: float, standard: float, assisted: float) -> float:
	match assist_mode:
		0: return base * assisted
		2: return base * expert
		_: return base * standard


func _partner_index(i: int) -> int:
	# FL<->FR (0<->1), RL<->RR (2<->3)
	match i:
		0: return 1
		1: return 0
		2: return 3
		3: return 2
	return -1


func _velocity_at(offset: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(offset)


func _cast_wheel(w: Wheel, up: Vector3) -> Dictionary:
	var from := w.marker.global_position
	var probe := data.suspension_rest_length + data.suspension_max_travel + data.wheel_radius
	var to := from - up * probe
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [get_rid()]
	params.collision_mask = collision_mask
	params.hit_back_faces = true  # defensive: road trimesh may be hit from behind
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return {"grounded": false, "compression": 0.0}
	var dist: float = from.distance_to(hit["position"])
	# Spring rest sits at rest_length; compression is how far above rest we are.
	var compression := (data.suspension_rest_length + data.wheel_radius) - dist
	compression = clampf(compression, 0.0, data.suspension_rest_length + data.suspension_max_travel)
	return {
		"grounded": true,
		"compression": compression,
		"point": hit["position"],
		"normal": hit["normal"],
		"distance": dist,
	}


var _pivots_bound := false

## Finds the wheel nodes inside an imported car model (e.g. wheel_fl,
## WheelFrontL) and pairs each with the nearest physics wheel so they spin/steer.
func _bind_model_wheels() -> void:
	_pivots_bound = true
	var m := get_node_or_null("CarModel")
	if m == null:
		return
	var cands: Array[Node3D] = []
	for n in m.find_children("*", "Node3D", true, false):
		var nm := String(n.name).to_lower().replace("_", "").replace("-", "").replace(" ", "")
		var axle := nm.contains("front") or nm.contains("rear") or nm.contains("back") \
			or nm.ends_with("fl") or nm.ends_with("fr") or nm.ends_with("rl") or nm.ends_with("rr")
		var side := nm.contains("left") or nm.contains("right") or nm.ends_with("l") or nm.ends_with("r")
		var is_pivot := nm.begins_with("wheel") and axle and side \
			and not nm.contains("brake") and not nm.contains("rim") \
			and (n.get_child_count() > 0 or n is MeshInstance3D)
		if is_pivot:
			cands.append(n as Node3D)
	if cands.size() < 4:
		return
	var inv := global_transform.affine_inverse()
	for w in wheels:
		var best: Node3D = null; var bd := INF
		for c in cands:
			var d := (inv * c.global_position).distance_to(w.marker.position)
			if d < bd:
				bd = d; best = c
		if best and bd < 1.2:
			w.model_pivot = best
			w.model_rest = global_transform.basis.inverse() * best.global_transform.basis
			cands.erase(best)


func _update_wheel_visuals(delta: float, hit_info: Dictionary) -> void:
	if not _pivots_bound:
		_bind_model_wheels()
	for i in wheels.size():
		var w: Wheel = wheels[i]
		if w.model_pivot:
			# model wheels roll with road speed (spin_angle used to never advance here)
			w.spin_angle = wrapf(w.spin_angle + w.omega * delta, -TAU, TAU)
			var sa := w.spin_angle
			var st := current_steer_angle if w.is_front else 0.0
			var gb := global_transform.basis * Basis(Vector3.UP, st) * Basis(Vector3.RIGHT, sa) * w.model_rest
			w.model_pivot.global_transform = Transform3D(gb, w.model_pivot.global_position)
		if w.mesh == null:
			continue
		var up := global_transform.basis.y
		# Vertical position follows suspension.
		var drop := data.suspension_rest_length
		if w.grounded:
			var info = hit_info[i]
			drop = clampf(info["distance"] - data.wheel_radius, 0.0, data.suspension_rest_length + data.suspension_max_travel)
		var local_pos := w.marker.position - Vector3(0, drop, 0)
		w.mesh.position = local_pos
		# Spin from forward speed; steer on front wheels.
		w.spin_angle = wrapf(w.spin_angle + w.omega * delta, -TAU, TAU)
		var steer := current_steer_angle if w.is_front else 0.0
		w.mesh.rotation = Vector3(w.spin_angle, steer, 0.0)


## Tint a car model's paint (multiplies the texture, so white/silver bodies take
## the colour fully; tyres/glass stay dark). Shared with the garage preview.
## Which surfaces are body paint. Named paint/body materials win; otherwise the
## biggest non-dark, opaque surface that isn't glass / interior / trim / tyres.
## Cars with one texture for everything (AI models) get none: their windows
## are in the same texture, so painting would cover the glass.
const _NOT_PAINT := ["glass", "window", "windscreen", "windshield", "screen", "tint", "light", "lamp", "reflector",
	"chrome", "mirror", "tyre", "tire", "rubber", "rim", "wheel", "disc", "brake", "caliper", "interior", "inside",
	"seat", "leather", "carpet", "dash", "steering", "fabric", "plastic", "black", "dark", "grill", "plate", "logo",
	"badge", "bottom", "under", "alu", "carbon", "exhaust", "invisible", "shield"]
const _IS_PAINT := ["paint", "body", "carpaint", "car_paint", "exterior"]


static var _area_cache := {}   # Mesh -> per-surface area (models share meshes)


static func _surface_areas(mesh: Mesh) -> PackedFloat32Array:
	if _area_cache.has(mesh):
		return _area_cache[mesh]
	var out := PackedFloat32Array()
	for si in mesh.get_surface_count():
		var a := 0.0
		var arr: Array = mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for k in range(0, idx.size() - 2, 3):
			a += (v[idx[k + 1]] - v[idx[k]]).cross(v[idx[k + 2]] - v[idx[k]]).length()
		out.append(a)
	_area_cache[mesh] = out
	return out


static func paint_targets(m: Node) -> Array:
	var area := {}
	var mats := {}
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var areas := _surface_areas(mesh)
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si) as BaseMaterial3D
			if mat == null:
				continue
			area[mat] = area.get(mat, 0.0) + areas[si]
			mats[mat] = true
	if mats.size() <= 1:
		return []
	var named: Array = []
	for mat in mats:
		var nm: String = (mat as BaseMaterial3D).resource_name.to_lower()
		if _IS_PAINT.any(func(k): return nm.contains(k)) and not _NOT_PAINT.any(func(k): return nm.contains(k) and k != "body"):
			named.append(mat)
	if not named.is_empty():
		return named
	var best: BaseMaterial3D = null
	for mat in mats:
		var bm := mat as BaseMaterial3D
		var nm := bm.resource_name.to_lower()
		if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or bm.albedo_color.a < 0.95:
			continue
		# dark + non-metallic is trim / tyres / tinted glass; a black car's paint is metallic
		if bm.albedo_color.get_luminance() < 0.15 and bm.albedo_texture == null and bm.metallic < 0.5:
			continue
		if _NOT_PAINT.any(func(k): return nm.contains(k)):
			continue
		if best == null or area[mat] > area[best]:
			best = bm
	return [best] if best else []


static func paint_model(m: Node, col: Color) -> void:
	var targets := paint_targets(m)
	if targets.is_empty():
		return
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si) as BaseMaterial3D
			if mat == null or not targets.has(mat):
				continue
			# keep the automotive finish set by _finish_materials, only change colour
			var cur := (mi as MeshInstance3D).get_surface_override_material(si) as BaseMaterial3D
			var dup := (cur if cur else mat).duplicate() as BaseMaterial3D
			dup.albedo_color = col
			(mi as MeshInstance3D).set_surface_override_material(si, dup)


## Automotive finish, applied to runtime copies (the model file is untouched):
## - body paint: a metallic base coat under a glossy clear coat. Imported paints
##   are often near-chrome (metallic ~0.9, roughness ~0.02), which looks like
##   liquid metal once the sky is reflected, or flat grey when it isn't.
## - glass: dielectric (not metal), very smooth, tinted - reflects the sky at
##   grazing angles like real glass instead of being a mirror.
## Chrome trim, lights, tyres and interior keep their original materials.
static func _finish_materials(m: Node, tint := 0.55) -> void:
	var paint := paint_targets(m)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si) as BaseMaterial3D
			if mat == null:
				continue
			var nm := mat.resource_name.to_lower()
			var dup := mat.duplicate() as BaseMaterial3D
			var lamp := nm.contains("light") or nm.contains("lamp") or nm.contains("klosz") or nm.contains("lens")
			var see_through := mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and mat.albedo_color.a < 0.9
			if nm.contains("mirror") or nm.contains("miror"):
				continue   # real chrome mirror: keep
			elif nm.contains("glass") or nm.contains("window") or (see_through and not lamp):
				dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				dup.albedo_color = Color(0.05, 0.08, 0.09, lerpf(0.35, 0.92, tint))
				dup.metallic = 0.0
				dup.roughness = 0.04
				dup.metallic_specular = 0.7
			elif paint.has(mat):
				# metallic paint flake, softened; the clear coat carries the gloss
				dup.metallic = 0.45 if mat.metallic > 0.5 else clampf(mat.metallic, 0.05, 0.3)
				dup.roughness = clampf(mat.roughness, 0.3, 0.5)
				dup.metallic_specular = 0.5
				dup.clearcoat_enabled = true
				dup.clearcoat = 1.0
				dup.clearcoat_roughness = 0.08
			else:
				continue
			(mi as MeshInstance3D).set_surface_override_material(si, dup)


## Ride height: shift the model so its lowest point (the tyres) sits where the
## raycast wheels actually touch the road at rest, so no car floats or sinks
## whatever its model_offset says.
func _auto_ground(m: Node3D) -> void:
	if wheels.is_empty():
		return
	var lowest := INF
	var inv: Transform3D = (m.get_parent() as Node3D).global_transform.affine_inverse() if m.is_inside_tree() else Transform3D()
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		var xf: Transform3D = (inv * g.global_transform) if g.is_inside_tree() else (m.transform * g.transform)
		var bb: AABB = xf * g.get_aabb()
		lowest = minf(lowest, bb.position.y)
	if lowest == INF:
		return
	var sag: float = mass * 9.81 / float(wheels.size()) / maxf(data.suspension_stiffness, 1.0)
	var contact: float = wheels[0].marker.position.y - (data.suspension_rest_length - sag) - data.wheel_radius
	m.position.y += contact - lowest
