extends SceneTree
## Counts building triangles + checks build time for both race maps.
func _init() -> void:
	await process_frame
	for path in ["res://scenes/world/maps/lagos_bridge/lagos_bridge.tscn", "res://scenes/world/maps/lekki/lekki.tscn"]:
		var t0 := Time.get_ticks_msec()
		var sc: Node = load(path).instantiate()
		root.add_child(sc)
		await process_frame
		var b := sc.find_child("LagosBuildings", true, false) as MeshInstance3D
		var l := sc.find_child("Land", true, false) as MeshInstance3D
		print("[density] %s build %d ms, building tris %d, land tris %d" % [path.get_file(), Time.get_ticks_msec() - t0,
			b.mesh.surface_get_array_len(0) / 3 if b else -1, l.mesh.surface_get_array_len(0) / 3 if l else -1])
		sc.queue_free(); await process_frame
	quit()
