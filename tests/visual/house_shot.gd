extends SceneTree
## Low street-level shot along the roadside (user://street_<map>.png).
func _init() -> void:
	await process_frame
	var sc: Node = load("res://scenes/world/maps/lekki/lekki.tscn").instantiate()
	root.add_child(sc)
	for i in 8: await process_frame
	# find a keke instance and look at it
	var target := Vector3.ZERO
	for m in sc.find_children("*house*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = m.multimesh
		if mm.instance_count > 0:
			target = mm.get_instance_transform(0).origin
			break
	var cam := Camera3D.new(); cam.far = 3000.0; sc.add_child(cam)
	cam.global_position = target + Vector3(18, 5, 14)
	cam.look_at(target + Vector3(0, 0.8, 0))
	cam.current = true
	for i in 8: await process_frame
	root.get_viewport().get_texture().get_image().save_png("user://house_lekki.png")
	print("[house] at ", target)
	quit()
