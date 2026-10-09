extends SceneTree
## Loads both race maps and lists which landmarks were built.
func _init() -> void:
	await process_frame
	for path in ["res://scenes/world/maps/lagos_bridge/lagos_bridge.tscn", "res://scenes/world/maps/lekki/lekki.tscn"]:
		var sc: Node = load(path).instantiate()
		root.add_child(sc)
		for i in 5: await process_frame
		var names := []
		for n in sc.find_children("Landmark_*", "Node3D", true, false):
			names.append("%s@(%d,%d)" % [n.name, n.global_position.x, n.global_position.z])
		print("[landmarks] ", path.get_file(), ": ", names)
		var audio := sc.find_children("*", "CarAudio", true, false).size()
		print("[landmarks] car audio nodes: ", audio)
		sc.queue_free()
		await process_frame
	quit()
