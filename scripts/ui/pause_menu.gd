extends CanvasLayer
## Reusable in-game pause menu (spec §15). Lives in a world scene; call toggle()
## from the world's pause action. Runs while the tree is paused (process_mode =
## ALWAYS is set in the scene) so its buttons stay responsive.

signal restart_requested

@onready var _panel: Control = %Panel


func _ready() -> void:
	_panel.visible = false
	%ResumeButton.pressed.connect(toggle)
	%RestartButton.pressed.connect(_on_restart)
	%MenuButton.pressed.connect(func(): Game.goto_main_menu())
	%QuitButton.pressed.connect(func(): get_tree().quit())


func toggle() -> void:
	var showing := not _panel.visible
	_panel.visible = showing
	get_tree().paused = showing


func is_open() -> bool:
	return _panel.visible


func _on_restart() -> void:
	get_tree().paused = false
	_panel.visible = false
	restart_requested.emit()
	get_tree().reload_current_scene()
