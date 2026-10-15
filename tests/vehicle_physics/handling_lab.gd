extends Node3D
## Handling lab: a flat proving ground for the vehicle physics, separate from
## the game (nothing in the game loads it).
##
## Interactive (open the scene and press F6): drive the car on an endless flat
## asphalt plane with a 40 m skidpad circle, a braking zone and a 12 cm road
## bump; a telemetry overlay shows speed, gear/rpm, lateral g, yaw rate, body
## slip and per-wheel load / slip angle / slip ratio. Keys 1-9 switch car.
##
## Automated (headless): measures each car and prints a table
##   godot --headless --fixed-fps 60 --path . res://tests/vehicle_physics/handling_lab.tscn
##   env CARS=corolla_01,skyline_01 picks cars (default: the whole roster)
## Tests: 0-100 km/h, top speed (40 s), 100-0 braking distance, 40 m skidpad
## max lateral g, step-steer response at 80 km/h, handbrake slide + recovery,
## bump at 80 km/h, physics cost per step.

const KMH := 3.6
const G := 9.81
const CAR_SCENE := "res://scenes/vehicles/player/player_car.tscn"
const SKID_C := Vector3(-300, 0, 0)
const SKID_R := 40.0
const BUMP_X := 300.0

var car: VehicleController
var _cam: Camera3D
var _hud: Label
var _auto := false
var _ids: Array = []
var _prev_vel := Vector3.ZERO
var _lat_g := 0.0
var _results: Array = []


func _ready() -> void:
	_auto = DisplayServer.get_name() == "headless" or OS.get_environment("AUTO") == "1"
	VehicleController.handling_v2 = OS.get_environment("V2") == "1"
	_build_world()
	var env := OS.get_environment("CARS")
	_ids = Array(env.split(",")) if env != "" else Array(CarDatabase.ORDER)
	if _auto:
		_run_all.call_deferred()
	else:
		_spawn(StringName(_ids[0]), Transform3D(Basis(), Vector3(0, 0.7, 0)), true)


# ───────────────────────────── world ─────────────────────────────
func _build_world() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	add_child(body)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	ground.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/asphalt.jpg")
	mat.albedo_color = Color(2.4, 2.4, 2.4)
	mat.uv1_scale = Vector3(1000, 1000, 1)
	mat.roughness = 0.85
	ground.material_override = mat
	add_child(ground)
	# 12 cm x 1.6 m road bump across the lane at x = BUMP_X
	var bump := StaticBody3D.new()
	var shp := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for z in [-0.8, 0.0, 0.8]:
		for x in [-6.0, 6.0]:
			pts.append(Vector3(x, 0.12 if z == 0.0 else 0.0, z))
	shp.points = pts
	var bcs := CollisionShape3D.new()
	bcs.shape = shp
	bump.add_child(bcs)
	bump.position = Vector3(BUMP_X, 0, 0)
	bump.rotation.y = PI * 0.5
	add_child(bump)
	var bm := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(12, 0.12, 1.6)
	bm.mesh = box
	bm.position = Vector3(BUMP_X, 0.04, 0)
	bm.rotation.y = PI * 0.5
	add_child(bm)
	if _auto:
		return
	# skidpad cones + braking-zone stripes (visual only)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05; cone.bottom_radius = 0.22; cone.height = 0.6
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(1.0, 0.45, 0.05)
	for k in 48:
		var a := TAU * k / 48.0
		for r in [SKID_R - 4.0, SKID_R + 4.0]:
			var c := MeshInstance3D.new()
			c.mesh = cone
			c.material_override = cmat
			c.position = SKID_C + Vector3(cos(a) * r, 0.3, sin(a) * r)
			add_child(c)
	for k in 10:
		var s := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(10, 0.01, 0.5)
		s.mesh = sb
		s.position = Vector3(0, 0.01, 200 + k * 10)
		add_child(s)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.55, 0.7, 0.9)
	we.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(we)
	_cam = Camera3D.new()
	_cam.far = 3000.0
	add_child(_cam)
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(12, 12)
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)


func _spawn(id: StringName, xf: Transform3D, human: bool) -> void:
	if car:
		car.queue_free()
		car = null
	var c := load(CAR_SCENE).instantiate() as VehicleController
	c.is_player = false
	c.data = CarDatabase.get_data(id)
	if not human:
		for n in ["PlayerDriver", "VehicleDebug"]:
			var nd := c.get_node_or_null(n)
			if nd:
				nd.free()
	add_child(c)
	c.global_transform = xf
	c.reset_state()
	car = c
	_prev_vel = Vector3.ZERO


# ───────────────────────────── interactive ─────────────────────────────
func _unhandled_input(ev: InputEvent) -> void:
	if _auto or not (ev is InputEventKey) or not ev.pressed:
		return
	var k: int = ev.keycode - KEY_1
	if k >= 0 and k < mini(9, _ids.size()):
		_spawn(StringName(_ids[k]), Transform3D(Basis(), Vector3(0, 0.7, 0)), true)
	elif ev.keycode == KEY_R and car:
		_spawn(car.data.vehicle_id, Transform3D(Basis(), Vector3(0, 0.7, 0)), true)


func _physics_process(delta: float) -> void:
	if car == null:
		return
	var v := car.linear_velocity
	var acc := (v - _prev_vel) / delta
	_prev_vel = v
	_lat_g = lerpf(_lat_g, acc.dot(car.global_transform.basis.x) / G, 0.2)


func _process(_delta: float) -> void:
	if _auto or car == null:
		return
	var b := car.global_transform.basis
	var p := car.global_position
	var f := Vector3(b.z.x, 0, b.z.z).normalized()
	_cam.global_position = _cam.global_position.lerp(p - f * 7.0 + Vector3.UP * 2.6, 0.12)
	_cam.look_at(p + f * 6.0 + Vector3.UP * 0.8)
	var t := "%s  [1-9 car, R reset]\n" % car.data.display_name
	t += "%5.1f km/h  gear %s  %4.0f rpm\n" % [car.linear_velocity.length() * KMH, car.transmission.gear_label(), car.transmission.engine_rpm]
	t += "lat %.2f g   yaw %.2f rad/s   body slip %.1f°   steer %.1f°\n" % [_lat_g, car.angular_velocity.y, rad_to_deg(_beta()), rad_to_deg(car.current_steer_angle)]
	for w in car.wheels:
		t += "%s load %5.0f N  slip %5.1f°  ratio %+.2f%s\n" % [w.marker.name.substr(5), w.normal_load, rad_to_deg(w.slip_angle), w.slip_ratio, "" if w.grounded else "  AIR"]
	_hud.text = t


func _beta() -> float:
	var v := car.linear_velocity
	if v.length() < 2.0:
		return 0.0
	var b := car.global_transform.basis
	return atan2(v.dot(b.x), v.dot(b.z))


# ───────────────────────────── automated ─────────────────────────────
func _step(n := 1) -> void:
	for i in n:
		await get_tree().physics_frame


func _speed() -> float:
	return car.linear_velocity.length() * KMH


## Holds a target speed with throttle/brake (simple P control).
func _cruise(kmh: float) -> Array:
	var e := kmh - _speed()
	return [clampf(e * 0.25, 0.0, 1.0), clampf(-e * 0.15, 0.0, 1.0) if e < -3.0 else 0.0]


## Steer toward a world point (same law as the rival AI).
func _steer_to(target: Vector3) -> float:
	var to := target - car.global_position
	var b := car.global_transform.basis
	return clampf(atan2(to.dot(b.x), maxf(to.dot(b.z), 0.1)) * 1.4, -1.0, 1.0)


func _run_all() -> void:
	for id in _ids:
		var r := {"id": String(id)}
		if OS.get_environment("ONLY") == "step":
			await _t_step(StringName(id), r)
			_results.append(r)
			continue
		if OS.get_environment("ONLY") == "acc":
			await _t_accel(StringName(id), r)
			_results.append(r)
			continue
		if OS.get_environment("ONLY") == "hb":
			await _t_handbrake(StringName(id), r)
			_results.append(r)
			continue
		await _t_accel(StringName(id), r)
		await _t_brake(StringName(id), r)
		await _t_skidpad(StringName(id), r)
		await _t_step(StringName(id), r)
		await _t_handbrake(StringName(id), r)
		await _t_bump(StringName(id), r)
		_results.append(r)
		print("[lab] ", r)
	_print_table()
	get_tree().quit(0)


func _t_accel(id: StringName, r: Dictionary) -> void:
	_spawn(id, Transform3D(Basis(), Vector3(0, 0.7, 0)), false)
	await _step(30)
	var t := 0.0; var t100 := -1.0; var vmax := 0.0
	VehicleController.prof_us = 0; VehicleController.prof_steps = 0
	while t < 40.0:
		car.set_driver_input(1.0, 0.0, _steer_to(Vector3(0, 0, car.global_position.z + 50.0)), false)
		await _step()
		t += 1.0 / 60.0
		vmax = maxf(vmax, _speed())
		if t100 < 0.0 and _speed() >= 100.0:
			t100 = t
		if OS.get_environment("DEBUG_ACC") == "1" and int(t * 60.0) % 60 == 0 and t < 13.0:
			var w: VehicleController.Wheel = car.wheels[0]
			print("  acc t=%.0f v=%.0f gear=%d rpm=%.0f tf=%.2f FLslip=%.2f FLfx=%.0f FLload=%.0f" % [t, _speed(), car.transmission.gear, car.transmission.engine_rpm, car.transmission.torque_factor(), w.slip_ratio, w.dbg_fx, w.normal_load])
	r["0_100_s"] = snappedf(t100, 0.01)
	r["top_kmh"] = snappedf(vmax, 0.1)
	r["phys_us"] = int(float(VehicleController.prof_us) / maxi(VehicleController.prof_steps, 1))   # controller cost per car per physics step


func _t_brake(id: StringName, r: Dictionary) -> void:
	_spawn(id, Transform3D(Basis(), Vector3(0, 0.7, 0)), false)
	await _step(30)
	var t := 0.0
	while _speed() < 102.0 and t < 40.0:
		car.set_driver_input(1.0, 0.0, _steer_to(Vector3(0, 0, car.global_position.z + 50.0)), false)
		await _step(); t += 1.0 / 60.0
	if _speed() < 100.0:
		r["brake_100_m"] = -1
		return
	while _speed() > 100.0:
		car.set_driver_input(0.0, 0.0, 0.0, false)
		await _step()
	var p0 := car.global_position; t = 0.0
	while _speed() > 0.5 and t < 15.0:
		car.set_driver_input(0.0, 1.0, _steer_to(car.global_position + Vector3(0, 0, 50)), false)
		await _step(); t += 1.0 / 60.0
	r["brake_100_m"] = snappedf(Vector2(car.global_position.x - p0.x, car.global_position.z - p0.z).length(), 0.1)


## Drive round a 40 m circle, raising the speed slowly; the highest speed held
## within 2 m of the line for 2 s gives the steady lateral grip.
func _t_skidpad(id: StringName, r: Dictionary) -> void:
	var start := SKID_C + Vector3(SKID_R, 0.7, 0)
	_spawn(id, Transform3D(Basis(Vector3.UP, PI), start), false)   # heading -Z
	await _step(30)
	var target := 25.0; var held := 0.0; var best := 0.0; var t := 0.0; var steer_at := 0.0
	while t < 120.0:
		var p := car.global_position - SKID_C
		var ang := atan2(p.z, p.x) - 0.35            # look ahead clockwise
		var aim := SKID_C + Vector3(cos(ang), 0, sin(ang)) * SKID_R
		var cr := _cruise(target)
		car.set_driver_input(cr[0], cr[1], _steer_to(aim), false)
		await _step(); t += 1.0 / 60.0
		var rad := Vector2(p.x, p.z).length()
		if absf(rad - SKID_R) < 2.0 and absf(_speed() - target) < 2.0:
			held += 1.0 / 60.0
			if held > 2.0:
				best = target; steer_at = absf(car.current_steer_angle)
				target += 2.0; held = 0.0
		elif absf(rad - SKID_R) > 6.0:
			break
	var v := best / KMH
	r["skidpad_g"] = snappedf(v * v / SKID_R / G, 0.01)
	r["skidpad_kmh"] = best
	# Ackermann angle for 40 m vs angle used: >1 = understeer
	r["us_ratio"] = snappedf(steer_at / maxf(atan(car.data.wheelbase / SKID_R), 0.001), 0.01)


## 80 km/h, then a fixed 30 % steering step: yaw-rate rise time and overshoot.
func _t_step(id: StringName, r: Dictionary) -> void:
	_spawn(id, Transform3D(Basis(), Vector3(0, 0.7, 0)), false)
	await _step(30)
	var t := 0.0
	while _speed() < 80.0 and t < 30.0:
		car.set_driver_input(1.0, 0.0, _steer_to(Vector3(0, 0, car.global_position.z + 50.0)), false)
		await _step(); t += 1.0 / 60.0
	var yaws: Array[float] = []
	for i in 180:
		var cr := _cruise(80.0)
		car.set_driver_input(cr[0], cr[1], 0.3, false)
		await _step()
		yaws.append(absf(car.angular_velocity.y))
		if OS.get_environment("DEBUG_STEP") == "1" and i % 10 == 0:
			var ls := ""
			for w in car.wheels:
				ls += " %s %.0f" % [w.marker.name.substr(5), w.normal_load]
			print("  step t=%.2f v=%.0f yaw=%.2f roll=%.1f beta=%.1f steer=%.3f |%s" % [i / 60.0, _speed(), car.angular_velocity.y, rad_to_deg(car.global_transform.basis.x.y), rad_to_deg(_beta()), car.current_steer_angle, ls])
	var steady := 0.0
	for i in range(150, 180):
		steady += yaws[i] / 30.0
	var t90 := -1.0; var peak := 0.0
	for i in yaws.size():
		peak = maxf(peak, yaws[i])
		if t90 < 0.0 and yaws[i] >= 0.9 * steady:
			t90 = i / 60.0
	r["step_t90_s"] = snappedf(t90, 0.01)
	r["step_overshoot_pct"] = int((peak / maxf(steady, 0.001) - 1.0) * 100.0)
	r["step_lat_g"] = snappedf(steady * car.linear_velocity.length() / G, 0.01)


## 60 km/h: full lock + handbrake 0.7 s, then release and countersteer with
## part throttle. Records peak body slip and whether it recovers within 4 s.
func _t_handbrake(id: StringName, r: Dictionary) -> void:
	_spawn(id, Transform3D(Basis(), Vector3(0, 0.7, 0)), false)
	await _step(30)
	var t := 0.0
	while _speed() < 60.0 and t < 30.0:
		car.set_driver_input(1.0, 0.0, _steer_to(Vector3(0, 0, car.global_position.z + 50.0)), false)
		await _step(); t += 1.0 / 60.0
	var h0 := car.global_rotation.y
	var peak := 0.0
	for i in 42:
		car.set_driver_input(0.0, 0.0, 1.0, true)
		await _step()
		peak = maxf(peak, absf(_beta()))
		if OS.get_environment("DEBUG_HB") == "1" and i % 6 == 0:
			var w2: VehicleController.Wheel = car.wheels[2]
			var w0: VehicleController.Wheel = car.wheels[0]
			var fs := ""
			for w in car.wheels:
				fs += " %s(fx %.0f fy %.0f L %.0f)" % [w.marker.name.substr(5), w.dbg_fx, w.dbg_fy, w.normal_load]
			print("  hb t=%.2f v=%.0f yaw=%.2f beta=%.1f steer=%.2f |%s" % [i / 60.0, _speed(), car.angular_velocity.y, rad_to_deg(_beta()), car.current_steer_angle, fs])
	var rec := -1.0; t = 0.0
	while t < 4.0:
		var beta := _beta()
		peak = maxf(peak, absf(beta))
		car.set_driver_input(0.5, 0.0, clampf(-beta * 2.5, -1.0, 1.0), false)
		await _step(); t += 1.0 / 60.0
		if rec < 0.0 and absf(beta) < deg_to_rad(4.0) and absf(car.angular_velocity.y) < 0.3:
			rec = t
	r["hb_peak_slip_deg"] = int(rad_to_deg(peak))
	r["hb_turned_deg"] = int(absf(rad_to_deg(wrapf(car.global_rotation.y - h0, -PI, PI))))
	r["hb_recover_s"] = snappedf(rec, 0.01)


## 80 km/h over a 12 cm bump: airborne time, peak pitch, time to settle.
func _t_bump(id: StringName, r: Dictionary) -> void:
	_spawn(id, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(BUMP_X - 250.0, 0.7, 0)), false)   # heading +X
	await _step(30)
	var t := 0.0
	while car.global_position.x < BUMP_X - 2.0 and t < 40.0:
		var cr := _cruise(80.0)
		car.set_driver_input(cr[0], cr[1], _steer_to(Vector3(car.global_position.x + 50.0, 0, 0)), false)
		await _step(); t += 1.0 / 60.0
	var air := 0.0; var pitch := 0.0; var settle := -1.0; var calm := 0.0
	t = 0.0
	while t < 4.0:
		var cr := _cruise(80.0)
		car.set_driver_input(cr[0], cr[1], _steer_to(Vector3(car.global_position.x + 50.0, 0, 0)), false)
		await _step(); t += 1.0 / 60.0
		if car.wheels_on_ground == 0:
			air += 1.0 / 60.0
		var b := car.global_transform.basis
		pitch = maxf(pitch, absf(rad_to_deg(asin(clampf(b.z.y, -1.0, 1.0)))))
		var pr := absf(car.angular_velocity.dot(b.x))
		calm = calm + 1.0 / 60.0 if pr < 0.05 and absf(car.linear_velocity.y) < 0.1 else 0.0
		if settle < 0.0 and calm > 0.3 and t > 0.3:
			settle = t - 0.3
	r["bump_air_s"] = snappedf(air, 0.01)
	r["bump_pitch_deg"] = snappedf(pitch, 0.1)
	r["bump_settle_s"] = snappedf(settle, 0.01)


func _print_table() -> void:
	var cols := ["id", "0_100_s", "top_kmh", "brake_100_m", "skidpad_g", "us_ratio", "step_t90_s", "step_overshoot_pct", "step_lat_g", "hb_peak_slip_deg", "hb_turned_deg", "hb_recover_s", "bump_air_s", "bump_pitch_deg", "bump_settle_s", "phys_us"]
	print("\n[lab] | " + " | ".join(cols) + " |")
	for r in _results:
		var row := []
		for c in cols:
			row.append(str(r.get(c, "")))
		print("[lab] | " + " | ".join(row) + " |")
