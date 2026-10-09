class_name SaveManager
extends RefCounted
## Minimal offline persistence for the prototype (spec §16): settings + best
## times. Writes to user:// via a temp-file-then-rename so a crash mid-write
## can't corrupt the active save. Values are validated on load; a missing or
## corrupt file yields safe defaults rather than an error.

const SAVE_PATH := "user://save_data.json"
const SCHEMA_VERSION := 1


static func _default() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"best_times": {},   # event_id -> seconds (float)
		"settings": {"assist_mode": 1, "master_volume": 1.0},
	}


static func load_data() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return _default()
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: corrupt save, using defaults.")
		return _default()
	var data: Dictionary = _default()
	# Merge known keys only (validate on load, spec §16).
	if parsed.get("best_times") is Dictionary:
		data["best_times"] = parsed["best_times"]
	if parsed.get("settings") is Dictionary:
		for k in data["settings"]:
			if parsed["settings"].has(k):
				data["settings"][k] = parsed["settings"][k]
	return data


static func save_data(data: Dictionary) -> void:
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot open temp save for writing.")
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	# Atomic-ish replace.
	var dir := DirAccess.open("user://")
	if dir:
		if dir.file_exists(SAVE_PATH.get_file()):
			dir.remove(SAVE_PATH.get_file())
		dir.rename(tmp.get_file(), SAVE_PATH.get_file())


static func get_best_time(event_id: String) -> float:
	var bt: Dictionary = load_data()["best_times"]
	return float(bt.get(event_id, 0.0))


## Records a time if it beats the stored best (or none exists). Returns true if
## a new best was saved.
static func record_time(event_id: String, seconds: float) -> bool:
	var data := load_data()
	var bt: Dictionary = data["best_times"]
	var prev := float(bt.get(event_id, 0.0))
	if prev <= 0.0 or seconds < prev:
		bt[event_id] = seconds
		data["best_times"] = bt
		save_data(data)
		return true
	return false
