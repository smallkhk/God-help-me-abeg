class_name TouchControls
extends CanvasLayer
## On-screen buttons for phones/tablets. Each button fires a normal InputMap
## action, so the car code doesn't know the difference. Hidden on PC
## (TouchScreenButton.VISIBILITY_TOUCHSCREEN_ONLY).

const BTN := [
	# action, label, anchor side (0 = left, 1 = right), x, y (from bottom), radius
	["steer_left", "◀", 0, 110, 150, 85],
	["steer_right", "▶", 0, 300, 150, 85],
	["accelerate", "GAS", 1, 140, 170, 95],
	["brake", "BRAKE", 1, 340, 120, 70],
	["handbrake", "DRIFT", 1, 340, 300, 60],
	["nitro", "N2O", 1, 140, 380, 65],
]


func _ready() -> void:
	layer = 20
	var vp := get_viewport().get_visible_rect().size
	for b in BTN:
		var r: float = b[5]
		var tsb := TouchScreenButton.new()
		tsb.action = b[0]
		tsb.texture_normal = _circle(r, Color(1, 1, 1, 0.22))
		tsb.texture_pressed = _circle(r, Color(0.98, 0.76, 0.12, 0.55))
		var shape := CircleShape2D.new(); shape.radius = r
		tsb.shape = shape
		tsb.shape_centered = true
		tsb.passby_press = true
		tsb.visibility_mode = TouchScreenButton.VISIBILITY_TOUCHSCREEN_ONLY
		var x: float = b[3] if b[2] == 0 else vp.x - b[3]
		tsb.position = Vector2(x - r, vp.y - b[4] - r)
		var lbl := Label.new()
		lbl.text = b[1]
		lbl.add_theme_font_size_override("font_size", 26)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 6)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = Vector2(r * 2, r * 2)
		tsb.add_child(lbl)
		add_child(tsb)
	# pause button top-right
	var p := TouchScreenButton.new()
	p.action = "pause"
	p.texture_normal = _circle(40, Color(1, 1, 1, 0.22))
	p.visibility_mode = TouchScreenButton.VISIBILITY_TOUCHSCREEN_ONLY
	p.position = Vector2(vp.x - 110, 90)
	var pl := Label.new(); pl.text = "II"; pl.size = Vector2(80, 80)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pl.add_theme_font_size_override("font_size", 30)
	p.add_child(pl)
	add_child(p)


static func _circle(r: float, col: Color) -> ImageTexture:
	var s := int(r * 2)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(r, r)
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= r:
				var edge := clampf(r - d, 0.0, 1.0)
				var ring := 1.0 if d > r - 4.0 else 0.0
				img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * edge + ring * 0.35))
	return ImageTexture.create_from_image(img)
