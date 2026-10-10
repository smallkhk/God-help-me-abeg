extends Node3D
## Lagos Island street circuit: the road surface is continuous (no holes), the
## kerb-to-kerb road is free of buildings/walls, every building stands clear of
## the road, and an AI driver completes the full 2-lap race (ordered gates,
## lap counting, finish) without falling through or getting stuck.
## Run: godot --headless --path . res://tests/map_validation/island_circuit_test.tscn

const MAX_SECONDS := 420.0

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for i in 10:
		await get_tree().physics_frame
	var world := $LagosIsland
	var mb: MapBuilder = world.get_node("MapBuilder")
	var rm = world.get_node("RaceManager")
	var car: VehicleController = world.get_node("PlayerCar")
	var ch := mb.get_chunk()
	var s: Array = ch["road"]["samples"]
	var hw: float = ch["road"]["half_width_m"]
	var space := get_world_3d().direct_space_state
	# 1) road surface under every sample (both lane edges + centre)
	var holes := 0
	for i in s.size():
		var h: float = s[i]["heading_rad"]
		var pr := Vector3(cos(h), 0, -sin(h))
		for o in [-hw + 0.6, 0.0, hw - 0.6]:
			var p: Vector3 = Vector3(s[i]["x"], 10.0, s[i]["z"]) + pr * o
			var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 20.0)
			q.exclude = [car.get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				holes += 1
			elif not (hit["collider"] is VehicleController) and absf(hit["position"].y - float(s[i]["elev_m"])) > 0.3:
				holes += 1
	print("[island_test] road holes: %d" % holes)
	if holes > 0:
		_failures.append("%d road holes" % holes)
	# 2) no static geometry across the road at car height
	var blocked := 0
	for i in range(0, s.size(), 2):
		var h: float = s[i]["heading_rad"]
		var pr := Vector3(cos(h), 0, -sin(h))
		var c := Vector3(s[i]["x"], float(s[i]["elev_m"]) + 0.8, s[i]["z"])
		var q := PhysicsRayQueryParameters3D.create(c - pr * (hw - 0.3), c + pr * (hw - 0.3))
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit["collider"] is StaticBody3D and not (hit["collider"] is AnimatableBody3D):
			blocked += 1
	print("[island_test] road blocked by static geometry: %d" % blocked)
	if blocked > 0:
		_failures.append("road blocked at %d samples" % blocked)
	# 3) an AI driver races the full event
	if not rm._loop or rm._laps < 2:
		_failures.append("circuit not set up as a lap race (loop=%s laps=%d)" % [rm._loop, rm._laps])
	for pd in car.find_children("*", "PlayerDriver", true, false):
		pd.queue_free()
	var drv := RivalDriver.new()
	drv.route = s
	drv.loop = true
	drv.laps_needed = 99
	drv.lanes.assign(rm._lanes)
	drv.lane_offset = rm._lanes[-1]
	drv.skill = 0.9
	drv.progress = rm._start_idx
	car.add_child(drv)
	rm._start_countdown()
	drv.active = true
	var t := 0.0
	var lowest := 99.0
	var last := car.global_position
	var still := 0.0
	while t < MAX_SECONDS and rm._state != 3:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		lowest = minf(lowest, car.global_position.y)
		if int(t * 60.0) % 1800 == 0:
			print("[island_test] t=%.0f lap=%d gate=%d pos=%s speed=%.0f km/h" % [t, rm._lap, rm._next, car.global_position, car.linear_velocity.length() * 3.6])
		if rm._state == 2:
			still = still + 1.0 / 60.0 if car.global_position.distance_to(last) < 0.02 else 0.0
			last = car.global_position
			if still > 20.0:
				_failures.append("car stuck at %s" % car.global_position)
				break
	print("[island_test] race state=%d laps=%d/%d time=%.1f best_lap=%.1f lowest_y=%.2f" % [rm._state, rm._lap, rm._laps, rm._elapsed, rm._best_lap, lowest])
	if rm._state != 3:
		_failures.append("race not finished in %.0f s" % MAX_SECONDS)
	if lowest < 1.5:
		_failures.append("car fell below the road (y %.2f)" % lowest)
	if _failures.is_empty():
		print("[island_test] PASS")
		get_tree().quit(0)
	else:
		print("[island_test] FAIL: ", ", ".join(_failures))
		get_tree().quit(1)
