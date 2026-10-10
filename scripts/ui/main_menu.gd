extends Control
## Main menu (premium redesign): cinematic split layout — logo + angled nav on
## the left, the player's real selected car as a live 3D showcase on the right
## over a Lagos night backdrop. Pages: HOME, RACE (event browser + preview),
## MAP (real routes on a Lagos map), SETTINGS. All data is real: money from the
## save, car from CarDatabase, best times from SaveManager, rewards from events.

const Y := UIStyle.YELLOW

const RACES := [
	{"name": "Third Mainland Bridge", "type": "Street Race", "loc": "Third Mainland Bridge · Lagos Lagoon", "km": 2.4, "tile": "street", "track": "bridge_test_sprint",
		"scene": "res://scenes/world/maps/lagos_bridge/lagos_bridge.tscn", "id": "bridge_test_sprint", "event": "res://data/events/bridge_sprint.tres", "map": "bridge"},
	{"name": "Lekki Expressway", "type": "Street Race", "loc": "Lekki Phase 1 → East", "km": 1.6, "tile": "freeroam", "track": "lekki_sprint",
		"scene": "res://scenes/world/maps/lekki/lekki.tscn", "id": "lekki_sprint", "event": "res://data/events/lekki_sprint.tres", "map": "lekki"},
	{"name": "Lagos Island", "type": "Circuit Race", "loc": "Marina · Broad Street · Balogun", "km": 1.7, "tile": "circuit", "track": "island_circuit",
		"scene": "res://scenes/world/maps/island/island.tscn", "id": "island_circuit", "event": "res://data/events/island_circuit.tres", "map": "island"},
	{"name": "Hills Loop", "type": "Circuit Race", "loc": "Hills outside Lagos", "km": 1.8, "tile": "hills", "track": "hills_sprint",
		"scene": "res://scenes/world/maps/hills/hills.tscn", "id": "hills_sprint", "event": "res://data/events/hills_sprint.tres"},
	{"name": "Bush Trail", "type": "Off-road", "loc": "Laterite trail through the bush", "km": 2.0, "tile": "offroad", "track": "offroad_trail",
		"scene": "res://scenes/world/maps/offroad/offroad.tscn", "id": "offroad_trail", "event": "res://data/events/offroad_trail.tres"},
	{"name": "Free Roam: Lagos Island", "type": "Free Roam", "loc": "Drive the whole city, no race", "km": 0.0, "tile": "circuit", "track": "island_circuit",
		"scene": "res://scenes/world/maps/island/island.tscn", "id": "", "free": true, "map": "island"},
	{"name": "Free Roam: Lekki", "type": "Free Roam", "loc": "Cruise Lekki Expressway", "km": 0.0, "tile": "freeroam", "track": "lekki_sprint",
		"scene": "res://scenes/world/maps/lekki/lekki.tscn", "id": "", "free": true, "map": "lekki"},
	{"name": "Mountain Valley", "type": "Free Roam", "loc": "Mountains, rocks and a tunnel", "km": 0.0, "tile": "hills", "track": "",
		"scene": "res://scenes/world/maps/mountain/mountain.tscn", "id": "", "free": true},
]

var _pages := {}
var _page_name := "home"
var _money_label: Label
var _sel_race := 0
var _preview := {}
var _cam: Camera3D
var _car_root: Node3D
var _t := 0.0


func _ready() -> void:
	theme = UIStyle.theme()
	_build_backdrop()
	_build_showcase()
	_build_vignette()
	_build_hud()
	_pages["home"] = _build_home()
	_pages["race"] = _build_race()
	_pages["map"] = _build_map()
	_pages["settings"] = _build_settings()
	_show("home", true)


func _process(delta: float) -> void:
	_t += delta
	if _cam:
		# slow cinematic drift around the car's rear three-quarter
		var a := -2.45 + sin(_t * 0.18) * 0.12
		var d := 8.2 + sin(_t * 0.11) * 0.3
		_cam.position = Vector3(sin(a) * d, 1.35 + sin(_t * 0.23) * 0.08, cos(a) * d)
		# aim left of the car so it sits in the right half of the screen
		_cam.look_at(Vector3(0, 0.7, 0) - Vector3(cos(a), 0, -sin(a)) * 2.6, Vector3.UP)


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel") and _page_name != "home":
		_show("home")
		get_viewport().set_input_as_handled()


func _show(page: String, instant := false) -> void:
	_page_name = page
	for k in _pages:
		var p: Control = _pages[k]
		if k == page:
			p.visible = true
			if not instant:
				p.modulate.a = 0.0
				create_tween().tween_property(p, "modulate:a", 1.0, 0.25)
		else:
			p.visible = false
	if _car_root:
		_car_root.get_parent().get_parent().visible = page == "home"   # showcase only on home
	var btns: Array = _pages[page].find_children("*", "Button", true, false)
	if not btns.is_empty():
		UIStyle.focus_later(btns[0])
	if page == "home":
		var items: Array = _pages["home"].find_children("Nav*", "Button", true, false)
		for i in items.size():
			UIStyle.enter(items[i], -50.0, 0.05 * i)


# ───────────────────────── backdrop + 3D car ─────────────────────────
func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = UIStyle.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var art := TextureRect.new()
	art.texture = load("res://assets/ui/tiles/backdrop.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	art.pivot_offset = get_viewport_rect().size * 0.5
	var tw := create_tween().set_loops()
	tw.tween_property(art, "scale", Vector2(1.06, 1.06), 18.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(art, "scale", Vector2(1.0, 1.0), 18.0).set_trans(Tween.TRANS_SINE)


func _build_showcase() -> void:
	var d := CarDatabase.get_data(Game.selected_car_id)
	if d == null or d.model_scene == null:
		return
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cont)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	cont.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.38, 0.55)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	var we := WorldEnvironment.new(); we.environment = env
	vp.add_child(we)
	# night lighting: cool moon key, warm street lamp, red tail-light glow
	var moon := DirectionalLight3D.new()
	moon.rotation = Vector3(deg_to_rad(-35), deg_to_rad(-150), 0)
	moon.light_color = Color(0.62, 0.72, 1.0); moon.light_energy = 0.8; moon.shadow_enabled = true
	vp.add_child(moon)
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(2.5, 6.0, 1.5)
	lamp.look_at_from_position(lamp.position, Vector3.ZERO, Vector3.UP)
	lamp.light_color = Color(1.0, 0.78, 0.45); lamp.light_energy = 9.0; lamp.spot_range = 16.0; lamp.spot_angle = 45.0
	vp.add_child(lamp)
	var rim := SpotLight3D.new()
	rim.position = Vector3(-4.0, 2.5, -5.0)
	rim.look_at_from_position(rim.position, Vector3(0, 0.6, 0), Vector3.UP)
	rim.light_color = Color(0.45, 0.6, 1.0); rim.light_energy = 5.0; rim.spot_range = 14.0; rim.spot_angle = 35.0
	vp.add_child(rim)
	# wet asphalt: dark mirror-ish road that fades out at its edges
	var road := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(16, 16)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled;
void fragment() {
	vec2 c = UV - 0.5;
	float fade = 1.0 - smoothstep(0.18, 0.5, length(c));
	ALBEDO = vec3(0.02, 0.022, 0.028);
	ROUGHNESS = 0.08;
	METALLIC = 0.6;
	SPECULAR = 0.8;
	ALPHA = fade * 0.92;
}"""
	sm.shader = sh
	pm.material = sm
	road.mesh = pm
	vp.add_child(road)
	_car_root = Node3D.new()
	vp.add_child(_car_root)
	var m := d.model_scene.instantiate() as Node3D
	m.rotation = Vector3(deg_to_rad(d.model_rotation_deg.x), deg_to_rad(d.model_rotation_deg.y), deg_to_rad(d.model_rotation_deg.z))
	m.scale = Vector3.ONE * d.model_scale
	var col = Game.car_color(String(d.vehicle_id))
	if col != null:
		VehicleController.paint_model(m, col)
	_car_root.add_child(m)
	# sit the model's lowest point on the road
	var lo := INF
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		var bb: AABB = (_car_root.global_transform.affine_inverse() * g.global_transform) * g.get_aabb()
		lo = minf(lo, bb.position.y)
	if lo != INF:
		m.position.y -= lo
	var tail := OmniLight3D.new()
	tail.position = Vector3(0, 0.8, -2.6)
	tail.light_color = Color(1.0, 0.1, 0.08); tail.light_energy = 1.6; tail.omni_range = 3.5
	_car_root.add_child(tail)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	vp.add_child(_cam)
	_cam.current = true


func _build_vignette() -> void:
	# left-side darkening for the nav + bottom fade for readability
	for spec in [[Vector2(0, 0), Vector2(1, 0), 0.92, 0.0], [Vector2(0, 1), Vector2(0, 0.55), 0.7, 0.0]]:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, spec[2])); g.set_color(1, Color(0, 0, 0, spec[3]))
		var gt := GradientTexture2D.new()
		gt.gradient = g; gt.fill_from = spec[0]; gt.fill_to = spec[1]
		var r := TextureRect.new()
		r.texture = gt
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if spec[0] == Vector2(0, 0):
			r.anchor_right = 0.62
		add_child(r)


func _build_hud() -> void:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.PANEL, UIStyle.LINE, 0.0, 1, 8))
	pill.anchor_left = 1.0; pill.anchor_right = 1.0
	pill.offset_left = -360; pill.offset_right = -28; pill.offset_top = 24; pill.offset_bottom = 74
	add_child(pill)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.alignment = BoxContainer.ALIGNMENT_END
	pill.add_child(h)
	var ic := TextureRect.new()
	ic.texture = UIStyle.icon("coins"); ic.custom_minimum_size = Vector2(26, 26)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = Color(0.35, 0.9, 0.45)
	h.add_child(ic)
	_money_label = UIStyle.label(Game.naira(Game.money), 22, UIStyle.TEXT, UIStyle.bold())
	h.add_child(_money_label)


# ─────────────────────────────── HOME ───────────────────────────────
func _build_home() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# logo
	var logo := UIStyle.title("LAGOS", 150, Color.WHITE)
	logo.position = Vector2(70, 18)
	logo.add_theme_color_override("font_shadow_color", Color(0.98, 0.76, 0.12, 0.55))
	logo.add_theme_constant_override("shadow_offset_x", 5); logo.add_theme_constant_override("shadow_offset_y", 5)
	root.add_child(logo)
	var sub := UIStyle.title("STREET RACING", 62, Y)
	sub.position = Vector2(150, 150); sub.rotation = deg_to_rad(-5)
	root.add_child(sub)
	var tag := UIStyle.label("THIRD MAINLAND   •   LEKKI   •   EKO", 15, UIStyle.MUTED, UIStyle.bold())
	tag.position = Vector2(108, 228)
	root.add_child(tag)
	# nav
	var nav := VBoxContainer.new()
	nav.position = Vector2(56, 268)
	nav.add_theme_constant_override("separation", 9)
	root.add_child(nav)
	var items := [
		["flag", "RACE", "Hit the streets. Earn respect.", func(): _show("race")],
		["car", "GARAGE", "View & upgrade your rides.", func(): Game.goto(Game.SCENE_GARAGE)],
		["map-pin", "MAP", "Explore Lagos.", func(): _show("map")],
		["settings", "SETTINGS", "Graphics, audio, controls.", func(): _show("settings")],
		["log-out", "QUIT", "See you on the streets.", func(): get_tree().quit()],
	]
	for it in items:
		nav.add_child(_nav_item(it[0], it[1], it[2], it[3]))
	# tagline bottom-left
	var never := UIStyle.title("LAGOS NEVER SLEEPS", 34, Y)
	never.anchor_top = 1.0; never.anchor_bottom = 1.0
	never.offset_left = 70; never.offset_top = -64
	never.rotation = deg_to_rad(-4)
	root.add_child(never)
	# selected car: real name + price (bottom-right, above the weather chip)
	var d := CarDatabase.get_data(Game.selected_car_id)
	if d:
		var cb := VBoxContainer.new()
		cb.anchor_left = 1.0; cb.anchor_right = 1.0; cb.anchor_top = 1.0; cb.anchor_bottom = 1.0
		cb.offset_left = -520; cb.offset_right = -36; cb.offset_top = -210; cb.offset_bottom = -120
		cb.alignment = BoxContainer.ALIGNMENT_END
		root.add_child(cb)
		var n := UIStyle.title(d.display_name.to_upper(), 40, Color.WHITE)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cb.add_child(n)
		var price := "OWNED" if Game.owns(d.vehicle_id) else Game.naira(d.price_naira)
		var pl := UIStyle.label("YOUR RIDE   •   " + price, 15, Y, UIStyle.bold())
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cb.add_child(pl)
	root.add_child(_weather_chip())
	return root


func _nav_item(icon_name: String, t: String, desc: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = "Nav" + t
	b.custom_minimum_size = Vector2(440, 64)
	b.add_theme_stylebox_override("normal", UIStyle.box(Color(0.03, 0.035, 0.05, 0.82), UIStyle.LINE))
	var on := UIStyle.box(Y, Y)
	b.add_theme_stylebox_override("hover", on)
	b.add_theme_stylebox_override("focus", on)
	b.add_theme_stylebox_override("pressed", on)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 28; row.offset_right = -22
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var ic := TextureRect.new()
	ic.texture = UIStyle.icon(icon_name)
	ic.custom_minimum_size = Vector2(34, 34)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -4)
	row.add_child(col)
	var tl := UIStyle.title(t, 32, Color.WHITE)
	col.add_child(tl)
	var dl := UIStyle.label(desc, 13, UIStyle.MUTED)
	col.add_child(dl)
	var ch := TextureRect.new()
	ch.texture = UIStyle.icon("chevron-right")
	ch.custom_minimum_size = Vector2(26, 26)
	ch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ch)
	for c in [ic, ch, tl, dl]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lit := func(on_: bool):
		var k := UIStyle.INK if on_ else Color.WHITE
		ic.modulate = k; ch.modulate = k
		tl.add_theme_color_override("font_color", k)
		dl.add_theme_color_override("font_color", Color(0, 0, 0, 0.75) if on_ else UIStyle.MUTED)
		create_tween().tween_property(row, "offset_left", 40.0 if on_ else 28.0, 0.12)
	b.focus_entered.connect(func(): lit.call(true))
	b.focus_exited.connect(func(): lit.call(false))
	b.mouse_entered.connect(func(): b.grab_focus())
	b.pressed.connect(cb)
	UIStyle.juice(b)
	return b


func _weather_chip() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.PANEL, UIStyle.LINE, 0.0, 1, 8))
	p.anchor_left = 1.0; p.anchor_right = 1.0; p.anchor_top = 1.0; p.anchor_bottom = 1.0
	p.offset_left = -300; p.offset_right = -36; p.offset_top = -104; p.offset_bottom = -36
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var tod := String(Game.get_setting("start_time", "event"))
	var rain := bool(Game.get_setting("start_rain", false))
	var ic := TextureRect.new()
	ic.texture = UIStyle.icon("cloud-rain" if rain else ({"night": "moon", "sunset": "sun"}.get(tod, "cloud")))
	ic.custom_minimum_size = Vector2(36, 36)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	h.add_child(v)
	v.add_child(UIStyle.label("RACE CONDITIONS", 11, UIStyle.MUTED, UIStyle.bold()))
	var tt: String = {"event": "As per event", "day": "Day", "sunset": "Sunset", "night": "Night"}.get(tod, "As per event")
	v.add_child(UIStyle.title("%s%s" % [tt, "  ·  RAIN" if rain else ""], 26, Color.WHITE))
	return p


# ─────────────────────────────── RACE ───────────────────────────────
func _build_race() -> Control:
	var root := _page_root()
	_header(root, "flag", "RACE", "Choose an event and hit the streets.")
	# event browser (image tiles)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(56, 150)
	scroll.anchor_bottom = 1.0; scroll.offset_bottom = -110
	scroll.custom_minimum_size = Vector2(640, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	for i in RACES.size():
		grid.add_child(_race_tile(i))
	# selected-event preview
	var pv := PanelContainer.new()
	pv.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.PANEL, UIStyle.LINE, 0.0, 1, 6))
	pv.anchor_left = 1.0; pv.anchor_right = 1.0; pv.anchor_bottom = 1.0
	pv.offset_left = -600; pv.offset_right = -40; pv.offset_top = 150; pv.offset_bottom = -110
	root.add_child(pv)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pv.add_child(v)
	var img := TextureRect.new()
	img.custom_minimum_size = Vector2(0, 100)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	v.add_child(img)
	var nm := UIStyle.title("", 34, Color.WHITE); v.add_child(nm)
	var loc := UIStyle.label("", 15, UIStyle.MUTED); v.add_child(loc)
	var trk := TextureRect.new()
	trk.custom_minimum_size = Vector2(0, 110)
	trk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; trk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(trk)
	var info := GridContainer.new(); info.columns = 4
	info.add_theme_constant_override("h_separation", 18)
	v.add_child(info)
	var labels := {}
	for k in ["TYPE", "LENGTH", "BEST", "REWARD"]:
		info.add_child(UIStyle.label(k, 12, UIStyle.MUTED, UIStyle.bold()))
		var val := UIStyle.title("", 24, Color.WHITE)
		val.custom_minimum_size.x = 150
		labels[k] = val
		info.add_child(val)
	var go := Button.new()
	go.text = "START RACE  ›"
	go.custom_minimum_size = Vector2(0, 50)
	go.add_theme_font_override("font", UIStyle.head())
	go.add_theme_font_size_override("font_size", 30)
	go.add_theme_stylebox_override("normal", UIStyle.box(Y, Y))
	go.add_theme_stylebox_override("hover", UIStyle.box(Color(1, 0.86, 0.3), Color.WHITE, UIStyle.SKEW, 2))
	go.add_theme_stylebox_override("focus", UIStyle.box(Color(1, 0.86, 0.3), Color.WHITE, UIStyle.SKEW, 2))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		go.add_theme_color_override(c, UIStyle.INK)
	go.pressed.connect(_start_selected)
	UIStyle.juice(go)
	v.add_child(go)
	_preview = {"img": img, "name": nm, "loc": loc, "track": trk, "info": labels, "go": go}
	_back_button(root)
	_select_race(0)
	return root


func _race_tile(i: int) -> Button:
	var r: Dictionary = RACES[i]
	var b := Button.new()
	b.custom_minimum_size = Vector2(305, 140)
	b.clip_contents = true
	var n := UIStyle.box(Color(0, 0, 0, 0), UIStyle.LINE, 0.0, 1, 6)
	var on := UIStyle.box(Color(0, 0, 0, 0), Y, 0.0, 3, 6)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", on)
	b.add_theme_stylebox_override("focus", on)
	b.add_theme_stylebox_override("pressed", on)
	var img := TextureRect.new()
	img.texture = load("res://assets/ui/tiles/%s.jpg" % r["tile"])
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	img.show_behind_parent = true
	b.add_child(img)
	var g := Gradient.new(); g.set_color(0, Color(0, 0, 0, 0)); g.set_color(1, Color(0, 0, 0, 0.88))
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill_from = Vector2(0, 0.35); gt.fill_to = Vector2(0, 1)
	var shade := TextureRect.new(); shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT); shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(shade)
	var t := UIStyle.title(String(r["name"]).to_upper(), 26, Color.WHITE)
	t.anchor_top = 1.0; t.anchor_bottom = 1.0; t.offset_left = 14; t.offset_top = -60
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(t)
	var s := UIStyle.label(r["type"], 13, Y, UIStyle.bold())
	s.anchor_top = 1.0; s.anchor_bottom = 1.0; s.offset_left = 14; s.offset_top = -28
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(s)
	b.focus_entered.connect(func(): _select_race(i))
	b.mouse_entered.connect(func(): b.grab_focus())
	b.pressed.connect(_start_selected)
	UIStyle.juice(b)
	return b


func _select_race(i: int) -> void:
	_sel_race = i
	if _preview.is_empty():
		return
	var r: Dictionary = RACES[i]
	(_preview["img"] as TextureRect).texture = load("res://assets/ui/tiles/%s.jpg" % r["tile"])
	(_preview["name"] as Label).text = String(r["name"]).to_upper()
	(_preview["loc"] as Label).text = r["loc"]
	var tp := "res://assets/ui/tracks/%s.png" % r["track"]
	(_preview["track"] as TextureRect).texture = load(tp) if r["track"] != "" and ResourceLoader.exists(tp) else null
	var info: Dictionary = _preview["info"]
	info["TYPE"].text = r["type"]
	info["LENGTH"].text = ("%.1f km" % r["km"]) if r["km"] > 0.0 else "Open world"
	info["BEST"].text = UIStyle.fmt_time(SaveManager.get_best_time(r["id"])) if r["id"] != "" else "—"
	var reward := "—"
	if r.has("event") and ResourceLoader.exists(r["event"]):
		var ev = load(r["event"])
		reward = Game.naira(int(ev.get("reward_naira")))
	info["REWARD"].text = reward
	(_preview["go"] as Button).text = ("START FREE ROAM  ›" if r.get("free", false) else "START RACE  ›")


func _start_selected() -> void:
	var r: Dictionary = RACES[_sel_race]
	UIStyle.sfx(self, "slide")
	if r.get("free", false):
		Game.goto_free_roam(r["scene"])
	else:
		Game.free_roam = false
		Game.goto(r["scene"])


# ─────────────────────────────── MAP ────────────────────────────────
func _build_map() -> Control:
	var root := _page_root()
	_header(root, "map-pin", "MAP", "Explore Lagos and find your next race.")
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UIStyle.box(Color(0.02, 0.03, 0.05, 0.92), UIStyle.LINE, 0.0, 1, 6))
	frame.anchor_right = 1.0; frame.anchor_bottom = 1.0
	frame.offset_left = 56; frame.offset_right = -420; frame.offset_top = 150; frame.offset_bottom = -110
	frame.clip_contents = true
	root.add_child(frame)
	var canvas := MapCanvas.new()
	canvas.data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/lagos_map.json"))
	frame.add_child(canvas)
	# info panel
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.PANEL, UIStyle.LINE, 0.0, 1, 6))
	info.anchor_left = 1.0; info.anchor_right = 1.0; info.anchor_bottom = 1.0
	info.offset_left = -400; info.offset_right = -40; info.offset_top = 150; info.offset_bottom = -110
	root.add_child(info)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	info.add_child(v)
	var img := TextureRect.new()
	img.custom_minimum_size = Vector2(0, 160)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	v.add_child(img)
	var nm := UIStyle.title("SELECT A LOCATION", 36, Color.WHITE); v.add_child(nm)
	var ds := UIStyle.label("Tap a yellow marker on the map.", 15, UIStyle.MUTED)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ds)
	var best := UIStyle.label("", 15, Y, UIStyle.bold()); v.add_child(best)
	var race_b := Button.new(); race_b.text = "RACE HERE  ›"; race_b.visible = false
	race_b.custom_minimum_size = Vector2(0, 52); UIStyle.juice(race_b)
	v.add_child(race_b)
	var roam_b := Button.new(); roam_b.text = "FREE ROAM HERE  ›"; roam_b.visible = false
	roam_b.custom_minimum_size = Vector2(0, 52); UIStyle.juice(roam_b)
	v.add_child(roam_b)
	var legend := UIStyle.label("Outside Lagos:  Hills Loop · Bush Trail · Mountain Valley — pick them in RACE.", 13, UIStyle.MUTED)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(legend)
	var sel := {"race": -1, "roam": -1}
	race_b.pressed.connect(func():
		if sel["race"] >= 0:
			_sel_race = sel["race"]; _start_selected())
	roam_b.pressed.connect(func():
		if sel["roam"] >= 0:
			_sel_race = sel["roam"]; _start_selected())
	canvas.picked.connect(func(key: String, title_: String):
		if key == "":
			nm.text = title_.to_upper()
			ds.text = "Coming soon — not built yet."
			best.text = ""; race_b.visible = false; roam_b.visible = false
			img.texture = null
			return
		sel["race"] = -1; sel["roam"] = -1
		for i in RACES.size():
			if RACES[i].get("map", "") == key:
				if RACES[i].get("free", false): sel["roam"] = i
				else: sel["race"] = i
		var ri: int = sel["race"] if sel["race"] >= 0 else sel["roam"]
		var r: Dictionary = RACES[ri]
		nm.text = title_.to_upper()
		ds.text = r["loc"]
		img.texture = load("res://assets/ui/tiles/%s.jpg" % r["tile"])
		best.text = ("Best: " + UIStyle.fmt_time(SaveManager.get_best_time(r["id"]))) if sel["race"] >= 0 else ""
		race_b.visible = sel["race"] >= 0
		roam_b.visible = sel["roam"] >= 0
		canvas.focus_hint = race_b if race_b.visible else roam_b)
	canvas.focus_hint = race_b
	_back_button(root)
	UIStyle.focus_later(canvas)
	return root


# ───────────────────────────── SETTINGS ─────────────────────────────
func _build_settings() -> Control:
	var root := _page_root()
	_header(root, "settings", "SETTINGS", "Graphics, audio, controls.")
	var pv := PanelContainer.new()
	pv.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.PANEL, UIStyle.LINE, 0.0, 1, 6))
	pv.position = Vector2(56, 150)
	pv.custom_minimum_size = Vector2(760, 0)
	root.add_child(pv)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	pv.add_child(v)
	v.add_child(_slider_row("Rival racers", 0, 5, 1, float(Game.get_setting("rivals", 4)),
		func(x: float): Game.set_setting("rivals", int(x))))
	v.add_child(_slider_row("Volume", 0, 1, 0.05, float(Game.get_setting("volume", 0.8)),
		func(x: float):
			Game.set_setting("volume", x)
			AudioServer.set_bus_volume_db(0, linear_to_db(x))))
	v.add_child(_choice_row("Frame rate", ["30", "60", "90", "120", "MAX"], ["30", "60", "90", "120", "0"].find(str(int(Game.get_setting("max_fps", 60)))),
		func(i: int):
			var f: int = [30, 60, 90, 120, 0][i]
			Game.set_setting("max_fps", f)
			Engine.max_fps = f))
	var tods := ["event", "day", "sunset", "night"]
	v.add_child(_choice_row("Race time", ["EVENT", "DAY", "SUNSET", "NIGHT"], tods.find(String(Game.get_setting("start_time", "event"))),
		func(i: int):
			Game.set_setting("start_time", tods[i])
			_refresh_weather()))
	var rain := CheckButton.new()
	rain.text = "Start races in the rain"
	rain.button_pressed = bool(Game.get_setting("start_rain", false))
	rain.toggled.connect(func(on: bool):
		Game.set_setting("start_rain", on)
		_refresh_weather())
	UIStyle.juice(rain)
	v.add_child(rain)
	var gfx := CheckButton.new()
	gfx.text = "High graphics (photo sky, glow, long shadows)"
	gfx.button_pressed = Game.high_graphics
	gfx.toggled.connect(func(on: bool):
		Game.high_graphics = on
		Game.set_setting("high_graphics", on))
	UIStyle.juice(gfx)
	v.add_child(gfx)
	var fs := CheckButton.new()
	fs.text = "Fullscreen"
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(func(on: bool):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	UIStyle.juice(fs)
	v.add_child(fs)
	v.add_child(UIStyle.label("Controller: RT gas · LT brake · L-stick steer · A drift · X nitro · Y camera · R-stick look · A select · B back", 13, UIStyle.MUTED))
	_back_button(root)
	return root


func _refresh_weather() -> void:
	var home: Control = _pages.get("home")
	if home == null:
		return
	for c in home.get_children():
		if c is PanelContainer and c.anchor_top == 1.0:
			c.queue_free()
	home.add_child(_weather_chip())


# ───────────────────────────── helpers ──────────────────────────────
func _page_root() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	return root


func _header(root: Control, icon_name: String, t: String, sub: String) -> void:
	var ic := TextureRect.new()
	ic.texture = UIStyle.icon(icon_name)
	ic.position = Vector2(58, 52); ic.size = Vector2(44, 44)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.modulate = Y
	root.add_child(ic)
	var tl := UIStyle.title(t, 64, Color.WHITE)
	tl.position = Vector2(116, 28)
	root.add_child(tl)
	var sl := UIStyle.label(sub, 16, UIStyle.MUTED)
	sl.position = Vector2(120, 100)
	root.add_child(sl)


func _back_button(root: Control) -> void:
	var b := Button.new()
	b.text = "‹  BACK"
	b.anchor_top = 1.0; b.anchor_bottom = 1.0
	b.offset_left = 56; b.offset_top = -86; b.offset_right = 236; b.offset_bottom = -34
	b.pressed.connect(func(): _show("home"))
	UIStyle.juice(b)
	root.add_child(b)


func _slider_row(t: String, lo: float, hi: float, step: float, val: float, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := UIStyle.label(t, 18, Color.WHITE, UIStyle.bold())
	l.custom_minimum_size = Vector2(190, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = step; s.value = val
	s.custom_minimum_size = Vector2(360, 30)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vl := UIStyle.title("", 28, Y)
	s.value_changed.connect(func(x: float):
		vl.text = str(int(x)) if step >= 1.0 else "%d%%" % int(x * 100)
		cb.call(x))
	vl.text = str(int(val)) if step >= 1.0 else "%d%%" % int(val * 100)
	h.add_child(s)
	h.add_child(vl)
	return h


func _choice_row(t: String, opts: Array, cur: int, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := UIStyle.label(t, 18, Color.WHITE, UIStyle.bold())
	l.custom_minimum_size = Vector2(190, 0)
	h.add_child(l)
	var group := ButtonGroup.new()
	for i in opts.size():
		var b := Button.new()
		b.text = opts[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == cur
		b.custom_minimum_size = Vector2(92, 44)
		b.add_theme_stylebox_override("pressed", UIStyle.box(Y, Y))
		var idx := i
		b.pressed.connect(func(): cb.call(idx))
		UIStyle.juice(b)
		h.add_child(b)
	return h


## Lagos map: real race routes (from the map data, in lat/lon) on a dark grid,
## clickable markers, "coming soon" areas greyed out. Drag to pan, wheel/pinch
## to zoom.
class MapCanvas extends Control:
	signal picked(key: String, title: String)
	var data: Dictionary
	var focus_hint: Control
	var _zoom := 1.0
	var _pan := Vector2.ZERO
	var _drag := false
	var _hover := ""
	# view centre / scale (deg → px)
	const C_LAT := 6.48
	const C_LON := 3.42
	const PX_PER_DEG := 5200.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		focus_mode = Control.FOCUS_ALL
		resized.connect(func():
			if not _fitted:
				_fit(); queue_redraw())

	func _to_px(lat: float, lon: float) -> Vector2:
		var c := size * 0.5 + _pan
		return c + Vector2((lon - C_LON), -(lat - C_LAT)) * PX_PER_DEG * _zoom

	var _pad_i := -1
	func _gui_input(ev: InputEvent) -> void:
		if ev.is_action_pressed("ui_accept") and focus_hint and focus_hint.visible:
			focus_hint.grab_focus(); accept_event(); return
		if ev.is_action_pressed("ui_right") or ev.is_action_pressed("ui_left") or ev.is_action_pressed("ui_down") or ev.is_action_pressed("ui_up"):
			var ms := _markers()
			_pad_i = wrapi(_pad_i + (1 if ev.is_action_pressed("ui_right") or ev.is_action_pressed("ui_down") else -1), 0, ms.size())
			UIStyle.sfx(self, "hover")
			picked.emit(ms[_pad_i][0], ms[_pad_i][1])
			accept_event()
			return
		if ev is InputEventMouseButton:
			if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
				_zoom = clampf(_zoom * 1.12, 0.2, 4.0); _fitted = true; queue_redraw()
			elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
				_zoom = clampf(_zoom / 1.12, 0.2, 4.0); _fitted = true; queue_redraw()
			elif ev.button_index == MOUSE_BUTTON_LEFT:
				if ev.pressed:
					_drag = false
				elif not _drag:
					_click(ev.position)
		elif ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if ev.relative.length() > 1.5:
				_drag = true
			_pan += ev.relative; _fitted = true; queue_redraw()
		elif ev is InputEventMagnifyGesture:
			_zoom = clampf(_zoom * ev.factor, 0.2, 4.0); _fitted = true; queue_redraw()
		elif ev is InputEventScreenDrag:
			_pan += ev.relative; _drag = true; _fitted = true; queue_redraw()

	func _markers() -> Array:
		var out := []
		for r in data.get("routes", []):
			var p0: Array = r["pts"][0]
			out.append([r["key"], r["name"], _to_px(p0[0], p0[1])])
		for s in data.get("soon", []):
			out.append(["", s["name"], _to_px(s["lat"], s["lon"])])
		return out

	func _click(pos: Vector2) -> void:
		for m in _markers():
			if (m[2] as Vector2).distance_to(pos) < 26.0:
				UIStyle.sfx(self, "click")
				picked.emit(m[0], m[1])
				return

	var _fitted := false
	## First draw: zoom/pan so every race route fits the panel.
	func _fit() -> void:
		var lo := Vector2(INF, INF); var hi := -lo
		for r in data.get("routes", []):
			for q in r["pts"]:
				lo = lo.min(Vector2(q[1], q[0])); hi = hi.max(Vector2(q[1], q[0]))
		if lo.x == INF:
			return
		var span := (hi - lo).max(Vector2(0.01, 0.01)) * PX_PER_DEG
		_zoom = clampf(minf((size.x - 160.0) / span.x, (size.y - 150.0) / span.y), 0.2, 4.0)
		var mid := (lo + hi) * 0.5
		_pan = -Vector2(mid.x - C_LON, -(mid.y - C_LAT)) * PX_PER_DEG * _zoom

	func _draw() -> void:
		if not _fitted and size.x > 10.0:
			_fit()
		# grid
		var step := 60.0 * _zoom
		var off := Vector2(fposmod(_pan.x, step), fposmod(_pan.y, step))
		var x := off.x
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.04)); x += step
		var y := off.y
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.04)); y += step
		var f := UIStyle.bold()
		# coming-soon areas
		for s in data.get("soon", []):
			var p := _to_px(s["lat"], s["lon"])
			draw_circle(p, 30.0 * _zoom, Color(1, 1, 1, 0.04))
			draw_arc(p, 30.0 * _zoom, 0, TAU, 40, Color(1, 1, 1, 0.18), 1.5, true)
			draw_string(f, p + Vector2(-60, 46 * _zoom + 6), String(s["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(1, 1, 1, 0.45))
			draw_string(f, p + Vector2(-60, 46 * _zoom + 20), "COMING SOON", HORIZONTAL_ALIGNMENT_CENTER, 120, 10, Color(1, 1, 1, 0.3))
		# real routes (glow + core)
		for r in data.get("routes", []):
			var pts := PackedVector2Array()
			for q in r["pts"]:
				pts.append(_to_px(q[0], q[1]))
			draw_polyline(pts, Color(0.98, 0.76, 0.12, 0.18), 10.0, true)
			draw_polyline(pts, UIStyle.YELLOW, 3.0, true)
		# markers
		for m in _markers():
			if m[0] == "":
				continue
			var p: Vector2 = m[2]
			draw_circle(p, 16.0, Color(0, 0, 0, 0.8))
			draw_circle(p, 12.0, UIStyle.YELLOW)
			draw_circle(p, 4.0, UIStyle.INK)
			draw_string(f, p + Vector2(20, 6), String(m[1]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		draw_string(f, Vector2(16, size.y - 16), "DRAG TO PAN  ·  SCROLL / PINCH TO ZOOM", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.4))
