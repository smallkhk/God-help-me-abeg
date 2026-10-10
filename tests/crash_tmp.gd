extends SceneTree
func _init() -> void:
	await process_frame
	var sc: Node = load(OS.get_environment("SCN")).instantiate()
	root.add_child(sc)
	for i in 240: await process_frame
	print("[crash] survived ", OS.get_environment("SCN"), " mem MB ", OS.get_static_memory_usage() / 1048576)
	quit()
