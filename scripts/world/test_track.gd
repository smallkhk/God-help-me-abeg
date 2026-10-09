extends Node3D
## Physics test-track harness (spec §5.7, Milestone 1).
##
## Owns spawn, restart and pause, wires the chase camera and HUD to the player
## car, and provides a wet/dry toggle so the wet-vs-dry acceptance test can be
## run on the same track. Also drops distance markers so braking tests can be
## read off the ground.

@export var car_path: NodePath
@export var camera_path: NodePath
@export var hud_path: NodePath
@export var spawn_path: NodePath

var _car: VehicleController
var _camera: Node
var _hud: CanvasLayer
var _spawn: Transform3D
var _paused := false


func _ready() -> void:
	_car = get_node_or_null(car_path) as VehicleController
	_camera = get_node_or_null(camera_path)
	_hud = get_node_or_null(hud_path) as CanvasLayer
	var spawn_node := get_node_or_null(spawn_path) as Node3D
	if spawn_node:
		_spawn = spawn_node.global_transform
	elif _car:
		_spawn = _car.global_transform

	if _car and _hud and _hud.has_method("set_vehicle"):
		_hud.set_vehicle(_car)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		_reset_car()
	elif event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("interact"):
		_toggle_wet()


func _reset_car() -> void:
	if _car == null:
		return
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
	# PhysicsServer needs the transform set directly for an instant teleport.
	_car.global_transform = _spawn
	_car.transmission.gear = 0
	_car.transmission.engine_rpm = _car.data.idle_rpm


func _toggle_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused


func _toggle_wet() -> void:
	if _car:
		_car.wetness = 0.0 if _car.wetness > 0.5 else 1.0
