class_name Checkpoint
extends Area3D
## A single ordered checkpoint gate (spec §11). Emits `passed` when the player
## vehicle drives through it. The race manager owns ordering; the gate only
## reports contact and shows whether it is the current target.

signal passed(index: int)

@export var index: int = 0

var _is_target: bool = false
@onready var _ring: MeshInstance3D = $Ring


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Each gate instance shares the scene's material resource by default; give
	# every gate its own copy so highlighting the target doesn't light them all.
	if _ring and _ring.material_override:
		_ring.material_override = _ring.material_override.duplicate()
	set_target(false)


func set_target(active: bool) -> void:
	_is_target = active
	if _ring and _ring.material_override is StandardMaterial3D:
		var m: StandardMaterial3D = _ring.material_override
		m.albedo_color = Color(1.0, 0.85, 0.1, 0.65) if active else Color(0.4, 0.5, 0.6, 0.3)
		m.emission_enabled = active
		m.emission = Color(1.0, 0.7, 0.0) if active else Color.BLACK


func _on_body_entered(body: Node) -> void:
	if not _is_target:
		return
	if body is VehicleController:
		passed.emit(index)
