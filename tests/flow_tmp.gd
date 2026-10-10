extends SceneTree
func _init() -> void:
	await process_frame
	var g = root.get_node("Game")
	for car in [&"camry_01", &"super_01", &"gwagon_01"]:
		g.selected_car_id = car
		g.goto("res://scenes/world/maps/lekki/lekki.tscn")
		for i in 120: await physics_frame
		var pc = current_scene.find_child("PlayerCar", true, false)
		var m = pc.get_node_or_null("CarModel")
		print("[flow] ", car, " model_y=", m.position.y if m else "-", " car_y=", pc.global_position.y, " wheels=", pc.wheels_on_ground, " mem=", OS.get_static_memory_usage() / 1048576)
	for s in ["res://scenes/ui/menus/main_menu.tscn", "res://scenes/world/maps/offroad/offroad.tscn", "res://scenes/world/maps/hills/hills.tscn"]:
		g.goto(s)
		for i in 100: await physics_frame
		print("[flow] ", s.get_file(), " ok trees=", current_scene.find_children("*trees_*", "MultiMeshInstance3D", true, false).size())
	quit()
