extends SceneTree
## Renders each new car model on the test track from the side + front.
func _init() -> void:
	await process_frame
	for id in ["sedan_01", "hatch_01", "family_01", "suv_01", "luxury_01"]:
		var d: VehicleData = CarDatabase.get_data(id)
		var w := Node3D.new(); root.add_child(w)
		var env := WorldEnvironment.new(); env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.6, 0.75, 0.9)
		env.environment.ambient_light_color = Color(0.8, 0.8, 0.8); env.environment.ambient_light_energy = 0.8
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		w.add_child(env)
		var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 30, 0); w.add_child(sun)
		var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(40, 40); ground.mesh = pm; w.add_child(ground)
		var car: VehicleController = load("res://scenes/vehicles/player/player_car.tscn").instantiate()
		car.is_player = false; car.data = d; car.freeze = true
		car.position = Vector3(0, 0.55, 0)
		w.add_child(car)
		var cam := Camera3D.new(); w.add_child(cam)
		cam.position = Vector3(5.5, 2.2, 5.5); cam.look_at(Vector3(0, 0.6, 0))
		cam.current = true
		for i in 40:
			car.set_driver_input(0.0, 0.0, 1.0, false)
			await physics_frame
		root.get_viewport().get_texture().get_image().save_png("user://car_%s.png" % id)
		print("[carshot] ", id)
		w.queue_free(); await process_frame
	quit()
