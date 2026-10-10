extends Camera3D
## Smooth chase camera for AdvancedPhysicsCar (forward = -Z).
## Frame-rate independent smoothing (exp decay), follows the velocity when
## drifting, and a ray keeps it from clipping into walls or the ground.

@export_node_path("RigidBody3D") var target_vehicle_path: NodePath
@export var follow_distance: float = 5.0
@export var follow_height: float = 1.8
@export var look_at_height_offset: float = 0.5
## Higher = snappier. ~6–10 feels natural (same at 30, 60 or 120 FPS).
@export var position_speed: float = 12.0
@export var rotation_speed: float = 10.0
## How much the camera swings toward the travel direction when sliding (0–1).
@export_range(0.0, 1.0) var velocity_follow: float = 0.6

var target_vehicle: RigidBody3D


func _ready() -> void:
	if target_vehicle_path.is_empty():
		if get_parent() is RigidBody3D:
			target_vehicle = get_parent()
	else:
		target_vehicle = get_node(target_vehicle_path) as RigidBody3D
	if target_vehicle:
		top_level = true   # move independently of the car's body
		global_position = target_vehicle.global_position + target_vehicle.global_basis.z * follow_distance + Vector3.UP * follow_height


func _physics_process(delta: float) -> void:
	if not target_vehicle:
		return
	var car_xf: Transform3D = target_vehicle.global_transform
	var vel: Vector3 = target_vehicle.linear_velocity
	var forward := -car_xf.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	# drifting: blend toward the direction of travel
	var flat_vel := Vector3(vel.x, 0.0, vel.z)
	if flat_vel.length() > 3.0:
		forward = forward.lerp(flat_vel.normalized(), velocity_follow).normalized()

	var target_pos: Vector3 = car_xf.origin - forward * follow_distance
	target_pos.y = car_xf.origin.y + follow_height

	# keep the camera out of walls / ground
	var query := PhysicsRayQueryParameters3D.create(car_xf.origin + Vector3.UP * 0.8, target_pos)
	query.exclude = [target_vehicle.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		target_pos = hit.position + hit.normal * 0.25

	# exponential smoothing: identical feel at any frame rate
	global_position = global_position.lerp(target_pos, 1.0 - exp(-position_speed * delta))
	var look_target: Vector3 = car_xf.origin + Vector3.UP * look_at_height_offset
	if global_position.distance_to(look_target) > 0.01:
		var target_basis := Transform3D.IDENTITY.looking_at(look_target - global_position, Vector3.UP).basis
		global_transform.basis = global_transform.basis.slerp(target_basis, 1.0 - exp(-rotation_speed * delta)).orthonormalized()
