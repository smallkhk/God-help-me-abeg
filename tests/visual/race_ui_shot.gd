extends SceneTree
## Renders the race pop-ups and the results card (user://race_ui_*.png).
func _init() -> void:
	await process_frame
	root.get_node("Game").high_graphics = false
	var sc: Node = load("res://scenes/world/maps/island/island.tscn").instantiate()
	root.add_child(sc)
	current_scene = sc
	for i in 20: await process_frame
	var rm = sc.find_child("RaceManager", true, false)
	var fl = rm.get("_flair")
	fl.popup("NEAR MISS!", Color(1.0, 0.95, 0.3), 0.12)
	fl.popup("DRIFT  2.4 s", Color(1.0, 0.55, 0.15), 0.04)
	fl.popup("OVERTAKE!  2nd", Color(0.4, 1.0, 0.45), 0.1)
	fl.popup("PERFECT START!", Color(0.3, 1.0, 0.9), 0.35)
	for r in rm.get("_rivals"):
		fl.taunt(r, false)
		break
	for i in 8: await process_frame
	root.get_viewport().get_texture().get_image().save_png("user://race_ui_pops.png")
	fl.stats = {"drift": 3, "near": 5, "overtake": 2, "air": 0, "best_drift": 2.4}
	rm._finish()
	for i in 6: await process_frame
	root.get_viewport().get_texture().get_image().save_png("user://race_ui_results.png")
	print("[ui] done")
	quit()
