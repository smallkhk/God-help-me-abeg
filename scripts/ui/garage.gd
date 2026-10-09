extends Control
## Garage (stub for now — full car-select comes next). Shows the selected car
## and a Back button. Kept loadable so the main-menu button works today.

func _ready() -> void:
	%BackButton.pressed.connect(func(): Game.goto_main_menu())
	%Info.text = "Selected car: %s\n\n(Full garage — car select, stats, preview — coming next.)" % String(Game.selected_car_id)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Game.goto_main_menu()
