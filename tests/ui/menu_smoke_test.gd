extends Node
## Smoke test: the menu/UI scenes instantiate and wire up without errors, and
## the Game autoload is reachable. Run:
## godot --headless --path . res://tests/ui/menu_smoke_test.tscn
var _f := 0
func _ready() -> void:
	if not Engine.has_singleton("Game") and get_node_or_null("/root/Game") == null:
		printerr("[menu_smoke_test] FAIL: Game autoload missing"); get_tree().quit(1); return
	for path in [
		"res://scenes/ui/menus/main_menu.tscn",
		"res://scenes/ui/menus/garage.tscn",
		"res://scenes/ui/menus/pause_menu.tscn",
	]:
		var ps: PackedScene = load(path)
		if ps == null:
			printerr("[menu_smoke_test] FAIL: could not load ", path); get_tree().quit(1); return
		var inst := ps.instantiate()
		add_child(inst)
		print("[menu_smoke_test] ok: ", path)
func _process(_d: float) -> void:
	_f += 1
	if _f == 3:
		print("[menu_smoke_test] PASS")
		get_tree().quit(0)
