extends Node3D
## Lagos bridge world harness. Wires the HUD to the player, toggles pause and
## wet-road conditions (spec §4.2 rain gameplay effect). Spawn + restart for the
## sprint are owned by the RaceManager; this node stays out of that.

@export var car_path: NodePath
@export var hud_path: NodePath

var _car: VehicleController
var _hud: CanvasLayer
@onready var _pause_menu: CanvasLayer = get_node_or_null("PauseMenu")


func _ready() -> void:
	_car = get_node_or_null(car_path) as VehicleController
	_hud = get_node_or_null(hud_path) as CanvasLayer
	if _car and _hud and _hud.has_method("set_vehicle"):
		_hud.set_vehicle(_car)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _pause_menu and _pause_menu.has_method("toggle"):
			_pause_menu.toggle()
		else:
			get_tree().paused = not get_tree().paused
	elif event.is_action_pressed("interact"):
		if _car:
			_car.wetness = 0.0 if _car.wetness > 0.5 else 1.0
