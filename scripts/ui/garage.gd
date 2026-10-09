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
	var panel := get_node_or_null("Preview") as Control
	if panel == null:
		return
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(cont)
	panel.move_child(cont, 0)  # behind the placeholder label

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	cont.add_child(vp)

	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(35), 0)
	sun.light_energy = 1.3
	vp.add_child(sun)

	_pivot = Node3D.new()
	vp.add_child(_pivot)

	var cam := Camera3D.new()
	cam.position = Vector3(4.6, 2.0, 4.6)
	cam.look_at_from_position(cam.position, Vector3(0, 0.6, 0), Vector3.UP)
	cam.fov = 45.0
	vp.add_child(cam)


func _update_preview(d: VehicleData) -> void:
	if _pivot == null:
		return
	if _current_model:
		_current_model.queue_free()
		_current_model = null
	if d.model_scene:
		var m := d.model_scene.instantiate() as Node3D
		if m:
			m.rotation = Vector3(
				deg_to_rad(d.model_rotation_deg.x),
				deg_to_rad(d.model_rotation_deg.y),
				deg_to_rad(d.model_rotation_deg.z))
			m.scale = Vector3.ONE * d.model_scale
			_pivot.add_child(m)
			_current_model = m
		_preview_note.visible = false
	else:
		_preview_note.visible = true
		_preview_note.text = "[ %s — box placeholder\n(no model yet) ]" % d.display_name


func _process(delta: float) -> void:
	if _pivot and _current_model:
		_pivot.rotate_y(delta * 0.7)


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
