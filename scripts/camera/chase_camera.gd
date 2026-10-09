extends Camera3D
## Chase camera (spec §7). Smoothly follows the target vehicle, looks slightly
## ahead at speed, and supports chase / hood / bumper views. Reads the vehicle
## transform only — it never drives vehicle movement (spec §9.3).

@export var target_path: NodePath
@export var follow_distance: float = 4.6
@export var follow_height: float = 1.65
@export var look_ahead: float = 3.0
@export var position_smooth: float = 6.0
@export var rotation_smooth: float = 8.0
@export var base_fov: float = 72.0
@export var speed_fov_gain: float = 0.25   # extra FOV per (m/s), capped
@export var max_extra_fov: float = 18.0

enum View { CHASE, HOOD, BUMPER }
var _view: int = View.CHASE

var _target: VehicleController
var _cam_pos: Vector3

# Local mount offsets for the non-chase views (tuned to the sample car).
const HOOD_OFFSET := Vector3(0.0, 1.1, 0.6)
const BUMPER_OFFSET := Vector3(0.0, 0.55, 1.9)


func _ready() -> void:
	_target = get_node_or_null(target_path) as VehicleController
	if _target == null:
		push_warning("chase_camera: no target vehicle set.")
	fov = base_fov
	if _target:
		_cam_pos = _target.global_position
	top_level = true  # we set global transform ourselves


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_next"):
		_view = (_view + 1) % View.size()


func _physics_process(delta: float) -> void:
	if _target == null:
		return

	var xf := _target.global_transform
	var fwd := xf.basis.z
	var up := Vector3.UP

	if _view == View.CHASE:
		var look_back := Input.is_action_pressed("look_back")
		var behind := fwd if look_back else -fwd
		var desired := xf.origin + behind * follow_distance + up * follow_height
		_cam_pos = _cam_pos.lerp(desired, 1.0 - exp(-position_smooth * delta))
		global_position = _cam_pos

		var vel := _target.linear_velocity
		var ahead := xf.origin + fwd * look_ahead
		if vel.length() > 3.0:
			ahead += vel.normalized() * look_ahead * 0.5
		var target_basis := Transform3D().looking_at(ahead - global_position, up).basis
		global_transform.basis = global_transform.basis.slerp(target_basis, 1.0 - exp(-rotation_smooth * delta)).orthonormalized()
	else:
		var offset := HOOD_OFFSET if _view == View.HOOD else BUMPER_OFFSET
		global_transform = xf * Transform3D(Basis(), offset)
		# look forward from the mount
		look_at(global_position + fwd * 10.0, up)

	# Speed-reactive FOV adds a sense of velocity (spec §7).
	var extra := minf(_target.linear_velocity.length() * speed_fov_gain, max_extra_fov)
	fov = lerpf(fov, base_fov + extra, 1.0 - exp(-4.0 * delta))
