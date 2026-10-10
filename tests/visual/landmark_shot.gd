extends SceneTree
## Renders a close-up of every landmark (user://lm_<name>.png).
func _init() -> void:
	await process_frame
	for path in ["res://scenes/world/maps/lagos_bridge/lagos_bridge.tscn", "res://scenes/world/maps/lekki/lekki.tscn"]:
		var sc: Node = load(path).instantiate()
		root.add_child(sc)
		for i in 10: await process_frame
		var pd = sc.get_node_or_null("PlayerCar/PlayerDriver")
		if pd: pd.set_physics_process(false)
		var cam := Camera3D.new(); cam.far = 3000.0; sc.add_child(cam)
		for n in sc.find_children("Landmark_*", "Node3D", true, false):
			var big: bool = not String(n.name).contains("Toll")
			var off := Vector3(160, 45, 160) if big else Vector3(20, 6, 25)
			cam.global_position = n.global_position + off
			cam.look_at(n.global_position + Vector3(0, 30 if big else 5, 0))
			cam.current = true
			for i in 6: await process_frame
			root.get_viewport().get_texture().get_image().save_png("user://lm_%s.png" % n.name)
			print("[lmshot] ", n.name)
		sc.queue_free()
		await process_frame
	quit()
