extends Control
## Garage / car select (spec §13). Cycle the roster, see stats that map to real
## physics (spec §6.3), and set your active car (persisted via Game). Preview is
## a placeholder for now; a real .glb model slots in per car id later.

var _cars: Array[VehicleData] = []
var _index: int = 0

@onready var _name: Label = %CarName
@onready var _class: Label = %ClassLabel
@onready var _stats: Label = %Stats
@onready var _selected_tag: Label = %SelectedTag
@onready var _preview_note: Label = %PreviewNote

var _pivot: Node3D
var _current_model: Node3D


func _ready() -> void:
	_cars = CarDatabase.all()
	%PrevButton.pressed.connect(func(): _cycle(-1))
	%NextButton.pressed.connect(func(): _cycle(1))
	%SelectButton.pressed.connect(_select_current)
	%BackButton.pressed.connect(func(): Game.goto_main_menu())
	_build_preview()
	_build_shop()

	# start on the currently-selected car
	for i in _cars.size():
		if _cars[i].vehicle_id == Game.selected_car_id:
			_index = i
			break
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("steer_left"):
		_cycle(-1)
	elif event.is_action_pressed("steer_right"):
		_cycle(1)
	elif event.is_action_pressed("accelerate"):
		_select_current()
	elif event.is_action_pressed("pause"):
		Game.goto_main_menu()


func _cycle(dir: int) -> void:
	if _cars.is_empty():
		return
	_index = wrapi(_index + dir, 0, _cars.size())
	_refresh()


func _select_current() -> void:
	if _cars.is_empty():
		return
	var d := _cars[_index]
	if not Game.owns(d.vehicle_id):
		if not Game.buy_car(d.vehicle_id, d.price_naira):
			_flash("Not enough money — win races to earn more")
			_refresh()
			return
		_flash("Bought %s!" % d.display_name)
	Game.set_selected_car(d.vehicle_id)
	_refresh()


# ---------- shop: money + upgrades (built in code) ----------
var _money_label: Label
var _msg_label: Label
var _up_buttons := {}


func _build_shop() -> void:
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 30)
	_money_label.add_theme_color_override("font_color", Color(0.98, 0.76, 0.12))
	_money_label.anchor_left = 1.0; _money_label.anchor_right = 1.0
	_money_label.offset_left = -420; _money_label.offset_right = -24; _money_label.offset_top = 16
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_money_label)
	var box := VBoxContainer.new()
	box.anchor_left = 1.0; box.anchor_right = 1.0; box.anchor_top = 1.0; box.anchor_bottom = 1.0
	box.offset_left = -420; box.offset_right = -24; box.offset_top = -300; box.offset_bottom = -110
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var t := Label.new(); t.text = "UPGRADES"; t.add_theme_font_size_override("font_size", 22)
	box.add_child(t)
	for kind in Game.UPGRADE_KINDS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(390, 44)
		b.add_theme_font_size_override("font_size", 18)
		var k: String = kind
		b.pressed.connect(func(): _buy_upgrade(k))
		box.add_child(b)
		_up_buttons[kind] = b
	_msg_label = Label.new()
	_msg_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_msg_label)


func _buy_upgrade(kind: String) -> void:
	var id := _cars[_index].vehicle_id
	if Game.buy_upgrade(id, kind):
		_flash("%s upgraded!" % kind.capitalize())
	else:
		_flash("Can't buy — own the car, max level, or not enough money")
	_refresh()


func _flash(msg: String) -> void:
	if _msg_label:
		_msg_label.text = msg


func _refresh_shop(d: VehicleData) -> void:
	if _money_label == null:
		return
	_money_label.text = "Money: " + Game.naira(Game.money)
	var owned := Game.owns(d.vehicle_id)
	for kind in Game.UPGRADE_KINDS:
		var lvl := Game.upgrade_level(d.vehicle_id, kind)
		var b: Button = _up_buttons[kind]
		var stars := "●".repeat(lvl) + "○".repeat(Game.MAX_UPGRADE - lvl)
		if lvl >= Game.MAX_UPGRADE:
			b.text = "%s  %s   MAX" % [kind.capitalize(), stars]
		else:
			b.text = "%s  %s   %s" % [kind.capitalize(), stars, Game.naira(Game.upgrade_cost(d.vehicle_id, kind))]
		b.disabled = not owned or lvl >= Game.MAX_UPGRADE


## Builds a small live 3D viewport inside the preview panel for a turntable of
## the selected car's model.
func _build_preview() -> void:
	# full-screen showroom behind the UI (was a small box in the middle)
	var panel := get_node_or_null("Preview") as ColorRect
	if panel:
		panel.color = Color(0, 0, 0, 0)
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cont)
	move_child(cont, 1)   # just above the background colour

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	cont.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.66)
	env.ambient_light_energy = 0.7
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	vp.add_child(sun)
	# studio spotlights from above
	for x in [-1.0, 1.0]:
		var sl := SpotLight3D.new()
		sl.position = Vector3(x * 3.5, 6.0, 2.0)
		sl.look_at_from_position(sl.position, Vector3(0, 0.5, 0), Vector3.UP)
		sl.spot_range = 14.0; sl.spot_angle = 40.0; sl.light_energy = 6.0
		sl.light_color = Color(1.0, 0.95, 0.88)
		vp.add_child(sl)
	# glossy turntable floor + rim
	var floor_mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new(); cyl.top_radius = 4.2; cyl.bottom_radius = 4.2; cyl.height = 0.08
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.09, 0.09, 0.1); fm.metallic = 0.7; fm.roughness = 0.12
	cyl.material = fm
	floor_mi.mesh = cyl
	floor_mi.position = Vector3(0, -0.04, 0)
	vp.add_child(floor_mi)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new(); tor.inner_radius = 4.15; tor.outer_radius = 4.3
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.98, 0.76, 0.12); rm.emission_enabled = true
	rm.emission = Color(0.98, 0.76, 0.12); rm.emission_energy_multiplier = 2.0
	tor.material = rm
	ring.mesh = tor
	vp.add_child(ring)

	_pivot = Node3D.new()
	vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	vp.add_child(_cam)
	_horn = AudioStreamPlayer.new()
	_horn.stream = load("res://assets/audio/horn.ogg")
	add_child(_horn)
	_build_showroom_buttons()


var _cam: Camera3D
var _horn: AudioStreamPlayer
var _yaw := 0.7
var _pitch := 0.25
var _dist := 6.2
var _idle := 99.0
var _drag := false
var _lights_on := false
var _lights: Array[Node3D] = []
const PAINTS := [null, Color(0.85, 0.08, 0.08), Color(0.05, 0.05, 0.06), Color(0.95, 0.95, 0.95),
	Color(0.1, 0.25, 0.75), Color(0.98, 0.76, 0.12), Color(0.1, 0.55, 0.25), Color(0.55, 0.1, 0.6),
	Color(0.95, 0.45, 0.05), Color(0.6, 0.62, 0.66)]


func _build_showroom_buttons() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 1.0; box.anchor_right = 1.0; box.anchor_top = 0.0
	box.offset_left = -190; box.offset_right = -20; box.offset_top = 110
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	for spec in [["HEADLIGHTS", _toggle_lights], ["HORN", func(): _horn.play()], ["PAINT", func(): _paint(1)], ["FACTORY PAINT", func(): _paint(0)]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(170, 52)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(spec[1])
		box.add_child(b)
	var hint := Label.new()
	hint.text = "Drag to look around 360°"
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)


func _toggle_lights() -> void:
	_lights_on = not _lights_on
	for l in _lights:
		l.visible = _lights_on


func _paint(step: int) -> void:
	if _cars.is_empty():
		return
	var id := String(_cars[_index].vehicle_id)
	var cur = Game.car_color(id)
	var i := 0
	if step != 0:
		for k in PAINTS.size():
			if PAINTS[k] != null and cur != null and (PAINTS[k] as Color).is_equal_approx(cur):
				i = k
		i = (i + 1) % PAINTS.size()
	Game.set_car_color(id, PAINTS[i])
	_update_preview(_cars[_index])


func _input(event: InputEvent) -> void:
	# 360° orbit: mouse drag / touch drag anywhere that isn't a button
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed and get_viewport().gui_get_hovered_control() == null
	elif event is InputEventMouseMotion and _drag:
		_orbit(event.relative)
	elif event is InputEventScreenDrag:
		_orbit(event.relative)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_dist = clampf(_dist + (-0.4 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.4), 3.5, 10.0)


func _orbit(rel: Vector2) -> void:
	_yaw -= rel.x * 0.008
	_pitch = clampf(_pitch + rel.y * 0.005, -0.05, 1.2)
	_idle = 0.0


func _update_preview(d: VehicleData) -> void:
	if _pivot == null:
		return
	if _current_model:
		_current_model.free()
		_current_model = null
	_lights.clear()
	if d.model_scene:
		var m := d.model_scene.instantiate() as Node3D
		if m:
			m.rotation = Vector3(
				deg_to_rad(d.model_rotation_deg.x),
				deg_to_rad(d.model_rotation_deg.y),
				deg_to_rad(d.model_rotation_deg.z))
			m.scale = Vector3.ONE * d.model_scale
			m.position = d.model_offset + Vector3(0, 0.5, 0)
			var col = Game.car_color(String(d.vehicle_id))
			if col != null:
				VehicleController.paint_model(m, col)
			var holder := Node3D.new()
			holder.add_child(m)
			_pivot.add_child(holder)
			_current_model = holder
			# headlights at the front (+Z) of the car's bounds
			var ab := _aabb(holder)
			for x in [-0.32, 0.32]:
				var sl := SpotLight3D.new()
				sl.position = Vector3(ab.get_center().x + ab.size.x * x, ab.position.y + ab.size.y * 0.38, ab.end.z - 0.05)
				sl.spot_range = 18.0; sl.spot_angle = 28.0; sl.light_energy = 8.0
				sl.light_color = Color(1.0, 0.97, 0.9)
				holder.add_child(sl)
				var glow := MeshInstance3D.new()
				var sp := SphereMesh.new(); sp.radius = 0.09; sp.height = 0.18
				var gm := StandardMaterial3D.new()
				gm.emission_enabled = true; gm.emission = Color(1, 0.97, 0.88); gm.emission_energy_multiplier = 6.0
				gm.albedo_color = Color.WHITE
				sp.material = gm
				glow.mesh = sp
				glow.position = sl.position
				holder.add_child(glow)
				sl.visible = _lights_on; glow.visible = _lights_on
				_lights.append(sl); _lights.append(glow)
		_preview_note.visible = false
	else:
		_preview_note.visible = true
		_preview_note.text = "[ %s — box placeholder\n(no model yet) ]" % d.display_name


func _aabb(n: Node3D) -> AABB:
	var out := AABB(); var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		var xf := n.global_transform.affine_inverse() * g.global_transform if n.is_inside_tree() else g.transform
		var bb: AABB = xf * g.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


func _process(delta: float) -> void:
	if _cam == null:
		return
	_idle += delta
	if _idle > 3.0:
		_yaw += delta * 0.35   # slow turntable when you're not dragging
	var target := Vector3(0, 0.8, 0)
	_cam.position = target + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_cam.look_at(target, Vector3.UP)


func _refresh() -> void:
	if _cars.is_empty():
		_name.text = "(no cars)"
		return
	var d := _cars[_index]
	_update_preview(d)
	_name.text = d.display_name
	_class.text = "%s   ·   ₦%s   ·   %d kg" % [
		CarDatabase.drivetrain_label(d), _naira(d.price_naira), int(d.mass)]

	var r := CarDatabase.ratings(d)
	_stats.text = "\n".join([
		_bar("TOP SPEED", r["top_speed"]),
		_bar("ACCEL    ", r["accel"]),
		_bar("GRIP     ", r["grip"]),
		_bar("BRAKING  ", r["braking"]),
		_bar("WEIGHT   ", r["weight"]),
	])

	var is_sel := d.vehicle_id == Game.selected_car_id
	var owned := Game.owns(d.vehicle_id)
	_selected_tag.text = "✔ SELECTED" if is_sel else ("OWNED" if owned else "🔒 " + Game.naira(d.price_naira))
	if is_sel:
		%SelectButton.text = "Selected"
	elif owned:
		%SelectButton.text = "Select this car"
	else:
		%SelectButton.text = "Buy for " + Game.naira(d.price_naira)
	%SelectButton.disabled = is_sel
	_refresh_shop(d)


static func _bar(label: String, v: float) -> String:
	var filled := int(round(clampf(v, 0.0, 1.0) * 20.0))
	return "%s  %s%s" % [label, "█".repeat(filled), "░".repeat(20 - filled)]


static func _naira(amount: int) -> String:
	var s := str(amount)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
