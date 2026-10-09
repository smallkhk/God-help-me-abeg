extends Control
## Main menu (spec §3.1, §15). Entry point of the game: pick where to go.
## Buttons are wired by name so the scene stays simple.

@onready var _best_label: Label = %BestLabel


func _ready() -> void:
	%FreeDriveButton.pressed.connect(func(): Game.goto(Game.SCENE_TEST_TRACK))
	%BridgeButton.pressed.connect(func(): Game.goto(Game.SCENE_BRIDGE))
	%LekkiButton.pressed.connect(func(): Game.goto(Game.SCENE_LEKKI))
	%GarageButton.pressed.connect(func(): Game.goto(Game.SCENE_GARAGE))
	%QuitButton.pressed.connect(func(): get_tree().quit())

	var best := SaveManager.get_best_time("bridge_test_sprint")
	if best > 0.0:
		_best_label.text = "Bridge Sprint best: " + _fmt(best)
	else:
		_best_label.text = "Bridge Sprint best: —"

	%CarLabel.text = "Car: " + String(Game.selected_car_id)


static func _fmt(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	var ms := int((t - int(t)) * 1000.0)
	return "%02d:%02d.%03d" % [m, s, ms]
