extends Node
class_name RivalDriver
## Race AI. Feeds the same VehicleController as the player. Follows the route in
## a lane, drives near flat-out, slows for bends, swaps lanes to pass slower cars
## and rubber-bands a little toward the player so races stay close.
## Drives like a person, not a robot: each rival has an aggression level — when
## side by side it sometimes swings into the player, it defends its line when
## the player tries to pass, and now and then it brakes late or wobbles.

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
var aggression := 0.5     # 0 = clean racer, 1 = dirty: how often it bumps / blocks
var road_half := 8.0      # kerb distance from the centre line (m)
## Alternative routes it may take: [{"from": route idx, "to": route idx, "pts": Array[Vector3]}]
var shortcuts: Array = []
var _sc := -1             # shortcut being driven, or -1
var _sc_i := 0
var _sc_lane := 0.0
var _sc_seen := {}        # shortcut -> lap it was last considered on

var _vehicle: VehicleController
var _lane_timer := 0.0
var _stuck := 0.0
var _attack := 0.0        # seconds left of a deliberate swing at the player
var _attack_lane := 0.0
var _cool := 4.0          # time before it may attack / block again
var _mistake := 0.0       # seconds left of a late-braking mistake
var _mistake_in := 20.0
var _wobble := 0.0
var _base_lane := 5.9
var _blocked_by_player := false


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
	if _sc >= 0:
		_drive_shortcut(delta, pos)
		return
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
	_consider_shortcuts()
	if _sc >= 0:
		return
	_human(delta, pos, speed)
	var look := 3 + int(speed / 8.0)
	var target := _lane_point(_ahead(progress, look))
	var to_t := target - pos
	var fwd := _vehicle.global_transform.basis.z
	var right := _vehicle.global_transform.basis.x
	var steer := clampf(atan2(to_t.dot(right), maxf(to_t.dot(fwd), 0.1)) * 1.4, -1.0, 1.0)
	# hands aren't perfectly steady
	_wobble += delta
	steer = clampf(steer + sin(_wobble * 1.7) * 0.025 * (1.0 - skill * 0.5), -1.0, 1.0)

	# bend ahead → safe speed
	var h0: float = route[progress]["heading_rad"]
	var h1: float = route[_ahead(progress, 25)]["heading_rad"]
	var turn := absf(wrapf(h1 - h0, -PI, PI))
	var top := lerpf(46.0, 62.0, skill)
	var safe := clampf(top - turn * 90.0, 18.0, top)
	if _mistake > 0.0:
		safe += 7.0   # brakes too late for this bend

	# rubber band: chase when behind the player, ease off a bit when far ahead
	if player:
		var gap := (player.global_position - pos).dot(fwd)
		safe *= clampf(1.0 + gap * 0.002, 0.88, 1.12)

	# blocked ahead (racer or street traffic) → change lane, brake if it's close
	_lane_timer -= delta
	var gap := _blocked(pos, fwd)
	if _attack > 0.0 and _blocked_by_player:
		gap = -1.0    # it means to hit you: no braking for the player
	if _lane_timer <= 0.0 and gap > 0.0 and _attack <= 0.0:
		var options := lanes.filter(func(l): return absf(l - lane_offset) > 0.1)
		if not options.is_empty():
			lane_offset = options[randi() % options.size()]
		_lane_timer = 2.5
	if gap > 0.0 and gap < 4.0 + speed * 0.35:
		safe = minf(safe, maxf(gap - 3.0, 0.0) * 0.8)

	var throttle := 1.0 if speed < safe else 0.0
	var brake := clampf((speed - safe) / 10.0, 0.0, 0.8) if speed > safe + 2.0 else 0.0
	_vehicle.set_driver_input(throttle, brake, steer, false)


## Human-like racing: swing into the player when alongside, defend when the
## player is right behind, the odd late-braking mistake.
func _human(delta: float, pos: Vector3, speed: float) -> void:
	_cool -= delta
	_mistake -= delta
	_mistake_in -= delta
	if _mistake_in <= 0.0:
		_mistake_in = randf_range(18.0, 45.0) * (0.6 + skill)
		_mistake = randf_range(0.6, 1.3)
	if _attack > 0.0:
		_attack -= delta
		lane_offset = lerpf(lane_offset, _attack_lane, clampf(delta * 3.0, 0.0, 1.0))
		if _attack <= 0.0:
			lane_offset = _base_lane
		return
	if player == null or _cool > 0.0 or speed < 8.0:
		return
	var s = route[progress]
	var h: float = s["heading_rad"]
	var fwd := Vector3(sin(h), 0.0, cos(h))
	var side := Vector3(cos(h), 0.0, -sin(h))
	var rel := player.global_position - pos
	var along := rel.dot(fwd)
	var player_lane: float = (player.global_position - Vector3(s["x"], 0.0, s["z"])).dot(side)
	player_lane = clampf(player_lane, -road_half + 1.5, road_half - 1.5)
	var my_lane: float = (pos - Vector3(s["x"], 0.0, s["z"])).dot(side)
	_cool = 0.5   # look again soon
	if absf(along) < 5.0 and absf(player_lane - my_lane) < 4.5:
		# side by side: sometimes lean on the player
		if randf() < aggression * 0.35:
			_base_lane = lane_offset
			_attack_lane = player_lane
			_attack = randf_range(0.8, 1.4)
			_cool = randf_range(6.0, 12.0) * (1.4 - aggression)
	elif along < -2.0 and along > -14.0 and absf(player_lane - my_lane) > 1.2:
		# player behind, moving over to pass: cover the inside
		if randf() < aggression * 0.25:
			_base_lane = lane_offset
			_attack_lane = clampf(player_lane, -road_half + 1.5, road_half - 1.5)
			_attack = randf_range(1.0, 1.8)
			_cool = randf_range(8.0, 14.0) * (1.4 - aggression)


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
	_blocked_by_player = false
	var space := _vehicle.get_world_3d().direct_space_state
	var from := pos + fwd * 2.4 + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 18.0)
	q.exclude = [_vehicle.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1.0
	var col = hit.get("collider")
	_blocked_by_player = col == player
	if col is VehicleController or col is AnimatableBody3D:
		return from.distance_to(hit["position"])
	return -1.0


## Coming up to a shortcut entrance: braver drivers dive in more often.
func _consider_shortcuts() -> void:
	for k in shortcuts.size():
		var sc: Dictionary = shortcuts[k]
		var f: int = sc["from"]
		if progress < f - 14 or progress > f - 2 or int(_sc_seen.get(k, -1)) == wraps:
			continue
		_sc_seen[k] = wraps
		if randf() < 0.25 + aggression * 0.5:
			_sc = k
			_sc_i = 0
			_sc_lane = randf_range(-1.2, 1.2)
			return


func _sc_point(pts: Array, i: int) -> Vector3:
	var k := clampi(i, 0, pts.size() - 2)
	var a: Vector3 = pts[k]
	var b: Vector3 = pts[k + 1]
	var d := (b - a).normalized()
	a = pts[mini(i, pts.size() - 1)]
	return a + Vector3(d.z, 0.0, -d.x) * _sc_lane


## Narrow back street: follow its centre line, slower, then rejoin the circuit.
func _drive_shortcut(delta: float, pos: Vector3) -> void:
	var sc: Dictionary = shortcuts[_sc]
	var pts: Array = sc["pts"]
	while _sc_i < pts.size() - 1 and _flat(pts[_sc_i]).distance_to(_flat(pos)) < 7.0:
		_sc_i += 1
	if _sc_i >= pts.size() - 2:
		progress = int(sc["to"])
		_sc = -1
		return
	var speed := _vehicle.linear_velocity.length()
	if speed < 1.0:
		_stuck += delta
	else:
		_stuck = 0.0
	if _stuck > 4.0 or _vehicle.global_transform.basis.y.y < 0.3 and speed < 2.0:
		_stuck = 0.0
		var i := mini(_sc_i + 2, pts.size() - 2)
		var p0: Vector3 = pts[i]; var p1: Vector3 = pts[i + 1]
		_vehicle.linear_velocity = Vector3.ZERO
		_vehicle.angular_velocity = Vector3.ZERO
		_vehicle.global_transform = Transform3D(Basis(Vector3.UP, atan2(p1.x - p0.x, p1.z - p0.z)), p0 + Vector3.UP * 0.8)
		if _vehicle.has_method("reset_state"):
			_vehicle.reset_state()
		_sc_i = i
		return
	var target := _sc_point(pts, _sc_i + 2 + int(speed / 8.0))
	var to_t := target - pos
	var fwd := _vehicle.global_transform.basis.z
	var right := _vehicle.global_transform.basis.x
	var steer := clampf(atan2(to_t.dot(right), maxf(to_t.dot(fwd), 0.1)) * 1.5, -1.0, 1.0)
	var a: Vector3 = pts[_sc_i]; var b: Vector3 = pts[mini(_sc_i + 1, pts.size() - 1)]
	var c: Vector3 = pts[mini(_sc_i + 8, pts.size() - 2)]; var e: Vector3 = pts[mini(_sc_i + 9, pts.size() - 1)]
	var turn := absf(wrapf(atan2(e.x - c.x, e.z - c.z) - atan2(b.x - a.x, b.z - a.z), -PI, PI))
	var top := lerpf(30.0, 40.0, skill)
	var safe := clampf(top - turn * 70.0, 11.0, top)
	var gap := _blocked(pos, fwd)
	if gap > 0.0 and gap < 4.0 + speed * 0.35:
		safe = minf(safe, maxf(gap - 3.0, 0.0) * 0.8)
	var throttle := 1.0 if speed < safe else 0.0
	var brake := clampf((speed - safe) / 10.0, 0.0, 0.8) if speed > safe + 2.0 else 0.0
	_vehicle.set_driver_input(throttle, brake, steer, false)
