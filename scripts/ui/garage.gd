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


func _ready() -> void:
	_cars = CarDatabase.all()
	%PrevButton.pressed.connect(func(): _cycle(-1))
	%NextButton.pressed.connect(func(): _cycle(1))
	%SelectButton.pressed.connect(_select_current)
	%BackButton.pressed.connect(func(): Game.goto_main_menu())

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


func _refresh() -> void:
	if _cars.is_empty():
		_name.text = "(no cars)"
		return
	var d := _cars[_index]
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
