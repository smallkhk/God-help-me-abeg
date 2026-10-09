extends Node3D
## Renders the bridge and saves screenshots (sunset, day, night) for visual review.
## Run under a real GL context: xvfb-run godot --path . res://tests/visual/shot.tscn
var _f := 0
var _shots := [[90, 1, "sunset"], [150, 0, "day"], [210, 2, "night"]]
func _ready():
	var pd = $LagosBridge.get_node_or_null("PlayerCar/PlayerDriver")
	if pd: pd.set_physics_process(false)
func _process(_d):
	_f += 1
	for s in _shots:
		if _f == s[0] - 20:
			$LagosBridge/TimeOfDay.apply(s[1])
		if _f == s[0]:
			var img := get_viewport().get_texture().get_image()
			img.save_png("user://shot_%s.png" % s[2])
			print("[shot] saved ", s[2])
	if _f > 220:
		get_tree().quit()
