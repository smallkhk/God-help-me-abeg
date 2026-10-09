extends Node
## Global game state (autoloaded as `Game`). Holds the player's current choices
## that must survive scene changes — selected car, settings — and bridges them to
## the on-disk save (spec §16). Scene routing goes through here so there is one
## place that knows the game's scene layout.

signal settings_changed

## High = photo skies, glow, long shadows, all props. F6 in-game toggles.
var high_graphics: bool = true

const SCENE_MAIN_MENU := "res://scenes/ui/menus/main_menu.tscn"
const SCENE_TEST_TRACK := "res://scenes/world/test_track.tscn"
const SCENE_BRIDGE := "res://scenes/world/maps/lagos_bridge/lagos_bridge.tscn"
const SCENE_LEKKI := "res://scenes/world/maps/lekki/lekki.tscn"
const SCENE_GARAGE := "res://scenes/ui/menus/garage.tscn"

var selected_car_id: StringName = &"sedan_01"
var settings: Dictionary = {}


func _ready() -> void:
	var data := SaveManager.load_data()
	settings = data.get("settings", {})
	if data.has("selected_car") and typeof(data["selected_car"]) == TYPE_STRING:
		selected_car_id = StringName(data["selected_car"])


func save() -> void:
	var data := SaveManager.load_data()
	data["settings"] = settings
	data["selected_car"] = String(selected_car_id)
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


func goto(scene_path: String) -> void:
	# Always unpause before switching, or the next scene loads frozen.
	get_tree().paused = false
	get_tree().change_scene_to_file(scene_path)


func goto_main_menu() -> void:
	goto(SCENE_MAIN_MENU)
