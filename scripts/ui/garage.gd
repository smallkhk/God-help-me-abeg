extends Control
## Garage (premium redesign): full-screen 3D showroom of the real car model with
## orbit/zoom, and tabs CARS · UPGRADES · CUSTOMIZE · PAINT · TUNING, all wired
## to the real save (Game): ownership, money, upgrades, paint, tint, tuning.

const Y := UIStyle.YELLOW
const PAINTS := [Color(0.85, 0.08, 0.08), Color(0.05, 0.05, 0.06), Color(0.95, 0.95, 0.95),
	Color(0.1, 0.25, 0.75), Color(0.98, 0.76, 0.12), Color(0.1, 0.55, 0.25), Color(0.55, 0.1, 0.6),
	Color(0.95, 0.45, 0.05), Color(0.6, 0.62, 0.66), Color(0.0, 0.55, 0.6), Color(0.45, 0.25, 0.12), Color(1.0, 0.4, 0.6)]
const TABS := [["car", "CARS"], ["wrench", "UPGRADES"], ["sparkles", "CUSTOMIZE"], ["paintbrush", "PAINT"], ["sliders-horizontal", "TUNING"]]

var _cars: Array[VehicleData] = []
var _index := 0
var _pivot: Node3D
var _current_model: Node3D
var _cam: Camera3D
var _horn: AudioStreamPlayer
var _yaw := 0.7
var _pitch := 0.22
var _dist := 6.4
var _idle := 99.0
var _drag := false
var _lights_on := false
var _lights: Array[Node3D] = []
var _has_glass := false

var _money: Label
var _name: Label
var _status: Label
var _stats: VBoxContainer
var _panel: PanelContainer
var _content: VBoxContainer
var _tab := 0
var _tab_buttons: Array[Button] = []
var _msg: Label


func _ready() -> void:
	theme = UIStyle.theme()
	for c in get_children():
		c.queue_free()   # old scene widgets: everything is built in code now
	_cars = CarDatabase.all()
	for i in _cars.size():
		if _cars[i].vehicle_id == Game.selected_car_id:
			_index = i
	_build_showroom()
	_build_ui()
	_show_car(true)
	_set_tab(0)


# ───────────────────────────── showroom ─────────────────────────────
func _build_showroom() -> void:
	var bg := ColorRect.new(); bg.color = UIStyle.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cont)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	cont.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.53, 0.62)
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(25), 0)
	sun.light_energy = 0.7; sun.shadow_enabled = true
	vp.add_child(sun)
	# workshop ceiling strip lights
	for x in [-2.5, 0.0, 2.5]:
		var sl := SpotLight3D.new()
		sl.position = Vector3(x, 6.0, 0.5)
		sl.look_at_from_position(sl.position, Vector3(x * 0.3, 0.0, 0.0), Vector3.UP)
		sl.spot_range = 12.0; sl.spot_angle = 42.0; sl.light_energy = 5.0
		sl.light_color = Color(0.92, 0.95, 1.0)
		vp.add_child(sl)
		var strip := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(1.8, 0.05, 0.18)
		var em := StandardMaterial3D.new(); em.emission_enabled = true; em.emission = Color(0.9, 0.95, 1.0); em.emission_energy_multiplier = 3.0
		bm.material = em; strip.mesh = bm; strip.position = Vector3(x, 5.8, 0.5)
		vp.add_child(strip)
	# glossy floor + yellow turntable ring
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 40)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.07, 0.07, 0.08); fm.metallic = 0.6; fm.roughness = 0.18
	pm.material = fm; floor_mi.mesh = pm
	vp.add_child(floor_mi)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new(); tor.inner_radius = 3.6; tor.outer_radius = 3.72
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Y; rm.emission_enabled = true; rm.emission = Y; rm.emission_energy_multiplier = 2.5
	tor.material = rm; ring.mesh = tor; ring.scale = Vector3(1, 0.05, 1)
	vp.add_child(ring)
	# back wall with a Nigerian flag and a yellow neon line
	var wall := MeshInstance3D.new()
	var wm := PlaneMesh.new(); wm.size = Vector2(30, 10); wm.orientation = PlaneMesh.FACE_Z
	var wmat := StandardMaterial3D.new(); wmat.albedo_color = Color(0.09, 0.095, 0.11); wmat.roughness = 0.8
	wm.material = wmat; wall.mesh = wm; wall.position = Vector3(0, 5, -9)
	vp.add_child(wall)
	for i in 3:
		var stripe := MeshInstance3D.new()
		var sq := PlaneMesh.new(); sq.size = Vector2(1.0, 2.0); sq.orientation = PlaneMesh.FACE_Z
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.0, 0.53, 0.32) if i != 1 else Color(0.97, 0.97, 0.97)
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sq.material = smat; stripe.mesh = sq
		stripe.position = Vector3(-4.0 + i * 1.0, 4.2, -8.95)
		vp.add_child(stripe)
	var neon := MeshInstance3D.new()
	var nb := BoxMesh.new(); nb.size = Vector3(26, 0.06, 0.06)
	var nm := StandardMaterial3D.new(); nm.emission_enabled = true; nm.emission = Y; nm.emission_energy_multiplier = 4.0; nm.albedo_color = Y
	nb.material = nm; neon.mesh = nb; neon.position = Vector3(0, 2.4, -8.9)
	vp.add_child(neon)
	_pivot = Node3D.new()
	vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 48.0
	vp.add_child(_cam)
	_horn = AudioStreamPlayer.new()
	_horn.stream = load("res://assets/audio/horn.ogg")
	add_child(_horn)


func _show_car(instant := false) -> void:
	var d := _cars[_index]
	if _current_model:
		_current_model.queue_free()
		_current_model = null
	_lights.clear()
	_has_glass = false
	if d.model_scene:
		var m := d.model_scene.instantiate() as Node3D
		m.rotation = Vector3(deg_to_rad(d.model_rotation_deg.x), deg_to_rad(d.model_rotation_deg.y), deg_to_rad(d.model_rotation_deg.z))
		m.scale = Vector3.ONE * d.model_scale
		VehicleController._finish_materials(m, Game.window_tint(String(d.vehicle_id)))
		var col = Game.car_color(String(d.vehicle_id))
		if col != null:
			VehicleController.paint_model(m, col)
		var holder := Node3D.new()
		holder.add_child(m)
		_pivot.add_child(holder)
		_current_model = holder
		# ground it + detect real glass (for window tint)
		var ab := _aabb(holder)
		m.position.y -= ab.position.y
		ab = _aabb(holder)
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			if mesh:
				for si in mesh.get_surface_count():
					var mat := mesh.surface_get_material(si)
					if mat and (mat.resource_name.to_lower().contains("glass") or mat.resource_name.to_lower().contains("window")):
						_has_glass = true
		for x in [-0.32, 0.32]:
			var sl := SpotLight3D.new()
			sl.position = Vector3(ab.get_center().x + ab.size.x * x, ab.position.y + ab.size.y * 0.38, ab.end.z - 0.05)
			sl.spot_range = 18.0; sl.spot_angle = 28.0; sl.light_energy = 8.0
			holder.add_child(sl)
			var glow := MeshInstance3D.new()
			var sp := SphereMesh.new(); sp.radius = 0.09; sp.height = 0.18
			var gm := StandardMaterial3D.new()
			gm.emission_enabled = true; gm.emission = Color(1, 0.97, 0.88); gm.emission_energy_multiplier = 6.0
			sp.material = gm; glow.mesh = sp; glow.position = sl.position
			holder.add_child(glow)
			sl.visible = _lights_on; glow.visible = _lights_on
			_lights.append(sl); _lights.append(glow)
		if not instant:
			holder.scale = Vector3.ONE * 0.92
			create_tween().tween_property(holder, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_info()


func _aabb(n: Node3D) -> AABB:
	var out := AABB(); var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		var bb: AABB = (n.global_transform.affine_inverse() * g.global_transform) * g.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


func _process(delta: float) -> void:
	_idle += delta
	if _idle > 3.0:
		_yaw += delta * 0.3
	var target := Vector3(0, 0.75, 0)
	_cam.position = target + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_cam.look_at(target, Vector3.UP)


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = ev.pressed and get_viewport().gui_get_hovered_control() == null
	elif ev is InputEventMouseMotion and _drag:
		_orbit(ev.relative)
	elif ev is InputEventScreenDrag and get_viewport().gui_get_hovered_control() == null:
		_orbit(ev.relative)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and get_viewport().gui_get_hovered_control() == null:
		_dist = clampf(_dist + (-0.4 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 0.4), 3.6, 10.0)
	elif ev is InputEventMagnifyGesture:
		_dist = clampf(_dist / ev.factor, 3.6, 10.0)


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("pause"):
		Game.goto_main_menu()
	elif ev is InputEventJoypadMotion and ev.axis == JOY_AXIS_RIGHT_X and absf(ev.axis_value) > 0.3:
		_orbit(Vector2(ev.axis_value * 12.0, 0))


func _orbit(rel: Vector2) -> void:
	_yaw -= rel.x * 0.008
	_pitch = clampf(_pitch + rel.y * 0.005, -0.02, 1.2)
	_idle = 0.0


# ──────────────────────────────── UI ────────────────────────────────
func _build_ui() -> void:
	var g := Gradient.new(); g.set_color(0, Color(0, 0, 0, 0.75)); g.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill_from = Vector2(0, 1); gt.fill_to = Vector2(0, 0.6)
	var shade := TextureRect.new(); shade.texture = gt; shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT); shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# header
	var ic := TextureRect.new(); ic.texture = UIStyle.icon("car"); ic.modulate = Y
	ic.position = Vector2(56, 40); ic.size = Vector2(44, 44); ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(ic)
	var tl := UIStyle.title("GARAGE", 64, Color.WHITE); tl.position = Vector2(112, 18); add_child(tl)
	var sl := UIStyle.label("Upgrade. Customize. Dominate.", 16, UIStyle.MUTED); sl.position = Vector2(116, 90); add_child(sl)
	# money
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.PANEL, UIStyle.LINE, 0.0, 1, 8))
	pill.anchor_left = 1.0; pill.anchor_right = 1.0
	pill.offset_left = -360; pill.offset_right = -28; pill.offset_top = 24; pill.offset_bottom = 74
	add_child(pill)
	var ph := HBoxContainer.new(); ph.alignment = BoxContainer.ALIGNMENT_END; ph.add_theme_constant_override("separation", 10)
	pill.add_child(ph)
	var ci := TextureRect.new(); ci.texture = UIStyle.icon("coins"); ci.modulate = Color(0.35, 0.9, 0.45)
	ci.custom_minimum_size = Vector2(26, 26); ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ph.add_child(ci)
	_money = UIStyle.label("", 22, UIStyle.TEXT, UIStyle.bold()); ph.add_child(_money)
	# car info (left)
	var info := VBoxContainer.new()
	info.position = Vector2(58, 150)
	info.add_theme_constant_override("separation", 4)
	add_child(info)
	_name = UIStyle.title("", 52, Color.WHITE); info.add_child(_name)
	_status = UIStyle.label("", 16, Y, UIStyle.bold()); info.add_child(_status)
	_stats = VBoxContainer.new(); _stats.add_theme_constant_override("separation", 6)
	info.add_child(_stats)
	# right content panel
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.PANEL, UIStyle.LINE, 0.0, 1, 6))
	_panel.anchor_left = 1.0; _panel.anchor_right = 1.0; _panel.anchor_bottom = 1.0
	_panel.offset_left = -450; _panel.offset_right = -28; _panel.offset_top = 96; _panel.offset_bottom = -132
	add_child(_panel)
	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(sc)
	_content = VBoxContainer.new(); _content.add_theme_constant_override("separation", 10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_content)
	# tab bar (bottom)
	var bar := HBoxContainer.new()
	bar.anchor_left = 0.5; bar.anchor_right = 0.5; bar.anchor_top = 1.0; bar.anchor_bottom = 1.0
	bar.offset_left = -440; bar.offset_right = 450; bar.offset_top = -112; bar.offset_bottom = -40
	bar.add_theme_constant_override("separation", 10)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bar)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i][1]
		b.icon = UIStyle.icon(TABS[i][0])
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 26)
		b.custom_minimum_size = Vector2(170, 66)
		b.add_theme_font_override("font", UIStyle.head())
		b.add_theme_font_size_override("font_size", 26)
		var idx := i
		b.pressed.connect(func(): _set_tab(idx))
		UIStyle.juice(b)
		bar.add_child(b)
		_tab_buttons.append(b)
	# back + quick actions
	var back := Button.new(); back.text = "‹  BACK"
	back.anchor_top = 1.0; back.anchor_bottom = 1.0
	back.offset_left = 28; back.offset_top = -104; back.offset_right = 170; back.offset_bottom = -48
	back.pressed.connect(func(): Game.goto_main_menu())
	UIStyle.juice(back)
	add_child(back)
	var qa := VBoxContainer.new()
	qa.anchor_top = 1.0; qa.anchor_bottom = 1.0
	qa.offset_left = 58; qa.offset_top = -290; qa.offset_bottom = -136
	qa.add_theme_constant_override("separation", 8)
	add_child(qa)
	for spec in [["HEADLIGHTS", _toggle_lights], ["HORN", func(): _horn.play()]]:
		var b := Button.new(); b.text = spec[0]; b.custom_minimum_size = Vector2(190, 46)
		b.pressed.connect(spec[1]); UIStyle.juice(b)
		qa.add_child(b)
	_msg = UIStyle.label("", 16, Y, UIStyle.bold())
	_msg.anchor_top = 1.0; _msg.anchor_bottom = 1.0
	_msg.offset_left = 58; _msg.offset_top = -132
	add_child(_msg)
	var hint := UIStyle.label("Drag to rotate · scroll / pinch to zoom", 13, UIStyle.MUTED)
	hint.anchor_left = 0.5; hint.anchor_right = 0.5; hint.anchor_top = 1.0; hint.anchor_bottom = 1.0
	hint.offset_left = -150; hint.offset_top = -136
	add_child(hint)


func _set_tab(i: int) -> void:
	_tab = i
	for k in _tab_buttons.size():
		var on := k == i
		_tab_buttons[k].add_theme_stylebox_override("normal", UIStyle.box(Y, Y) if on else UIStyle.box())
		if on:
			_tab_buttons[k].add_theme_stylebox_override("focus", UIStyle.box(Y, Color.WHITE, UIStyle.SKEW, 2))
			_tab_buttons[k].add_theme_color_override("font_focus_color", UIStyle.INK)
		else:
			_tab_buttons[k].remove_theme_stylebox_override("focus")
			_tab_buttons[k].remove_theme_color_override("font_focus_color")
		_tab_buttons[k].add_theme_color_override("font_color", UIStyle.INK if on else UIStyle.TEXT)
		_tab_buttons[k].add_theme_color_override("icon_normal_color", UIStyle.INK if on else Color.WHITE)
	for c in _content.get_children():
		c.queue_free()
	match i:
		0: _tab_cars()
		1: _tab_upgrades()
		2: _tab_customize()
		3: _tab_paint()
		4: _tab_tuning()
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.18)
	if _tab_buttons.size() > i:
		UIStyle.focus_later(_tab_buttons[i])


func _section(t: String) -> void:
	_content.add_child(UIStyle.title(t, 32, Y))


func _tab_cars() -> void:
	_section("CARS")
	for i in _cars.size():
		var d := _cars[i]
		var b := Button.new()
		var owned := Game.owns(d.vehicle_id)
		var sel := d.vehicle_id == Game.selected_car_id
		var st := "SELECTED" if sel else ("OWNED" if owned else Game.naira(d.price_naira))
		b.text = "%s\n%s" % [d.display_name, st]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size = Vector2(0, 62)
		b.add_theme_stylebox_override("normal", UIStyle.box(Color(0.1, 0.1, 0.12, 0.9), Y if i == _index else UIStyle.LINE, 0.0, 2 if i == _index else 1, 4))
		if not owned:
			b.icon = UIStyle.icon("lock")
			b.add_theme_constant_override("icon_max_width", 18)
		var idx := i
		b.focus_entered.connect(func():
			if _index != idx:
				_index = idx; _show_car())
		b.pressed.connect(func():
			_index = idx
			_show_car()
			_buy_or_select())
		UIStyle.juice(b)
		_content.add_child(b)


func _buy_or_select() -> void:
	var d := _cars[_index]
	if not Game.owns(d.vehicle_id):
		if not Game.buy_car(d.vehicle_id, d.price_naira):
			_flash("Not enough money — win races to earn more")
			return
		_flash("Bought %s!" % d.display_name)
	Game.set_selected_car(d.vehicle_id)
	if not _msg.text.begins_with("Bought"):
		_flash("%s selected" % d.display_name)
	_refresh_info()
	_set_tab(_tab)


func _tab_upgrades() -> void:
	var d := _cars[_index]
	_section("UPGRADES")
	if not Game.owns(d.vehicle_id):
		_content.add_child(UIStyle.label("Buy this car first to upgrade it.", 15, UIStyle.MUTED))
	var what := {"engine": "More power + higher rev limit", "tyres": "More grip, cornering and braking",
		"brakes": "Stronger brakes (+10% per level)", "suspension": "Stiffer springs, less body roll", "nitro": "Bigger, stronger nitro"}
	for kind in Game.UPGRADE_KINDS:
		var lvl := Game.upgrade_level(d.vehicle_id, kind)
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10)
		var col := VBoxContainer.new(); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UIStyle.title("%s  %s" % [String(kind).to_upper(), "■".repeat(lvl) + "□".repeat(Game.MAX_UPGRADE - lvl)], 26, Color.WHITE))
		col.add_child(UIStyle.label(what.get(kind, ""), 12, UIStyle.MUTED))
		row.add_child(col)
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 50)
		b.text = "MAX" if lvl >= Game.MAX_UPGRADE else Game.naira(Game.upgrade_cost(d.vehicle_id, kind))
		b.disabled = not Game.owns(d.vehicle_id) or lvl >= Game.MAX_UPGRADE
		var k: String = kind
		b.pressed.connect(func():
			if Game.buy_upgrade(d.vehicle_id, k):
				_flash("%s upgraded!" % k.capitalize())
			else:
				_flash("Not enough money")
			_refresh_info(); _set_tab(1))
		UIStyle.juice(b)
		row.add_child(b)
		_content.add_child(row)


func _tab_customize() -> void:
	var d := _cars[_index]
	_section("CUSTOMIZE")
	_content.add_child(UIStyle.title("WINDOW TINT", 26, Color.WHITE))
	if not _has_glass:
		_content.add_child(UIStyle.label("This car's windows are part of its body texture, so tint can't change on it.", 14, UIStyle.MUTED))
		return
	var s := HSlider.new()
	s.min_value = 0.0; s.max_value = 1.0; s.step = 0.05
	s.value = Game.window_tint(String(d.vehicle_id))
	s.custom_minimum_size = Vector2(0, 34)
	var vl := UIStyle.label("", 14, UIStyle.MUTED)
	var upd := func(v: float):
		vl.text = "Clear" if v < 0.2 else ("Light" if v < 0.45 else ("Medium" if v < 0.7 else "Limo black"))
	upd.call(s.value)
	s.value_changed.connect(func(v: float):
		upd.call(v)
		Game.set_window_tint(String(d.vehicle_id), v))
	s.drag_ended.connect(func(_c: bool): _show_car(true))
	_content.add_child(s)
	_content.add_child(vl)


func _tab_paint() -> void:
	var d := _cars[_index]
	_section("PAINT")
	var grid := GridContainer.new(); grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	for c in PAINTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(54, 54)
		var sb := UIStyle.box(c, Color(1, 1, 1, 0.3), 0.0, 1, 27)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", UIStyle.box(c, Y, 0.0, 3, 27))
		b.add_theme_stylebox_override("focus", UIStyle.box(c, Y, 0.0, 3, 27))
		var col: Color = c
		b.pressed.connect(func(): _apply_paint(d, col))
		UIStyle.juice(b)
		grid.add_child(b)
	_content.add_child(grid)
	_content.add_child(UIStyle.label("CUSTOM COLOUR", 13, UIStyle.MUTED, UIStyle.bold()))
	var pick := ColorPicker.new()
	pick.edit_alpha = false
	pick.presets_visible = false
	pick.sampler_visible = false
	pick.color_modes_visible = false
	pick.sliders_visible = false
	pick.hex_visible = true
	pick.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	pick.custom_minimum_size = Vector2(0, 260)
	var cur = Game.car_color(String(d.vehicle_id))
	if cur != null:
		pick.color = cur
	pick.color_changed.connect(func(c: Color): _apply_paint(d, c, false))
	_content.add_child(pick)
	var reset := Button.new(); reset.text = "FACTORY PAINT"
	reset.pressed.connect(func():
		Game.set_car_color(String(d.vehicle_id), null)
		_show_car(true)); UIStyle.juice(reset)
	_content.add_child(reset)


func _apply_paint(d: VehicleData, c: Color, animate := true) -> void:
	Game.set_car_color(String(d.vehicle_id), c)
	_show_car(true)
	if animate and _current_model:
		_current_model.scale = Vector3.ONE * 0.97
		create_tween().tween_property(_current_model, "scale", Vector3.ONE, 0.2)


func _tab_tuning() -> void:
	var d := _cars[_index]
	var id := String(d.vehicle_id)
	_section("TUNING")
	if not Game.owns(d.vehicle_id):
		_content.add_child(UIStyle.label("Buy this car first to tune it.", 15, UIStyle.MUTED))
		return
	var t := Game.tuning(id)
	var rows := [
		["grip_balance", "GRIP BALANCE", -1.0, 1.0, 0.1, "Front grip ◂ ▸ Rear grip (more rear = stable, more front = sharper)"],
		["stiffness", "SUSPENSION", 0.8, 1.25, 0.05, "Soft ◂ ▸ Stiff"],
		["brake_bias", "BRAKE BIAS", 0.5, 0.75, 0.01, "Rear ◂ ▸ Front"],
		["steer_speed", "STEERING SPEED", 0.7, 1.3, 0.05, "Slow ◂ ▸ Quick"],
	]
	for r in rows:
		_content.add_child(UIStyle.title(r[1], 24, Color.WHITE))
		var s := HSlider.new()
		s.min_value = r[2]; s.max_value = r[3]; s.step = r[4]; s.value = t[r[0]]
		s.custom_minimum_size = Vector2(0, 32)
		var key: String = r[0]
		s.value_changed.connect(func(v: float): Game.set_tuning(id, key, v))
		_content.add_child(s)
		_content.add_child(UIStyle.label(r[5], 12, UIStyle.MUTED))
	var reset := Button.new(); reset.text = "RESET TUNING"
	reset.pressed.connect(func():
		for k in Game.TUNE_DEFAULTS:
			Game.set_tuning(id, k, Game.TUNE_DEFAULTS[k])
		_set_tab(4)); UIStyle.juice(reset)
	_content.add_child(reset)
	_content.add_child(UIStyle.label("Takes effect on your next drive.", 12, UIStyle.MUTED))


func _toggle_lights() -> void:
	_lights_on = not _lights_on
	for l in _lights:
		l.visible = _lights_on


func _flash(t: String) -> void:
	_msg.text = t
	_msg.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(_msg, "modulate:a", 0.0, 0.6)


func _refresh_info() -> void:
	if _money == null:
		return
	var d := _cars[_index]
	_money.text = Game.naira(Game.money)
	_name.text = d.display_name.to_upper()
	var owned := Game.owns(d.vehicle_id)
	_status.text = ("SELECTED  ·  " if d.vehicle_id == Game.selected_car_id else "") + ("OWNED" if owned else "PRICE  " + Game.naira(d.price_naira))
	for c in _stats.get_children():
		c.queue_free()
	var stats := [
		["POWER", clampf(d.max_drive_force / 16000.0, 0.05, 1.0)],
		["GRIP", clampf((d.lateral_grip_front - 1.0) / 0.5, 0.05, 1.0)],
		["WEIGHT", clampf(d.mass / 2600.0, 0.05, 1.0)],
		["DRIVE", -1.0],
	]
	for s in stats:
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10)
		var l := UIStyle.label(s[0], 12, UIStyle.MUTED, UIStyle.bold()); l.custom_minimum_size = Vector2(70, 0)
		row.add_child(l)
		if s[1] < 0.0:
			row.add_child(UIStyle.label(CarDatabase.drivetrain_label(d), 13, Color.WHITE, UIStyle.bold()))
		else:
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(220, 8)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.value = s[1] * 100.0
			var fg := StyleBoxFlat.new(); fg.bg_color = Y; fg.set_corner_radius_all(2)
			var bgs := StyleBoxFlat.new(); bgs.bg_color = Color(1, 1, 1, 0.12); bgs.set_corner_radius_all(2)
			bar.add_theme_stylebox_override("fill", fg); bar.add_theme_stylebox_override("background", bgs)
			row.add_child(bar)
		_stats.add_child(row)
