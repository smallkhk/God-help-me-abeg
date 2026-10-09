extends Node
## Reads InputMap actions and feeds them to a sibling/parent VehicleController.
## Kept separate from the controller so the same physics can later be driven by
## traffic/police AI instead of a human (spec §9.3: controller owns forces, this
## only supplies input). Attach as a child of the vehicle, or set `vehicle_path`.

@export var vehicle_path: NodePath
@export var manual_shifting: bool = false

var _vehicle: VehicleController


func _ready() -> void:
	if vehicle_path.is_empty():
		_vehicle = get_parent() as VehicleController
	else:
		_vehicle = get_node_or_null(vehicle_path) as VehicleController
	if _vehicle == null:
		push_error("player_driver: no VehicleController found.")
		set_physics_process(false)
		return
	var audio := CarAudio.new()
	audio.vehicle = _vehicle
	_vehicle.add_child.call_deferred(audio)


func _physics_process(_delta: float) -> void:
	# Invert steering at the input: the car's forward is +Z with up +Y, so the
	# car's real right side is forward×up = -X (world +X is its left). get_axis
	# returns +1 for a right press, so we negate it so "right" steers the car to
	# the driver's right (toward -X / screen-right). AI traffic steers by geometry
	# and is unaffected, so the fix belongs here, on player input only.
	var steer := -Input.get_axis("steer_left", "steer_right")
	var throttle := Input.get_action_strength("accelerate")
	var brake := Input.get_action_strength("brake")
	var handbrake := Input.is_action_pressed("handbrake")
	_vehicle.set_driver_input(throttle, brake, steer, handbrake)

	if manual_shifting:
		_vehicle.transmission.automatic = false
		if Input.is_action_just_pressed("gear_up"):
			_vehicle.transmission.shift_up()
		if Input.is_action_just_pressed("gear_down"):
			_vehicle.transmission.shift_down()
	else:
		_vehicle.transmission.automatic = true
