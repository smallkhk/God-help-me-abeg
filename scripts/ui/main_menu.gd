extends Control
## Main menu: Home / Race select / Settings pages, built in code so it is easy to
## restyle. Race cards show distance and best time; rivals count and graphics
## live in Settings (saved via Game settings).

const ACCENT := Color(0.98, 0.76, 0.12)      # danfo yellow
const BG_TOP := Color(0.05, 0.07, 0.12)
const BG_BOT := Color(0.16, 0.10, 0.06)

const RACES := [
	{"name": "Third Mainland Bridge", "sub": "Sprint · 9.5 km over the lagoon", "scene": "res://scenes/world/maps/lagos_bridge/lagos_bridge.tscn", "id": "bridge_test_sprint", "col": Color(0.15, 0.45, 0.75)},
	{"name": "Lekki Expressway", "sub": "Sprint · 6.5 km Lekki Phase 1 → east", "scene": "res://scenes/world/maps/lekki/lekki.tscn", "id": "lekki_sprint", "col": Color(0.80, 0.35, 0.15)},
	{"name": "Free Drive", "sub": "Test track · tune and practise", "scene": "res://scenes/world/test_track.tscn", "id": "", "col": Color(0.25, 0.55, 0.30)},
]

var _pages := {}


func _ready() -> void:
	_build_bg()
	_pages["home"] = _build_home()
	_pages["race"] = _build_race()
	_pages["settings"] = _build_settings()
	_show("home")


func _show(page: String) -> void:
	for k in _pages:
		_pages[k].visible = k == page


# ---------- look ----------

func _build_bg() -> void:
	var g := Gradient.new()
	g.set_color(0, BG_TOP); g.set_color(1, BG_BOT)
	var gt := GradientTexture2D.new()
	gt.gradient = g; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# road stripe across the bottom
	var road := ColorRect.new()
	road.color = Color(0.08, 0.08, 0.09)
	road.anchor_left = 0; road.anchor_right = 1; road.anchor_top = 0.82; road.anchor_bottom = 1
	add_child(road)
	for i in 12:
		var dash := ColorRect.new()
		dash.color = ACCENT
		dash.anchor_top = 0.905; dash.anchor_bottom = 0.915
		dash.anchor_left = i / 12.0 + 0.01; dash.anchor_right = i / 12.0 + 0.05
		add_child(dash)
	var title := _label("LAGOS STREET RACING", 72, ACCENT)
	title.anchor_left = 0; title.anchor_right = 1; title.offset_top = 50; title.offset_bottom = 140
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var sub := _label("Third Mainland · Lekki · Eko", 22, Color(1, 1, 1, 0.7))
	sub.anchor_left = 0; sub.anchor_right = 1; sub.offset_top = 135; sub.offset_bottom = 170
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)


func _label(t: String, size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _button(t: String, cb: Callable, w := 380) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(w, 58)
	b.add_theme_font_size_override("font_size", 26)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.12, 0.13, 0.16, 0.92)
	n.border_color = Color(1, 1, 1, 0.15)
	n.set_border_width_all(2); n.set_corner_radius_all(10)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = ACCENT; h.border_color = ACCENT
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_color_override("font_hover_color", Color.BLACK)
	b.add_theme_color_override("font_focus_color", Color.BLACK)
	b.pressed.connect(cb)
	return b


func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.anchor_left = 0.5; v.anchor_right = 0.5; v.anchor_top = 0.5; v.anchor_bottom = 0.5
	v.offset_left = -300; v.offset_right = 300; v.offset_top = -170; v.offset_bottom = 260
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	return v


func _center(v: VBoxContainer, c: Control) -> void:
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(c)


# ---------- pages ----------

func _build_home() -> Control:
	var v := _page()
	_center(v, _button("RACE", func(): _show("race")))
	_center(v, _button("GARAGE", func(): Game.goto(Game.SCENE_GARAGE)))
	_center(v, _button("SETTINGS", func(): _show("settings")))
	_center(v, _button("QUIT", func(): get_tree().quit()))
	var car := _label("Car: %s" % String(Game.selected_car_id), 20, Color(1, 1, 1, 0.75))
	car.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(car)
	v.get_child(0).grab_focus.call_deferred()
	return v


func _build_race() -> Control:
	var v := _page()
	v.add_child(_label("CHOOSE A RACE", 30, ACCENT))
	for r in RACES:
		var card := Button.new()
		card.custom_minimum_size = Vector2(600, 92)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.11, 0.14, 0.95)
		sb.border_color = r["col"]; sb.border_width_left = 10
		sb.set_corner_radius_all(10)
		var sh := sb.duplicate() as StyleBoxFlat
		sh.bg_color = Color(0.2, 0.2, 0.24, 0.98); sh.border_color = ACCENT
		card.add_theme_stylebox_override("normal", sb)
		card.add_theme_stylebox_override("hover", sh)
		card.add_theme_stylebox_override("focus", sh)
		card.add_theme_stylebox_override("pressed", sh)
		var path: String = r["scene"]
		card.pressed.connect(func(): Game.goto(path))
		var t := _label(r["name"], 28)
		t.position = Vector2(26, 10)
		card.add_child(t)
		var best_txt := ""
		if r["id"] != "":
			var b := SaveManager.get_best_time(r["id"])
			best_txt = "   ·   Best " + (_fmt(b) if b > 0.0 else "—")
		var s := _label(r["sub"] + best_txt, 18, Color(1, 1, 1, 0.7))
		s.position = Vector2(26, 52)
		card.add_child(s)
		v.add_child(card)
	var rv := _label("Rivals: %d   (change in Settings)" % int(Game.get_setting("rivals", 4)), 18, Color(1, 1, 1, 0.7))
	v.add_child(rv)
	_center(v, _button("BACK", func(): _show("home"), 220))
	return v


func _build_settings() -> Control:
	var v := _page()
	v.add_child(_label("SETTINGS", 30, ACCENT))
	v.add_child(_slider_row("Rival racers", 0, 5, 1, float(Game.get_setting("rivals", 4)),
		func(x: float): Game.set_setting("rivals", int(x))))
	v.add_child(_slider_row("Volume", 0, 1, 0.05, float(Game.get_setting("volume", 0.8)),
		func(x: float):
			Game.set_setting("volume", x)
			AudioServer.set_bus_volume_db(0, linear_to_db(x))))
	var gfx := CheckButton.new()
	gfx.text = "High graphics (photo sky, glow, long shadows)"
	gfx.add_theme_font_size_override("font_size", 20)
	gfx.button_pressed = Game.high_graphics
	gfx.toggled.connect(func(on: bool):
		Game.high_graphics = on
		Game.set_setting("high_graphics", on))
	v.add_child(gfx)
	var fs := CheckButton.new()
	fs.text = "Fullscreen"
	fs.add_theme_font_size_override("font_size", 20)
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(func(on: bool):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	v.add_child(fs)
	_center(v, _button("BACK", func():
		_pages["race"].queue_free()
		_pages["race"] = _build_race()
		_show("home"), 220))
	return v


func _slider_row(title: String, lo: float, hi: float, step: float, val: float, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := _label(title, 22)
	l.custom_minimum_size = Vector2(180, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = step; s.value = val
	s.custom_minimum_size = Vector2(300, 30)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vl := _label(str(val), 22, ACCENT)
	s.value_changed.connect(func(x: float):
		vl.text = str(int(x)) if step >= 1.0 else "%d%%" % int(x * 100)
		cb.call(x))
	vl.text = str(int(val)) if step >= 1.0 else "%d%%" % int(val * 100)
	h.add_child(s)
	h.add_child(vl)
	return h


static func _fmt(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	var ms := int((t - int(t)) * 1000.0)
	return "%02d:%02d.%03d" % [m, s, ms]
