extends SceneTree
## Views along a map's race route: user://route_<map>_<i>.png
## Env: MAP=nyc, AT=400,700,... (metres along the lap)
func _init() -> void:
	await process_frame
	var mp := OS.get_environment("MAP")
	var sc: Node = load("res://scenes/world/maps/%s/%s.tscn" % [mp, mp]).instantiate()
	root.add_child(sc)
	current_scene = sc
	for i in 10: await process_frame
	var s: Array = (sc.get_node("MapBuilder") as MapBuilder).get_chunk()["road"]["samples"]
	var cam := Camera3D.new(); cam.far = 3000.0; cam.fov = 65.0; sc.add_child(cam)
	var k := 0
	for a in OS.get_environment("AT").split(","):
		var i := 0
		while i < s.size() - 1 and float(s[i]["dist_m"]) < float(a):
			i += 1
		var h: float = s[i]["heading_rad"]
		var f := Vector3(sin(h), 0, cos(h))
		var p := Vector3(s[i]["x"], float(s[i]["elev_m"]), s[i]["z"])
		cam.global_position = p - f * 7.0 + Vector3.UP * 3.0
		cam.look_at(p + f * 25.0 + Vector3.UP * 1.0)
		cam.current = true
		for j in 6: await process_frame
		root.get_viewport().get_texture().get_image().save_png("user://route_%s_%d.png" % [mp, k])
		k += 1
	quit()
