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
	Game.set_selected_car(_cars[_index].vehicle_id)
	_refresh()


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
	_selected_tag.text = "✔ SELECTED" if is_sel else ""
	%SelectButton.text = "Selected" if is_sel else "Select this car"
	%SelectButton.disabled = is_sel


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
