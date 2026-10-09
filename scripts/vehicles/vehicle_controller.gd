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


func _ready() -> void:
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
	_mount_model()


## Swaps the placeholder box for the car's .glb model (spec §6.2). Cosmetic only;
## physics is untouched. Alignment (offset/rotation/scale) comes from VehicleData
## so each model is fitted without code.
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


func set_driver_input(throttle: float, brake: float, steer: float, handbrake: bool) -> void:
	throttle_input = clampf(throttle, 0.0, 1.0)
	brake_input = clampf(brake, 0.0, 1.0)
	steer_input = clampf(steer, -1.0, 1.0)
	handbrake_input = handbrake


func _physics_process(delta: float) -> void:
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
		nitro_amount = minf(nitro_amount + delta * 0.04, 1.0)

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
			anti = data.anti_roll_stiffness * (compression - hit_info[partner_i]["compression"])

		var susp_mag := maxf(0.0, spring + damp + anti)
		w.normal_load = susp_mag
		apply_force(up * susp_mag, offset)

		# --- Tyre forces in the ground plane ---
		_apply_tyre_force(w, offset, up, driven_count, grip_scale, delta)

	_apply_body_aero(delta, speed, fwd, up)
	_apply_stability_assist(delta, up)
	_update_wheel_visuals(delta, hit_info)


func _update_steering(delta: float, speed: float) -> void:
	# Speed-sensitive steering (spec §5.2): big angles slow, restrained fast.
	var t := clampf(speed / data.steer_speed_falloff, 0.0, 1.0)
	var max_angle := lerpf(data.max_steer_angle, data.max_steer_angle * data.high_speed_steer_fraction, t)
	var target := steer_input * max_angle
	var rate := data.steer_rate if absf(steer_input) > 0.01 else data.steer_return_rate
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
	var lat_grip := (data.lateral_grip_front if w.is_front else data.lateral_grip_rear) * grip_scale
	if w.is_rear and handbrake_input:
		lat_grip *= data.handbrake_grip_fraction
	# Load sensitivity (real tyres): grip coefficient drops as load rises, so
	# weight transfer in corners/braking actually changes the balance.
	var nominal := mass * 9.81 / 4.0
	var load_mu := clampf(1.0 - 0.12 * (load / maxf(nominal, 1.0) - 1.0), 0.75, 1.15)
	lat_grip *= load_mu
	var max_lat := lat_grip * load
	var lat_curve := _pacejka(slip_angle, data.peak_slip_angle)
	var lat_force := -lat_curve * max_lat  # opposes lateral slip

	# --- Longitudinal (drive / brake / engine-brake) force ---
	var long_grip := data.longitudinal_grip * grip_scale * clampf(1.0 - 0.12 * (load / maxf(mass * 9.81 / 4.0, 1.0) - 1.0), 0.75, 1.15)
	var max_long := long_grip * load
	var long_force := 0.0

	if w.is_driven and transmission.gear != 0:
		var ratio := data.get_gear_ratio(transmission.gear)
		var first := data.get_gear_ratio(1)
		var gear_mult := absf(ratio) / maxf(absf(first), 0.001)
		var drive := data.max_drive_force * transmission.torque_factor() * throttle_input * gear_mult / driven_count
		if nitro_active and transmission.gear > 0:
			drive *= 1.0 + nitro_power
		if transmission.gear == -1:
			drive = -drive
		# Traction control (assist): cut drive if this wheel is already near its
		# longitudinal limit (spec §5.6 — modifies input, same physics).
		var tc := _assist(data.traction_control_strength, 0.0, 0.5, 1.0)
		if tc > 0.0 and absf(drive) > max_long:
			drive = lerpf(drive, sign(drive) * max_long, tc)
		long_force += drive

	# Braking opposes current forward motion of the wheel.
	if brake_input > 0.0 and not (brake_input > 0.1 and forward_speed < 0.5 and transmission.gear == -1):
		var front_bias := 0.6 if w.is_front else 0.4
		var brake := data.brake_force * brake_input * front_bias
		# ABS (assist): don't let brake force lock the tyre past its grip limit.
		var abs_s := _assist(data.abs_strength, 0.0, 0.6, 1.0)
		var brake_cap := lerpf(brake, minf(brake, max_long), abs_s)
		long_force += -sign(vf) * brake_cap

	# Handbrake: strong rear brake that, with reduced rear grip above, breaks traction.
	if handbrake_input and w.is_rear:
		long_force += -sign(vf) * data.handbrake_force

	# Engine braking when coasting in gear.
	if throttle_input < 0.05 and w.is_driven and transmission.gear > 0 and absf(vf) > 0.5:
		long_force += -sign(vf) * data.engine_brake_force / driven_count

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

	var force := fwd * fx + right * fy
	apply_force(force, offset)
	dbg_long_force += fx


## Pacejka "Magic Formula" (as used by real racing sims): normalised lateral
## force for a slip angle. Peaks (=1) at `peak` rad, then falls to ~0.75 when
## sliding — progressive, catchable breakaway instead of an on/off grip switch.
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


func _apply_body_aero(_delta: float, speed: float, _fwd: Vector3, up: Vector3) -> void:
	if speed < 0.1:
		return
	var dir := linear_velocity.normalized()
	var drag := data.drag_coefficient * speed * speed
	apply_central_force(-dir * drag)
	dbg_drag_force = drag
	# Baseline downforce so bumps/seams at top speed don't launch the car.
	var df := maxf(data.downforce_coefficient, 0.9)
	apply_central_force(-up * df * speed * speed)
	# Anti-launch: when wheels leave the deck at speed, kill upward velocity
	# and pull the car back down quickly.
	if wheels_on_ground < wheels.size() and speed > 15.0:
		var vy := linear_velocity.y
		if vy > 0.0:
			linear_velocity.y = vy * 0.85
		if wheels_on_ground == 0:
			apply_central_force(Vector3.DOWN * mass * 9.8)


func _apply_stability_assist(_delta: float, up: Vector3) -> void:
	var s := _assist(data.stability_assist_strength, 0.0, 0.35, 0.8)
	if s <= 0.0:
		return
	# Damp excessive yaw rate only — a gentle nudge, never a steering override.
	var yaw_rate := angular_velocity.dot(up)
	var correction := -yaw_rate * s * data.mass * 0.6
	apply_torque(up * correction)


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
		var nm := String(n.name).to_lower().replace("_", "")
		var is_pivot := (nm.begins_with("wheel") and (nm.contains("fl") or nm.contains("fr") or nm.contains("rl") or nm.contains("rr") or nm.contains("front") or nm.contains("rear"))) \
			and not nm.contains("brake") and not nm.contains("rim") and n.get_child_count() > 0
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
			var sa := w.spin_angle + (forward_speed / maxf(data.wheel_radius, 0.01)) * delta
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
		w.spin_angle += (forward_speed / maxf(data.wheel_radius, 0.01)) * delta
		var steer := current_steer_angle if w.is_front else 0.0
		w.mesh.rotation = Vector3(w.spin_angle, steer, 0.0)
