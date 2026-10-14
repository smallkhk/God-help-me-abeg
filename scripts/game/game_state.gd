extends Node
## Global game state (autoloaded as `Game`). Holds the player's current choices
## that must survive scene changes — selected car, settings — and bridges them to
## the on-disk save (spec §16). Scene routing goes through here so there is one
## place that knows the game's scene layout.

signal settings_changed

## High = photo skies, glow, long shadows, all props. F6 in-game toggles.
var high_graphics: bool = true
## 0 = day … 1 = night; set by TimeOfDay, read by car lights.
var night: float = 0.0
## Free roam: drive the map with no race (gates/rivals/timer off)
var free_roam := false

const SCENE_MAIN_MENU := "res://scenes/ui/menus/main_menu.tscn"
const SCENE_TEST_TRACK := "res://scenes/world/test_track.tscn"
const SCENE_BRIDGE := "res://scenes/world/maps/lagos_bridge/lagos_bridge.tscn"
const SCENE_LEKKI := "res://scenes/world/maps/lekki/lekki.tscn"
const SCENE_GARAGE := "res://scenes/ui/menus/garage.tscn"

var selected_car_id: StringName = &"corolla_01"

# --- career / economy ---
const START_MONEY := 2000000
const STARTER_CARS := ["corolla_01", "keke_01"]
const UPGRADE_KINDS := ["engine", "tyres", "brakes", "suspension", "nitro"]
const MAX_UPGRADE := 3
var money: int = START_MONEY
var owned: Array = []                 # car ids (String)
var upgrades: Dictionary = {}         # car id -> {engine:int, tyres:int, nitro:int}
var settings: Dictionary = {}


func _ready() -> void:
	_start_music()
	_add_gamepad()
	var data := SaveManager.load_data()
	settings = data.get("settings", {})
	# phones start on Low graphics (still switchable in Settings)
	high_graphics = bool(settings.get("high_graphics", not OS.has_feature("mobile")))
	# phones on the Mobile renderer (Metal on iOS) get the full look once:
	# photo sky, bloom, car reflections, building shadows
	if RenderingServer.get_current_rendering_method() == "mobile" and int(settings.get("gfx_profile", 0)) < 2:
		high_graphics = true
		settings["high_graphics"] = true
		settings["gfx_profile"] = 2
	# back on Compatibility after the Mobile-renderer test build: phone default (Low) again
	elif OS.has_feature("mobile") and RenderingServer.get_current_rendering_method() == "gl_compatibility" and int(settings.get("gfx_profile", 0)) == 2:
		high_graphics = false
		settings["high_graphics"] = false
		settings["gfx_profile"] = 3
	AudioServer.set_bus_volume_db(0, linear_to_db(float(settings.get("volume", 0.8))))
	money = int(data.get("money", START_MONEY))
	# owner's request: plenty money to buy every car and upgrade
	money = maxi(money, 1000000000)
	owned = data.get("owned", STARTER_CARS.duplicate())
	upgrades = data.get("upgrades", {})
	for c in STARTER_CARS:   # starter cars are always owned (also on old saves)
		if not owned.has(c):
			owned.append(c)
	if data.has("selected_car") and typeof(data["selected_car"]) == TYPE_STRING:
		selected_car_id = StringName(data["selected_car"])
	if not owned.has(String(selected_car_id)) or not CarDatabase.ORDER.has(selected_car_id):
		selected_car_id = &"corolla_01"


func save() -> void:
	var data := SaveManager.load_data()
	data["settings"] = settings
	data["selected_car"] = String(selected_car_id)
	data["money"] = money
	data["owned"] = owned
	data["upgrades"] = upgrades
	SaveManager.save_data(data)


func set_setting(key: String, value) -> void:
	settings[key] = value
	save()
	settings_changed.emit()


func get_setting(key: String, default_value):
	return settings.get(key, default_value)


func set_selected_car(car_id: StringName) -> void:
	selected_car_id = car_id
	save()


func goto_free_roam(scene_path: String) -> void:
	free_roam = true
	goto(scene_path)


func goto(scene_path: String) -> void:
	# Always unpause before switching, or the next scene loads frozen.
	get_tree().paused = false
	if scene_path.contains("/maps/"):
		_load_with_screen(scene_path)   # race maps: loading screen, no frozen menu
	else:
		get_tree().change_scene_to_file(scene_path)


const _TIPS := ["Hold BRAKE when stopped to reverse.", "Nitro works best on the straights.",
	"Okadas get knocked over — danfos and trucks don't.", "Upgrade tyres in the garage for more grip.",
	"Rivals have personalities: Tunde fights dirty, Bisi races clean.", "Lagos never sleeps."]
var _loading := false


## Shows a loading screen at once, loads the race scene (models, textures) on a
## background thread with a progress bar, switches scene, and fades the screen
## out after the map has been built.
func _load_with_screen(path: String) -> void:
	if _loading:
		return
	_loading = true
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var title := Label.new()
	title.text = "LOADING…"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.98, 0.76, 0.12))
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.offset_left = -400; title.offset_right = 400; title.offset_top = -90; title.offset_bottom = -20
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bg.add_child(title)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.set_anchors_preset(Control.PRESET_CENTER)
	bar.offset_left = -300; bar.offset_right = 300; bar.offset_top = 0; bar.offset_bottom = 14
	var fill := StyleBoxFlat.new(); fill.bg_color = Color(0.98, 0.76, 0.12); fill.set_corner_radius_all(7)
	var back := StyleBoxFlat.new(); back.bg_color = Color(1, 1, 1, 0.1); back.set_corner_radius_all(7)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	bg.add_child(bar)
	var tip := Label.new()
	tip.text = _TIPS[randi() % _TIPS.size()]
	tip.add_theme_font_size_override("font_size", 22)
	tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	tip.set_anchors_preset(Control.PRESET_CENTER)
	tip.offset_left = -500; tip.offset_right = 500; tip.offset_top = 40; tip.offset_bottom = 80
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bg.add_child(tip)
	await get_tree().process_frame
	await get_tree().process_frame          # make sure the screen is on display
	var packed: PackedScene = null
	if ResourceLoader.load_threaded_request(path) == OK:
		var prog := []
		while true:
			var st := ResourceLoader.load_threaded_get_status(path, prog)
			if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				bar.value = 80.0 * float(prog[0]) if not prog.is_empty() else bar.value
				await get_tree().process_frame
				continue
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				packed = ResourceLoader.load_threaded_get(path)
			break
	bar.value = 85.0
	title.text = "BUILDING LAGOS…"
	await get_tree().process_frame
	if packed:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(path)
	# the map builds itself in the new scene's _ready; keep the screen up until then
	for i in 3:
		await get_tree().process_frame
	bar.value = 100.0
	var tw := create_tween()
	tw.tween_property(bg, "modulate:a", 0.0, 0.35)
	await tw.finished
	layer.queue_free()
	_loading = false


func goto_main_menu() -> void:
	free_roam = false
	goto(SCENE_MAIN_MENU)


# ---------------- economy ----------------

func owns(car_id: StringName) -> bool:
	return owned.has(String(car_id))


func add_money(amount: int) -> void:
	money += amount
	save()


## Returns true if bought.
func buy_car(car_id: StringName, price: int) -> bool:
	if owns(car_id) or money < price:
		return false
	money -= price
	owned.append(String(car_id))
	save()
	return true


func upgrade_level(car_id: StringName, kind: String) -> int:
	return int(upgrades.get(String(car_id), {}).get(kind, 0))


## Price of the next level: scales with the car's price.
func upgrade_cost(car_id: StringName, kind: String) -> int:
	var d := CarDatabase.get_data(car_id)
	var base := maxi(int((d.price_naira if d else 2000000) * 0.12), 150000)
	return base * (upgrade_level(car_id, kind) + 1)


func buy_upgrade(car_id: StringName, kind: String) -> bool:
	var lvl := upgrade_level(car_id, kind)
	var cost := upgrade_cost(car_id, kind)
	if lvl >= MAX_UPGRADE or money < cost or not owns(car_id):
		return false
	money -= cost
	var u: Dictionary = upgrades.get(String(car_id), {})
	u[kind] = lvl + 1
	upgrades[String(car_id)] = u
	save()
	return true


static func naira(amount: int) -> String:
	var s := str(absi(amount))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return "₦" + out


## Background music (generated Afrobeats / Amapiano instrumentals), alternating.
var _music: AudioStreamPlayer
var _track := 0
# Kevin MacLeod (incompetech.com), CC-BY 4.0
const MUSIC := ["res://assets/audio/music/rocket.ogg", "res://assets/audio/music/hitman.ogg",
	"res://assets/audio/music/movement_proposition.ogg", "res://assets/audio/music/ouroboros.ogg",
	"res://assets/audio/music/rhinoceros.ogg"]
func _start_music() -> void:
	_music = AudioStreamPlayer.new()
	_music.volume_db = -16.0
	_track = randi() % MUSIC.size()
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_music.finished.connect(_next_track)
	_next_track()


func _next_track() -> void:
	var st: AudioStream = load(MUSIC[_track % MUSIC.size()])
	_track += 1
	if st:
		_music.stream = st
		_music.play()


## Gamepad (MFi / PlayStation / Xbox pads work on iPhone and PC): RT gas,
## LT brake, left stick steer, A/✕ handbrake, X/□ nitro, Y/△ camera, B/○ look
## back, Start pause, D-pad up = day/night, D-pad down = rain, R3 horn.
func _add_gamepad() -> void:
	var axes := {"accelerate": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "brake": [JOY_AXIS_TRIGGER_LEFT, 1.0],
		"steer_left": [JOY_AXIS_LEFT_X, -1.0], "steer_right": [JOY_AXIS_LEFT_X, 1.0]}
	var btns := {"handbrake": JOY_BUTTON_A, "nitro": JOY_BUTTON_X, "camera_next": JOY_BUTTON_Y,
		"look_back": JOY_BUTTON_B, "pause": JOY_BUTTON_START, "time_next": JOY_BUTTON_DPAD_UP,
		"weather_toggle": JOY_BUTTON_DPAD_DOWN, "horn": JOY_BUTTON_RIGHT_STICK, "restart": JOY_BUTTON_BACK}
	for a in axes:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		var e := InputEventJoypadMotion.new()
		e.axis = axes[a][0]; e.axis_value = axes[a][1]
		InputMap.action_add_event(a, e)
	for a in btns:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		var b := InputEventJoypadButton.new()
		b.button_index = btns[a]
		InputMap.action_add_event(a, b)
	# pad A = click / select in menus, B = back
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var pb := InputEventJoypadButton.new(); pb.button_index = pair[1]
		InputMap.action_add_event(pair[0], pb)
	Engine.max_fps = int(get_setting("max_fps", 60))
	for a in ["time_next", "weather_toggle", "horn"]:
		var k := InputEventKey.new()
		k.physical_keycode = {"time_next": KEY_N, "weather_toggle": KEY_Y, "horn": KEY_H}[a]
		InputMap.action_add_event(a, k)


## Per-car paint colour (garage), null = factory colour.
func car_color(car_id: String):
	var c = settings.get("color_" + car_id, null)
	return Color.html(c) if c is String else null


func set_car_color(car_id: String, col) -> void:
	if col == null:
		settings.erase("color_" + car_id)
	else:
		settings["color_" + car_id] = (col as Color).to_html(false)
	save()


## Garage TUNING: per-car handling setup (real VehicleData multipliers).
## grip_balance −1 (more front grip) .. +1 (more rear grip); stiffness 0.8–1.25;
## brake_bias 0.5–0.75 (front share); steer_speed 0.7–1.3.
const TUNE_DEFAULTS := {"grip_balance": 0.0, "stiffness": 1.0, "brake_bias": 0.6, "steer_speed": 1.0}
func tuning(car_id: String) -> Dictionary:
	var t: Dictionary = TUNE_DEFAULTS.duplicate()
	t.merge(settings.get("tune_" + car_id, {}), true)
	return t


func set_tuning(car_id: String, key: String, value: float) -> void:
	var t: Dictionary = settings.get("tune_" + car_id, {})
	t[key] = value
	settings["tune_" + car_id] = t
	save()


## Garage CUSTOMIZE: window tint 0 (clear) .. 1 (limo black), per car.
func window_tint(car_id: String) -> float:
	return float(settings.get("tint_" + car_id, 0.55))


func set_window_tint(car_id: String, v: float) -> void:
	settings["tint_" + car_id] = v
	save()
