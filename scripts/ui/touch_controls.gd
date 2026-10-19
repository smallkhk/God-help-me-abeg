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
	["horn", "HORN", 1, 520, 110, 50],
]


## Tilt steering (rotate the phone like a wheel). Saved in user://settings.cfg.
static var tilt := false
const TILT_FULL := 0.42          # rad of phone rotation for full lock
var _tilt0 := 0.0                # phone angle when tilt was switched on (neutral)
var _steer_btns: Array[TouchScreenButton] = []
var _tilt_lbl: Label


func _ready() -> void:
	layer = 20
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		tilt = bool(cfg.get_value("controls", "tilt", false))
	if not InputMap.has_action("horn"):
		InputMap.add_action("horn")
		var ev := InputEventKey.new(); ev.physical_keycode = KEY_H
		InputMap.action_add_event("horn", ev)
	# whole layer (incl. labels) only on touch devices
	visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
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
		if b[0] in ["steer_left", "steer_right"]:
			# drawn arrow: the iOS font has no ◀ ▶ glyphs (the buttons showed empty)
			lbl.text = ""
			var dir := -1.0 if b[0] == "steer_left" else 1.0
			var tri := Polygon2D.new()
			tri.polygon = PackedVector2Array([Vector2(r + dir * 26, r), Vector2(r - dir * 16, r - 28), Vector2(r - dir * 16, r + 28)])
			tri.color = Color(1, 1, 1, 0.85)
			tsb.add_child(tri)
		tsb.add_child(lbl)
		add_child(tsb)
		if b[0] in ["steer_left", "steer_right"]:
			_steer_btns.append(tsb)
	# camera / day-sunset-night / rain buttons along the top
	for a in [["time_next", KEY_N], ["weather_toggle", KEY_Y], ["horn", KEY_H], ["reset_car", KEY_T], ["tilt_toggle", KEY_G]]:
		if not InputMap.has_action(a[0]):
			InputMap.add_action(a[0])
			var kev := InputEventKey.new(); kev.physical_keycode = a[1]
			InputMap.action_add_event(a[0], kev)
	var top := [["camera_next", "CAM"], ["time_next", "DAY/NIGHT"], ["weather_toggle", "RAIN"], ["reset_car", "RESET"], ["tilt_toggle", "TILT: OFF"]]
	for t in top.size():
		var tb := TouchScreenButton.new()
		tb.action = top[t][0]
		var sz := Vector2(122, 56)
		tb.texture_normal = _rect(sz, Color(0, 0, 0, 0.35))
		tb.texture_pressed = _rect(sz, Color(0.98, 0.76, 0.12, 0.6))
		var rs := RectangleShape2D.new(); rs.size = sz
		tb.shape = rs
		tb.shape_centered = true
		tb.visibility_mode = TouchScreenButton.VISIBILITY_TOUCHSCREEN_ONLY
		# centred row that fits 4:3 iPads too (was cut off past RESET)
		tb.position = Vector2(vp.x * 0.5 - top.size() * 65.0 + t * 130.0, 20)
		var tl := Label.new(); tl.text = top[t][1]; tl.size = sz
		if top[t][0] == "tilt_toggle":
			_tilt_lbl = tl
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tl.add_theme_font_size_override("font_size", 19)
		tb.add_child(tl)
		add_child(tb)
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


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("tilt_toggle"):
		tilt = not tilt
		var cfg := ConfigFile.new()
		cfg.load("user://settings.cfg")
		cfg.set_value("controls", "tilt", tilt)
		cfg.save("user://settings.cfg")
		_apply_tilt()


func _apply_tilt() -> void:
	if tilt:
		var g := Input.get_gravity()
		_tilt0 = atan2(g.x, g.y) if g.length() > 1.0 else PI
	else:
		Input.action_release("steer_left")
		Input.action_release("steer_right")
	for b in _steer_btns:
		b.visible = not tilt
	if _tilt_lbl:
		_tilt_lbl.text = "TILT: ON" if tilt else "TILT: OFF"


func _process(_delta: float) -> void:
	if _tilt_lbl and _tilt_lbl.text != ("TILT: ON" if tilt else "TILT: OFF"):
		_apply_tilt()      # first frame / changed elsewhere
	if not tilt:
		return
	var g := Input.get_gravity()
	if g.length() < 1.0:
		return            # no sensor (PC)
	# phone turned clockwise (right side down) = steer right
	var a := -wrapf(atan2(g.x, g.y) - _tilt0, -PI, PI)
	var st := clampf(a / TILT_FULL, -1.0, 1.0)
	if absf(st) < 0.06:
		st = 0.0           # small dead zone: straight is straight
	if st > 0.0:
		Input.action_release("steer_left"); Input.action_press("steer_right", st)
	elif st < 0.0:
		Input.action_release("steer_right"); Input.action_press("steer_left", -st)
	else:
		Input.action_release("steer_left"); Input.action_release("steer_right")


static func _rect(sz: Vector2, col: Color) -> ImageTexture:
	var img := Image.create(int(sz.x), int(sz.y), false, Image.FORMAT_RGBA8)
	img.fill(col)
	return ImageTexture.create_from_image(img)


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
