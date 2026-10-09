extends MeshInstance3D
## 3D debug visualisation for the vehicle (spec §5.3): wheel contact points,
## suspension load, velocity vector and lateral velocity. Toggle with F3 (shares
## the debug_toggle action with the HUD overlay). Uses an ImmediateMesh so it
## costs nothing when hidden. Attach as a child of the VehicleController.

@export var vehicle_path: NodePath

var _vehicle: VehicleController
var _im: ImmediateMesh
var _mat: StandardMaterial3D
var _enabled := false


func _ready() -> void:
	_vehicle = get_node_or_null(vehicle_path) as VehicleController
	if _vehicle == null:
		_vehicle = get_parent() as VehicleController
	_im = ImmediateMesh.new()
	mesh = _im
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.no_depth_test = true
	material_override = _mat
	top_level = true
	global_position = Vector3.ZERO
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		_enabled = not _enabled
		visible = _enabled


func _process(_delta: float) -> void:
	if not _enabled or _vehicle == null:
		return
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PrimitiveType.PRIMITIVE_LINES)

	# Velocity (green) and lateral component (red) from the car centre.
	var c := _vehicle.global_position
	_line(c, c + _vehicle.linear_velocity, Color.GREEN)
	var right := _vehicle.global_transform.basis.x
	_line(c, c + right * _vehicle.lateral_speed, Color.RED)

	# Per-wheel contact + normal load (blue), slip magnitude (yellow).
	for w in _vehicle.wheels:
		if not w.grounded:
			continue
		var p := w.contact_point
		_line(p, p + Vector3.UP * (w.normal_load / (_vehicle.mass * 9.8) * 1.5), Color.CYAN)
		_cross(p, 0.15, Color.WHITE)
		var slip_len := clampf(absf(w.slip_angle) / _vehicle.data.peak_slip_angle, 0.0, 2.0)
		_line(p, p + Vector3.UP * 0.05 + right * slip_len * signf(w.slip_angle), Color.YELLOW)

	_im.surface_end()


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	_im.surface_set_color(col)
	_im.surface_add_vertex(a)
	_im.surface_set_color(col)
	_im.surface_add_vertex(b)


func _cross(p: Vector3, s: float, col: Color) -> void:
	_line(p - Vector3(s, 0, 0), p + Vector3(s, 0, 0), col)
	_line(p - Vector3(0, 0, s), p + Vector3(0, 0, s), col)
