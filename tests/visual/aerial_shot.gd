extends SceneTree
## Aerial view like a drone shot over the road (user://aerial_<map>.png).
func _init() -> void:
	await process_frame
	for path in ["res://scenes/world/maps/lekki/lekki.tscn", "res://scenes/world/maps/lagos_bridge/lagos_bridge.tscn"]:
		var sc: Node = load(path).instantiate()
		root.add_child(sc)
		for i in 8: await process_frame
		var car: Node3D = sc.get_node("PlayerCar")
		var cam := Camera3D.new(); cam.far = 3000.0; sc.add_child(cam)
		var f: Vector3 = car.global_transform.basis.z
		cam.global_position = car.global_position - f * 30.0 + Vector3(0, 28, 0) + car.global_transform.basis.x * 8.0
		cam.look_at(car.global_position + f * 120.0)
		cam.current = true
		for i in 6: await process_frame
		root.get_viewport().get_texture().get_image().save_png("user://aerial_%s.png" % path.get_file().get_basename())
		sc.queue_free(); await process_frame
	quit()
