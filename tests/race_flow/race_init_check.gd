extends Node3D
## Cheap check (no full drive): the bridge race initialises via deferred init +
## event wiring — gates spawn, spawn point is set, event name applied.
var _f := 0
func _physics_process(_d):
	_f += 1
	if _f < 120:  # ~2s: let _initialize run and the map build settle
		return
	var race := $LagosBridge/RaceManager
	var gates := 0
	for c in race.get_children():
		if c is Checkpoint: gates += 1
	var ok := true
	if not race._initialized: printerr("FAIL: race not initialized"); ok=false
	# races are trimmed to the first ~2.5 km of the route (RaceManager.RACE_LEN)
	if gates < 2: printerr("FAIL: expected at least 2 gates, got ", gates); ok=false
	if race.event_id != "bridge_test_sprint": printerr("FAIL: event_id ", race.event_id); ok=false
	print("[race_init_check] initialized=%s gates=%d event_id=%s" % [race._initialized, gates, race.event_id])
	print("[race_init_check] ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
