extends Node
class_name RivalDriver
## Race AI. Feeds the same VehicleController as the player. Follows the route in
## a lane, drives near flat-out, slows for bends, swaps lanes to pass slower cars
## and rubber-bands a little toward the player so races stay close.

var route: Array = []
var lane_offset: float = 5.9
var lanes: Array[float] = [2.4, 5.9, 9.4]
var skill: float = 0.9          # 0..1 — top speed / cornering confidence
var start_index: int = 0
var player: VehicleController
var active := false             # set true on GO

var progress: int = 0           # route sample index reached (for positions)
var finished := false
var finish_idx := -1   # race finish sample (race may be shorter than the route)
var loop := false      # closed circuit: progress wraps round the route
var laps_needed := 1   # wraps of the start line before the rival is finished
var wraps := 0

var _vehicle: VehicleController
var _lane_timer := 0.0
var _stuck := 0.0


func _ready() -> void:
	_vehicle = get_parent() as VehicleController
	progress = start_index


func _physics_process(delta: float) -> void:
	if _vehicle == null or route.size() < 2:
		return
	if not active or finished:
		_vehicle.set_driver_input(0.0, 1.0, 0.0, false)
		return
	var pos := _vehicle.global_position
	var m := route.size() - 1   # loops repeat sample 0 as the last sample
	if loop:
		var guard := 0
		while _flat(_lane_point(progress)).distance_to(_flat(pos)) < 10.0 and guard < 50:
			guard += 1
			progress += 1
			if progress >= m:
				progress = 0
				wraps += 1
				if wraps >= laps_needed:
					finished = true
					return
	else:
		while progress < route.size() - 1 and _flat(_lane_point(progress)).distance_to(_flat(pos)) < 10.0:
			progress += 1
		if progress >= route.size() - 1 or (finish_idx > 0 and progress >= finish_idx):
			finished = true
			return

	var speed := _vehicle.linear_velocity.length()
	# crashed / wedged / flipped for a few seconds: reset onto the racing line ahead
	# (queuing behind a car doesn't count — street traffic clears itself)
	if speed < 1.0:
		var q := _blocked(_vehicle.global_position, _vehicle.global_transform.basis.z)
		if q < 0.0 or q > 7.0:
			_stuck += delta
	else:
		_stuck = 0.0
	if _stuck > 4.0 or _vehicle.global_transform.basis.y.y < 0.3 and speed < 2.0:
		_stuck = 0.0
		_reset_ahead()
		return
	var look := 3 + int(speed / 8.0)
	var target := _lane_point(_ahead(progress, look))
	var to_t := target - pos
	var fwd := _vehicle.global_transform.basis.z
	var right := _vehicle.global_transform.basis.x
	var steer := clampf(atan2(to_t.dot(right), maxf(to_t.dot(fwd), 0.1)) * 1.4, -1.0, 1.0)

	# bend ahead → safe speed
	var h0: float = route[progress]["heading_rad"]
	var h1: float = route[_ahead(progress, 25)]["heading_rad"]
	var turn := absf(wrapf(h1 - h0, -PI, PI))
	var top := lerpf(46.0, 62.0, skill)
	var safe := clampf(top - turn * 90.0, 18.0, top)

	# rubber band: chase when behind the player, ease off a bit when far ahead
	if player:
		var gap := (player.global_position - pos).dot(fwd)
		safe *= clampf(1.0 + gap * 0.002, 0.88, 1.12)

	# blocked ahead (racer or street traffic) → change lane, brake if it's close
	_lane_timer -= delta
	var gap := _blocked(pos, fwd)
	if _lane_timer <= 0.0 and gap > 0.0:
		var options := lanes.filter(func(l): return absf(l - lane_offset) > 0.1)
		if not options.is_empty():
			lane_offset = options[randi() % options.size()]
		_lane_timer = 2.5
	if gap > 0.0 and gap < 4.0 + speed * 0.35:
		safe = minf(safe, maxf(gap - 3.0, 0.0) * 0.8)

	var throttle := 1.0 if speed < safe else 0.0
	var brake := clampf((speed - safe) / 10.0, 0.0, 0.8) if speed > safe + 2.0 else 0.0
	_vehicle.set_driver_input(throttle, brake, steer, false)


func _reset_ahead() -> void:
	var i := _ahead(progress, 4)
	var s = route[i]
	var h: float = s["heading_rad"]
	_vehicle.linear_velocity = Vector3.ZERO
	_vehicle.angular_velocity = Vector3.ZERO
	_vehicle.global_transform = Transform3D(Basis(Vector3.UP, h), _lane_point(i) + Vector3.UP * 0.8)
	if _vehicle.has_method("reset_state"):
		_vehicle.reset_state()
	progress = i


func _ahead(i: int, n: int) -> int:
	if loop:
		return (i + n) % (route.size() - 1)
	return mini(i + n, route.size() - 1)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _lane_point(i: int) -> Vector3:
	var s = route[i]
	var h: float = s["heading_rad"]
	return Vector3(s["x"], s.get("elev_m", 0.0), s["z"]) + Vector3(cos(h), 0.0, -sin(h)) * lane_offset


## Distance to a car (racer or street traffic) straight ahead, or -1.
func _blocked(pos: Vector3, fwd: Vector3) -> float:
	var space := _vehicle.get_world_3d().direct_space_state
	var from := pos + fwd * 2.4 + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 18.0)
	q.exclude = [_vehicle.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1.0
	var col = hit.get("collider")
	if col is VehicleController or col is AnimatableBody3D:
		return from.distance_to(hit["position"])
	return -1.0
