extends SceneTree
## Before/after look check on the Island circuit: chase, front-quarter and side
## views of the player car (user://look_<tag>_<preset>_<view>.png).
## Env: LOWGFX=1 for the phone default (Low), TAG=name, PRESETS=0,1,2
func _init() -> void:
	await process_frame
	root.get_node("Game").high_graphics = OS.get_environment("LOWGFX") != "1"
	var tag := OS.get_environment("TAG")
	var sc: Node = load("res://scenes/world/maps/island/island.tscn").instantiate()
	root.add_child(sc)
	for i in 10: await process_frame
	var car: Node3D = sc.get_node("PlayerCar")
	var pd = car.get_node_or_null("PlayerDriver")
	if pd: pd.set_physics_process(false)
	var tod = sc.find_child("TimeOfDay", true, false)
	var f: Vector3 = car.global_transform.basis.z
	var r: Vector3 = car.global_transform.basis.x
	var p: Vector3 = car.global_position
	var cam := Camera3D.new(); cam.far = 3000.0; cam.fov = 62.0; sc.add_child(cam)
	var views := {
		"chase": [p - f * 6.5 + Vector3(0, 2.3, 0), p + f * 14.0 + Vector3(0, 0.8, 0)],
		"front": [p + f * 4.6 + r * 3.4 + Vector3(0, 1.3, 0), p + Vector3(0, 0.55, 0)],
		"side": [p + r * 5.0 - f * 1.0 + Vector3(0, 1.0, 0), p + Vector3(0, 0.6, 0)],
	}
	for pr in OS.get_environment("PRESETS").split(","):
		if tod: tod.apply(int(pr))
		for k in views:
			cam.global_position = views[k][0]
			cam.look_at(views[k][1])
			cam.current = true
			for i in 6: await process_frame
			root.get_viewport().get_texture().get_image().save_png("user://look_%s_%s_%s.png" % [tag, pr, k])
			print("[look] ", tag, " ", pr, " ", k)
	quit()
