extends "res://tests/vehicle_physics/handling_lab.gd"
## PIT / side-slam check: the player car steers into a rival's rear quarter
## at ~80 km/h; prints how far the rival rotates and whether it spun out.
##   godot --headless --fixed-fps 60 --path . res://tests/vehicle_physics/pit_test.tscn
## env LAT=3 sideways closing speed (m/s), OFF=-1.5 contact point along the rival (- = rear)


func _ready() -> void:
	VehicleController.handling_v2 = true
	_build_world()
	_run.call_deferred()


func _mk(id: StringName, pos: Vector3, player: bool) -> VehicleController:
	var c := load(CAR_SCENE).instantiate() as VehicleController
	c.is_player = false
	c.data = CarDatabase.get_data(id)
	for n in ["PlayerDriver", "VehicleDebug"]:
		var nd := c.get_node_or_null(n)
		if nd:
			nd.free()
	add_child(c)
	c.global_transform = Transform3D(Basis(), pos)
	c.reset_state()
	c.is_player = player
	if player:
		c.contact_monitor = true
		c.max_contacts_reported = 4
		var fx := CarFX.new()       # exercises the impact sparks
		fx.vehicle = c
		c.add_child(fx)
		c.impact.connect(func(_pt: Vector3, s: float) -> void: print("[pit] impact %.1f m/s" % s))
	return c


func _run() -> void:
	var lat := float(OS.get_environment("LAT")) if OS.get_environment("LAT") != "" else 3.0
	var off := float(OS.get_environment("OFF")) if OS.get_environment("OFF") != "" else -1.6
	var r := _mk(&"corolla_01", Vector3(0, 0.7, 0), false)
	var p := _mk(&"corolla_01", Vector3(2.4, 0.7, off), true)
	for c in [r, p]:
		c.linear_velocity = Vector3(0, 0, 22.0)
	await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
	for c in [r, p]:
		c.linear_velocity = Vector3(0, 0, 22.0)
		c.set_driver_input(0.45, 0.0, 0.0, false)
	p.linear_velocity += Vector3(-lat, 0, 0)
	var steer := float(OS.get_environment("STEER")) if OS.get_environment("STEER") != "" else -0.5
	var max_yaw := 0.0
	var spun := false
	var t := 0.0
	while t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		p.set_driver_input(0.6, 0.0, steer if t < 0.6 else 0.0, false)
		r.set_driver_input(0.45 if r.knocked_t <= 0.0 else 0.1, 0.0, 0.0, false)
		max_yaw = maxf(max_yaw, absf(rad_to_deg(r.global_transform.basis.z.signed_angle_to(Vector3.FORWARD * -1.0, Vector3.UP))))
		spun = spun or r.spun_out
	print("[pit] lat=%.1f off=%.1f rival max yaw %.0f deg, spun_out=%s, knocked_t left %.2f, player yaw %.0f deg" % [lat, off, max_yaw, spun, r.knocked_t, absf(rad_to_deg(p.global_transform.basis.z.signed_angle_to(Vector3.BACK, Vector3.UP)))])
	get_tree().quit()
