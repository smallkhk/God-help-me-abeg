extends Node
class_name TrafficDriver
## AI driver for ambient traffic (spec §10). Feeds the SAME VehicleController the
## player uses (spec §9.3: controller owns forces, this only supplies input) so
## traffic obeys the same physics. Follows the road centerline offset into a
## lane, holds a cruise speed, and brakes for vehicles/obstacles ahead.
##
## The traffic manager sets `route`, `lane_offset`, `cruise_speed` and `start_index`
## before the car is added to the tree.

var route: Array = []          # chunk road samples: [{x,z,elev_m,heading_rad,...}]
var lane_offset: float = 4.0   # metres right of centerline (+ = right of travel)
var cruise_speed: float = 14.0 # m/s target (~50 km/h)
var start_index: int = 0

var _vehicle: VehicleController
var _idx: int = 0
var _finished := false

const LOOKAHEAD_SAMPLES := 4
const OBSTACLE_RANGE := 18.0


func _ready() -> void:
	_vehicle = get_parent() as VehicleController
	if _vehicle == null:
		push_error("traffic_driver: parent is not a VehicleController")
		set_physics_process(false)
		return
	_idx = clampi(start_index, 0, maxi(route.size() - 1, 0))


func _physics_process(_delta: float) -> void:
	if _vehicle == null or route.size() < 2:
		return

	var pos := _vehicle.global_position
	_advance_index(pos)

	# Target point: a few samples ahead, pushed into the lane.
	var target := _lane_point(mini(_idx + LOOKAHEAD_SAMPLES, route.size() - 1))
	var to_t := target - pos
	to_t.y = 0.0

	var fwd := _vehicle.global_transform.basis.z
	var right := _vehicle.global_transform.basis.x
	var steer := clampf(atan2(to_t.dot(right), maxf(to_t.dot(fwd), 0.1)) * 1.3, -1.0, 1.0)

	# Speed control: ease toward cruise, back off for obstacles ahead.
	var speed := _vehicle.linear_velocity.length()
	var target_speed := cruise_speed * _obstacle_factor(pos, fwd)
	var throttle := 0.0
	var brake := 0.0
	if speed < target_speed - 0.5:
		throttle = clampf((target_speed - speed) / 5.0, 0.15, 0.8)
	elif speed > target_speed + 1.5:
		brake = clampf((speed - target_speed) / 8.0, 0.1, 0.7)

	_vehicle.set_driver_input(throttle, brake, steer, false)

	# Reached the end of the route — stop requesting throttle.
	if _idx >= route.size() - 1:
		_vehicle.set_driver_input(0.0, 0.5, steer, false)


func _advance_index(pos: Vector3) -> void:
	# Move the progress marker forward while the next sample is behind/near us.
	while _idx < route.size() - 1:
		var p := _lane_point(_idx)
		if Vector2(p.x - pos.x, p.z - pos.z).length() < 8.0:
			_idx += 1
		else:
			break


func _lane_point(i: int) -> Vector3:
	var s = route[i]
	var h: float = s["heading_rad"]
	var perp := Vector3(cos(h), 0.0, -sin(h))  # right of travel
	return Vector3(s["x"], s.get("elev_m", 0.0), s["z"]) + perp * lane_offset


## Returns 0..1 multiplier on cruise speed: 1 = clear, lower = slow/stop for a
## vehicle detected ahead (simple forward raycast, spec §10 "brake for stopped
## vehicles and obstacles").
func _obstacle_factor(pos: Vector3, fwd: Vector3) -> float:
	var space := _vehicle.get_world_3d().direct_space_state
	var from := pos + fwd * 2.2 + Vector3.UP * 0.5
	var to := from + fwd * OBSTACLE_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [_vehicle.get_rid()]
	q.collision_mask = _vehicle.collision_mask
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 1.0
	var collider = hit.get("collider")
	if collider is VehicleController:
		var dist := pos.distance_to(hit["position"])
		return clampf((dist - 5.0) / OBSTACLE_RANGE, 0.0, 1.0)
	return 1.0
