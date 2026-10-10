class_name AdvancedPhysicsCar
extends RigidBody3D
## Simulator-grade raycast car for Godot 4 (no VehicleBody3D).
##
## Every force comes from the tyres and the air:
##   * 4 RayCast3D suspension struts: Hooke spring + linear damper, applied at the
##     contact point along the ground normal. Because each corner's force is
##     applied at its own contact point, weight transfer (roll, dive, squat)
##     emerges from rigid-body dynamics, nothing is faked.
##   * Each wheel is a spinning body (ω, inertia I). Engine/brake torque spins it;
##     the road reacts through the tyre. Longitudinal slip ratio σ comes from
##     ω·r vs ground speed, lateral slip angle α from the contact-patch velocity.
##   * Pacejka "Magic Formula" turns σ and α into forces, scaled by the
##     tyre load Fz (so loaded tyres grip more), combined in a friction ellipse.
##   * Aerodynamic drag F = ½·ρ·Cd·A·v² (plus optional downforce).
##
## Works with GodotPhysics or Jolt (Project Settings → Physics → 3D → Physics
## Engine = Jolt). Jolt is recommended: steadier contacts, better at 120 Hz.
## Tip: set Physics Ticks Per Second to 120 for the stiffest suspensions.
##
## Scene setup:
##   RigidBody3D (this script, mass ≈ 1200–1600)
##     CollisionShape3D  (chassis box, raised so it does not touch the road)
##     RayCast3D "WheelFL", "WheelFR", "WheelRL", "WheelRR"  (at the strut tops;
##        target_position is set automatically: straight down)
##     MeshInstance3D wheel visuals (optional, assigned in the inspector)
## Input actions used: accelerate, brake, steer_left, steer_right, handbrake.

# ─────────────────────────────── Wheels ────────────────────────────────
@export_group("Wheel Nodes")
@export var ray_fl: RayCast3D
@export var ray_fr: RayCast3D
@export var ray_rl: RayCast3D
@export var ray_rr: RayCast3D
## Optional visual meshes (spun and moved with the suspension).
@export var mesh_fl: Node3D
@export var mesh_fr: Node3D
@export var mesh_rl: Node3D
@export var mesh_rr: Node3D

# ───────────────────────────── Suspension ──────────────────────────────
@export_group("Suspension")
## Spring length at zero load, from the ray origin to the wheel centre (m).
@export var rest_length: float = 0.45
## Spring rate k (N/m). ~3–5× (corner weight / desired sag).
@export var spring_stiffness: float = 38000.0
## Damper rate c (N·s/m). Critical ≈ 2·sqrt(k·m_corner); use 0.3–0.7 of that.
@export var damper_stiffness: float = 3600.0
## Max droop/bump travel beyond rest (m): the ray only looks this far.
@export var max_travel: float = 0.2
## Anti-roll bar rate (N/m of left/right compression difference).
@export var anti_roll_stiffness: float = 9000.0

# ─────────────────────────── Engine / Brakes ───────────────────────────
@export_group("Engine & Brakes")
enum Drivetrain { FWD, RWD, AWD }
@export var drivetrain: Drivetrain = Drivetrain.RWD
## Peak engine torque at the crank (N·m).
@export var max_engine_torque: float = 420.0
## Overall drive ratio (gearbox × final drive). Single speed keeps this
## script focused on chassis/tyre physics; plug a gearbox in later.
@export var drive_ratio: float = 9.0
## Engine rev limit expressed as max wheel angular speed (rad/s).
@export var max_wheel_omega: float = 190.0
## Brake torque per wheel at full pedal (N·m). Front gets brake_bias.
@export var brake_force: float = 2600.0
@export_range(0.0, 1.0) var brake_bias: float = 0.62
## Handbrake torque on each rear wheel (N·m).
@export var handbrake_force: float = 3500.0

# ─────────────────────────────── Tyres ─────────────────────────────────
@export_group("Tyres")
@export var wheel_radius: float = 0.34
@export var wheel_mass: float = 20.0
## Peak friction coefficient μ (D = μ·Fz). 1.0 dry road tyre, 1.3 semi-slick.
@export var base_grip: float = 1.05
## Pacejka longitudinal coefficients (slip ratio σ).
@export var long_B: float = 11.0   # stiffness: initial slope
@export var long_C: float = 1.65   # shape: how wide the peak is
@export var long_E: float = 0.1    # curvature: fall-off after the peak
## Pacejka lateral coefficients (slip angle α in radians).
@export var lat_B: float = 9.5
@export var lat_C: float = 1.35
@export var lat_E: float = -0.4
## Rear grip multiplier (>1 = stable understeer, <1 = tail-happy).
@export var rear_grip_scale: float = 1.04
## Below this forward speed the slip maths is blended toward a stable,
## velocity-proportional friction so the car can stop and sit still.
@export var low_speed_threshold: float = 3.0
## Rolling resistance coefficient (fraction of load).
@export var rolling_resistance: float = 0.012

# ────────────────────────────── Steering ───────────────────────────────
@export_group("Steering")
@export var max_steer_angle: float = deg_to_rad(32.0)
## Steering angle shrinks with speed: at this speed (m/s) only
## high_speed_steer_fraction of the lock remains (keeps 200 km/h inputs sane).
@export var steer_falloff_speed: float = 33.0
@export_range(0.05, 1.0) var high_speed_steer_fraction: float = 0.15
@export var steer_speed: float = 3.0   # rad/s the wheel can be turned

# ───────────────────────────── Aerodynamics ────────────────────────────
@export_group("Aerodynamics")
@export var air_density: float = 1.225       # ρ (kg/m³)
@export var drag_coefficient: float = 0.32   # Cd
@export var frontal_area: float = 2.2        # A (m²)
## Downforce coefficient ×A (lift is negative); 0 for a road car.
@export var downforce_coefficient: float = 0.3

# ───────────────────────────── Runtime state ───────────────────────────
## Per-wheel simulation state.
class WheelState:
	var ray: RayCast3D
	var mesh: Node3D
	var is_front := false
	var is_left := false
	var driven := false
	var omega := 0.0            # wheel angular velocity (rad/s), +ve = rolling forward
	var spin := 0.0             # accumulated rotation for the visual (rad)
	var compression := 0.0      # current spring compression (m)
	var prev_compression := 0.0
	var load := 0.0             # normal force Fz (N)
	var grounded := false
	var contact := Vector3.ZERO
	var normal := Vector3.UP
	var slip_ratio := 0.0
	var slip_angle := 0.0
	var mesh_rest: Transform3D

var wheels: Array[WheelState] = []
var throttle := 0.0
var brake := 0.0
var steer_input := 0.0
var handbrake := false
var steer_angle := 0.0
var wheel_inertia := 1.0


func _ready() -> void:
	# Tyres and air provide all resistance: no hidden engine damping.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	# Solid-disc wheel inertia: I = ½·m·r²
	wheel_inertia = 0.5 * wheel_mass * wheel_radius * wheel_radius

	var specs := [[ray_fl, mesh_fl, true, true], [ray_fr, mesh_fr, true, false],
		[ray_rl, mesh_rl, false, true], [ray_rr, mesh_rr, false, false]]
	for s in specs:
		var r: RayCast3D = s[0]
		if r == null:
			push_error("AdvancedPhysicsCar: assign all four wheel RayCast3D nodes.")
			continue
		var w := WheelState.new()
		w.ray = r
		w.mesh = s[1]
		w.is_front = s[2]
		w.is_left = s[3]
		w.driven = (drivetrain == Drivetrain.AWD) \
			or (drivetrain == Drivetrain.FWD and w.is_front) \
			or (drivetrain == Drivetrain.RWD and not w.is_front)
		# Ray points straight down the strut, long enough for full droop + tyre.
		r.target_position = Vector3(0.0, -(rest_length + max_travel + wheel_radius), 0.0)
		r.enabled = true
		r.add_exception(self)
		if w.mesh:
			w.mesh_rest = w.mesh.transform
		wheels.append(w)


func _physics_process(delta: float) -> void:
	_read_input()
	_update_steering(delta)

	var com := global_transform * center_of_mass   # world centre of mass
	var driven_count := 0
	for w in wheels:
		if w.driven:
			driven_count += 1
	driven_count = maxi(driven_count, 1)

	# Pass 1: suspension (needs all compressions first for the anti-roll bar).
	for w in wheels:
		_cast(w, delta)
	for i in wheels.size():
		var w := wheels[i]
		if not w.grounded:
			w.load = 0.0
			continue
		# ── Hooke's law + linear damper ─────────────────────────────
		#   F_spring = k · x          (x = compression)
		#   F_damper = c · dx/dt      (compression velocity)
		var f_spring := spring_stiffness * w.compression
		var compression_velocity := (w.compression - w.prev_compression) / delta
		var f_damper := damper_stiffness * compression_velocity
		# Anti-roll bar: resists the difference between left and right.
		var partner := wheels[i ^ 1]   # FL<->FR (0,1), RL<->RR (2,3)
		var f_arb := 0.0
		if partner.grounded:
			f_arb = anti_roll_stiffness * (w.compression - partner.compression)
		# A spring can push but never pull the car into the road.
		w.load = maxf(0.0, f_spring + f_damper + f_arb)
		# Applied at the contact point → produces roll/pitch torque about the
		# CoM, which is exactly where weight transfer comes from.
		apply_force(w.normal * w.load, w.contact - global_position)

	# Pass 2: tyres (use this step's loads Fz).
	for w in wheels:
		_tyre(w, delta, com, driven_count)

	_aero()
	_update_visuals(delta)


# ─────────────────────────────── Input ────────────────────────────────
func _read_input() -> void:
	throttle = Input.get_action_strength("accelerate")
	brake = Input.get_action_strength("brake")
	steer_input = Input.get_axis("steer_right", "steer_left")
	handbrake = Input.is_action_pressed("handbrake")


func _update_steering(delta: float) -> void:
	# Speed-sensitive lock: full at parking speed, high_speed_steer_fraction
	# of it at steer_falloff_speed (sqrt curve: drops quickly, then levels out).
	var v := linear_velocity.length()
	var t := sqrt(clampf(v / steer_falloff_speed, 0.0, 1.0))
	var lock := max_steer_angle * lerpf(1.0, high_speed_steer_fraction, t)
	steer_angle = move_toward(steer_angle, steer_input * lock, steer_speed * delta)
	for w in wheels:
		if w.is_front:
			w.ray.rotation.y = steer_angle


# ───────────────────────────── Suspension ─────────────────────────────
func _cast(w: WheelState, _delta: float) -> void:
	w.prev_compression = w.compression
	w.ray.force_raycast_update()
	w.grounded = w.ray.is_colliding()
	if not w.grounded:
		w.compression = 0.0
		return
	w.contact = w.ray.get_collision_point()
	w.normal = w.ray.get_collision_normal()
	# Distance from strut top to the wheel centre = hit distance − tyre radius.
	var ray_length := w.ray.global_position.distance_to(w.contact) - wheel_radius
	# compression = rest_length − current_length  (negative = fully drooped)
	w.compression = clampf(rest_length - ray_length, 0.0, rest_length + max_travel)


# ──────────────────────────────── Tyres ────────────────────────────────
func _tyre(w: WheelState, delta: float, com: Vector3, driven_count: int) -> void:
	# ── Wheel torques (drive and brake) ──────────────────────────────
	var drive_torque := 0.0
	if w.driven:
		var t := max_engine_torque * drive_ratio / float(driven_count)
		# Reverse: brake held while (almost) stopped.
		var fwd_speed := linear_velocity.dot(-global_basis.z)
		if brake > 0.1 and fwd_speed < 0.5 and throttle < 0.05:
			drive_torque = -t * 0.5 * brake
		elif absf(w.omega) < max_wheel_omega:
			drive_torque = t * throttle
	var brake_torque := 0.0
	if not (brake > 0.1 and drive_torque < 0.0):
		brake_torque = brake_force * brake * (brake_bias if w.is_front else (1.0 - brake_bias)) * 2.0
	if handbrake and not w.is_front:
		brake_torque += handbrake_force

	if not w.grounded:
		# Free-spinning wheel: engine spins it up, brakes stop it.
		w.omega += drive_torque / wheel_inertia * delta
		w.omega = _apply_brake(w.omega, brake_torque, delta)
		w.slip_ratio = 0.0
		w.slip_angle = 0.0
		return

	# ── Contact-patch kinematics ────────────────────────────────────
	# Tyre axes in the ground plane. Forward is the (steered) ray's -Z.
	var fwd := -w.ray.global_basis.z
	fwd = (fwd - w.normal * fwd.dot(w.normal)).normalized()
	var right := fwd.cross(w.normal).normalized()
	# Velocity of the contact patch: v_cm + ω_body × r (r measured from CoM).
	var v_patch := linear_velocity + angular_velocity.cross(w.contact - com)
	var vx := v_patch.dot(fwd)     # forward ground speed at the patch
	var vy := v_patch.dot(right)   # sideways sliding speed

	# ── Slip quantities ─────────────────────────────────────────────
	# Longitudinal slip ratio σ = (ω·r − vx) / |vx|
	# Lateral slip angle    α = atan(vy / |vx|)
	# A floor on |vx| keeps both finite at a standstill.
	var denom := maxf(absf(vx), low_speed_threshold)
	w.slip_ratio = (w.omega * wheel_radius - vx) / denom
	w.slip_angle = atan2(vy, denom)

	# ── Pacejka forces, D = μ·Fz (load-sensitive peak) ──────────────
	var mu := base_grip * (1.0 if w.is_front else rear_grip_scale)
	# Mild load sensitivity: real tyres lose μ as load rises (drives balance).
	var nominal := mass * 9.81 * 0.25
	mu *= clampf(1.0 - 0.1 * (w.load / maxf(nominal, 1.0) - 1.0), 0.8, 1.1)
	var d := mu * w.load
	var fx := pacejka(w.slip_ratio, long_B, long_C, d, long_E)
	var fy := -pacejka(w.slip_angle, lat_B, lat_C, d, lat_E)   # opposes slide
	if handbrake and not w.is_front:
		fy *= 0.45   # locked rear tyres lose most lateral grip

	# ── Friction ellipse: combined slip can't exceed the tyre ───────
	var ex := fx / maxf(d, 1.0)
	var ey := fy / maxf(d, 1.0)
	var e := sqrt(ex * ex + ey * ey)
	if e > 1.0:
		fx /= e
		fy /= e

	# ── Low-speed blend: stable static friction so the car can park ──
	# At crawl speed the slip maths becomes stiff; blend in a force that
	# cancels the patch velocity over one step (clamped to the tyre limit).
	var low := 1.0 - clampf(absf(vx) / low_speed_threshold, 0.0, 1.0)
	if low > 0.0:
		var m_corner := mass * 0.25
		var fy_static := clampf(-vy * m_corner / delta, -d, d)
		fy = lerpf(fy, fy_static, low)

	# Rolling resistance opposes forward motion.
	fx -= signf(vx) * rolling_resistance * w.load * minf(absf(vx), 1.0)

	# ── Apply the tyre force at the contact patch ──────────────────
	apply_force(fwd * fx + right * fy, w.contact - global_position)

	# ── Wheel spin dynamics: I·dω/dt = T_drive − F_x·r − T_brake ────
	# The road's reaction (−fx·r) is what keeps σ near the grip peak.
	w.omega += (drive_torque - fx * wheel_radius) / wheel_inertia * delta
	w.omega = _apply_brake(w.omega, brake_torque, delta)
	# At low speed, settle ω toward free rolling to avoid jitter.
	if low > 0.0 and throttle < 0.05 and brake_torque <= 0.0:
		w.omega = lerpf(w.omega, vx / wheel_radius, low * 0.5)


## Brake torque always opposes spin and can stop the wheel, never reverse it.
func _apply_brake(omega: float, torque: float, delta: float) -> float:
	if torque <= 0.0:
		return omega
	var d_omega := torque / wheel_inertia * delta
	if absf(omega) <= d_omega:
		return 0.0
	return omega - signf(omega) * d_omega


## Simplified Pacejka "Magic Formula":
##   F = D · sin(C · atan(B·x − E·(B·x − atan(B·x))))
## B = stiffness, C = shape, D = peak force, E = curvature.
static func pacejka(slip: float, b: float, c: float, d: float, e: float) -> float:
	var bx := b * slip
	return d * sin(c * atan(bx - e * (bx - atan(bx))))


# ──────────────────────────── Aerodynamics ────────────────────────────
func _aero() -> void:
	var v := linear_velocity
	var speed := v.length()
	if speed < 0.1:
		return
	# Drag:  F = ½·ρ·Cd·A·v²  opposite to the direction of travel.
	var q := 0.5 * air_density * speed * speed      # dynamic pressure
	apply_central_force(-v.normalized() * q * drag_coefficient * frontal_area)
	# Downforce:  F = ½·ρ·Cl·A·v²  along the car's -Y.
	if downforce_coefficient > 0.0:
		apply_central_force(-global_basis.y * q * downforce_coefficient)


# ───────────────────────────── Visuals ────────────────────────────────
func _update_visuals(delta: float) -> void:
	for w in wheels:
		if w.mesh == null:
			continue
		w.spin = wrapf(w.spin + w.omega * delta, -TAU, TAU)
		# Wheel centre sits (rest_length − compression) below the strut top.
		var drop := (rest_length - w.compression) if w.grounded else (rest_length + max_travel)
		var t := w.mesh_rest
		t.origin = w.ray.position + Vector3(0.0, -drop, 0.0)
		var steer := steer_angle if w.is_front else 0.0
		t.basis = Basis(Vector3.UP, steer) * Basis(Vector3.RIGHT, -w.spin) * w.mesh_rest.basis
		w.mesh.transform = t


# ───────────────────────────── Debug info ─────────────────────────────
func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func debug_text() -> String:
	var s := "%.0f km/h  steer %.1f°\n" % [get_speed_kmh(), rad_to_deg(steer_angle)]
	for i in wheels.size():
		var w := wheels[i]
		s += "%s  Fz %5.0f N  σ %+.2f  α %+.1f°  ω %.0f\n" % [["FL", "FR", "RL", "RR"][i],
			w.load, w.slip_ratio, rad_to_deg(w.slip_angle), w.omega]
	return s
