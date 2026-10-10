extends Camera3D
## Chase camera (spec §7). Smoothly follows the target vehicle, looks slightly
## ahead at speed, and supports chase / hood / bumper views. Reads the vehicle
## transform only — it never drives vehicle movement (spec §9.3).

@export var target_path: NodePath
@export var follow_distance: float = 4.3
@export var follow_height: float = 1.55
@export var look_ahead: float = 3.0
@export var position_smooth: float = 14.0
@export var rotation_smooth: float = 8.0
@export var base_fov: float = 72.0
@export var speed_fov_gain: float = 0.1   # extra FOV per (m/s), capped
@export var max_extra_fov: float = 7.0

enum View { CHASE, HOOD, BUMPER }
var _view: int = View.CHASE

var _target: VehicleController
var _cam_pos: Vector3
# free look (360°): mouse drag (right button or any button), or touch-drag on
# empty screen; swings back behind the car ~1.5 s after you let go.
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _orbit_idle := 99.0
var _dragging := false
var _touch_id := -1

# Local mount offsets for the non-chase views (tuned to the sample car).
const HOOD_OFFSET := Vector3(0.0, 1.1, 0.6)
const BUMPER_OFFSET := Vector3(0.0, 0.55, 1.9)


func _ready() -> void:
	_target = get_node_or_null(target_path) as VehicleController
	if _target == null:
		push_warning("chase_camera: no target vehicle set.")
	fov = base_fov
	# draw distance: the haze hides the cut-off; the race only needs ~1 km
	var g := get_node_or_null("/root/Game")
	far = 1100.0 if (g == null or g.get("high_graphics")) else 750.0
	if _target:
		_cam_pos = _target.global_position
	top_level = true  # we set global transform ourselves


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_next"):
		_view = (_view + 1) % View.size()
	if event is InputEventMouseButton:
		_dragging = event.pressed and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]
	elif event is InputEventMouseMotion and _dragging:
		_orbit(event.relative)
	elif event is InputEventScreenTouch:
		# only touches that the on-screen buttons didn't take reach here
		var vp := get_viewport().get_visible_rect().size
		var free_area: bool = event.position.y < vp.y * 0.55 and event.position.y > 110.0
		if event.pressed and _touch_id == -1 and free_area:
			_touch_id = event.index
		elif not event.pressed and event.index == _touch_id:
			_touch_id = -1
	elif event is InputEventScreenDrag and event.index == _touch_id:
		_orbit(event.relative * 1.4)


func _orbit(rel: Vector2) -> void:
	_orbit_yaw = wrapf(_orbit_yaw - rel.x * 0.006, -PI, PI)
	_orbit_pitch = clampf(_orbit_pitch + rel.y * 0.004, -0.35, 0.9)
	_orbit_idle = 0.0


func _physics_process(delta: float) -> void:
	if _target == null:
		return

	var xf := _target.global_transform
	var fwd := xf.basis.z
	var up := Vector3.UP

	if _view == View.CHASE:
		var look_back := Input.is_action_pressed("look_back")
		var behind := fwd if look_back else -fwd
		# right stick / Q-E keys also orbit
		var stick := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
		if absf(stick) > 0.2:
			_orbit_yaw = wrapf(_orbit_yaw - stick * 2.5 * delta, -PI, PI); _orbit_idle = 0.0
		_orbit_idle += delta
		if _orbit_idle > 1.5 and not _dragging and _touch_id == -1:
			_orbit_yaw = lerp_angle(_orbit_yaw, 0.0, 1.0 - exp(-3.0 * delta))
			_orbit_pitch = lerpf(_orbit_pitch, 0.0, 1.0 - exp(-3.0 * delta))
		behind = Basis(up, _orbit_yaw) * behind
		var dist := follow_distance * (1.0 + _orbit_pitch * 0.3)
		var desired := xf.origin + behind * dist * cos(_orbit_pitch) + up * (follow_height + dist * sin(_orbit_pitch))
		if _cam_pos.distance_to(desired) > 60.0:
			# teleport (race start / respawn): snap instead of flying across the map
			_cam_pos = desired
			global_transform = Transform3D(Basis(), desired).looking_at(xf.origin + fwd * look_ahead, up)
		_cam_pos = _cam_pos.lerp(desired, 1.0 - exp(-position_smooth * delta))
		# never trail more than 0.8 m behind the ideal spot (stops the camera
		# drifting far back when you accelerate)
		if _cam_pos.distance_to(desired) > 0.8:
			_cam_pos = desired + (_cam_pos - desired).normalized() * 0.8
		global_position = _cam_pos
		# speed shake (subtle above ~120 km/h)
		var spd := _target.linear_velocity.length()
		if spd > 33.0:
			var amt := minf((spd - 33.0) * 0.0015, 0.04)
			global_position += Vector3(randf_range(-amt, amt), randf_range(-amt, amt), 0.0)

		var vel := _target.linear_velocity
		var ahead := xf.origin + fwd * look_ahead
		if absf(_orbit_yaw) > 0.3 or absf(_orbit_pitch) > 0.15:
			ahead = xf.origin + up * 0.8   # free look: look at the car
		elif vel.length() > 3.0:
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
	if _target.nitro_active:
		extra += 4.0
	fov = lerpf(fov, base_fov + extra, 1.0 - exp(-4.0 * delta))
