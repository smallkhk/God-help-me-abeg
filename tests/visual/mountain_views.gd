extends SceneTree
## Views of the Mountain Valley (Terrain3D demo) with the car (user://mountain_*.png).
func _init() -> void:
	await process_frame
	root.get_node("Game").high_graphics = OS.get_environment("LOWGFX") != "1"
	var sc: Node = load("res://scenes/world/maps/mountain/mountain.tscn").instantiate()
	root.add_child(sc)
	var car: RigidBody3D = sc.get_node("PlayerCar")
	for i in 120: await physics_frame   # let the car settle on the terrain
	print("[mtn] car at ", car.global_position)
	var f: Vector3 = car.global_transform.basis.z
	var r: Vector3 = car.global_transform.basis.x
	var cam := Camera3D.new(); cam.far = 6000.0; cam.fov = 65.0; sc.add_child(cam)
	var views := {
		"chase": [car.global_position - f * 8.0 + Vector3(0, 3.0, 0), car.global_position + f * 30.0 + Vector3(0, 2, 0)],
		"vista": [car.global_position - f * 30.0 + r * 25.0 + Vector3(0, 35, 0), car.global_position + f * 300.0],
	}
	for k in views:
		cam.global_position = views[k][0]
		cam.look_at(views[k][1])
		cam.current = true
		for i in 10: await process_frame
		root.get_viewport().get_texture().get_image().save_png("user://mountain_%s.png" % k)
		print("[mtn] ", k)
	quit()
