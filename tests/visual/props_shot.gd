extends SceneTree
## Close looks at the AI-generated (fal/Tripo) props on Lekki (user://props_<model>.png).
func _init() -> void:
	await process_frame
	var sc: Node = load("res://scenes/world/maps/lekki/lekki.tscn").instantiate()
	root.add_child(sc)
	for i in 8: await process_frame
	var cam := Camera3D.new(); cam.far = 3000.0; sc.add_child(cam)
	for key in ["plaza", "unfinished", "okada", "brt", "kiosk", "billboard"]:
		for m in sc.find_children("*%s*" % key, "MultiMeshInstance3D", true, false):
			var mm: MultiMesh = m.multimesh
			if mm.instance_count == 0:
				continue
			var xf: Transform3D = m.global_transform * mm.get_instance_transform(mm.instance_count / 2)
			var t := xf.origin
			var front := xf.basis.x.normalized()
			var d: float = {"plaza": 30.0, "unfinished": 22.0, "okada": 6.0, "brt": 18.0, "kiosk": 10.0, "billboard": 30.0}[key]
			cam.global_position = t + front * d + xf.basis.z.normalized() * d * 0.5 + Vector3(0, d * 0.25 + 1.5, 0)
			cam.look_at(t)
			cam.current = true
			for i in 6: await process_frame
			root.get_viewport().get_texture().get_image().save_png("user://props_%s.png" % key)
			print("[props] ", key, " count ", mm.instance_count)
			break
	quit()
