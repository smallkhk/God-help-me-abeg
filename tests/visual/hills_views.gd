extends SceneTree
## Three views of the Hills Loop with the player's car (user://hills_*.png).
func _init() -> void:
	await process_frame
	root.get_node("Game").high_graphics = OS.get_environment("LOWGFX") != "1"
	var sc: Node = load("res://scenes/world/maps/hills/hills.tscn").instantiate()
	root.add_child(sc)
	for i in 8: await process_frame
	var car: Node3D = sc.get_node("PlayerCar")
	var pd = car.get_node_or_null("PlayerDriver")
	if pd: pd.set_physics_process(false)
	var f: Vector3 = car.global_transform.basis.z
	var r: Vector3 = car.global_transform.basis.x
	var cam := Camera3D.new(); cam.far = 4000.0; cam.fov = 60.0; sc.add_child(cam)
	var views := {
		"chase": [car.global_position - f * 7.0 + Vector3(0, 2.6, 0), car.global_position + f * 20.0],
		"side": [car.global_position + r * 9.0 + f * 4.0 + Vector3(0, 1.6, 0), car.global_position + Vector3(0, 0.8, 0)],
		"drone": [car.global_position - f * 60.0 + r * 40.0 + Vector3(0, 70, 0), car.global_position + f * 200.0],
	}
	for k in views:
		cam.global_position = views[k][0]
		cam.look_at(views[k][1])
		cam.current = true
		for i in 8: await process_frame
		root.get_viewport().get_texture().get_image().save_png("user://hills_%s.png" % k)
		print("[hills] ", k)
	quit()
