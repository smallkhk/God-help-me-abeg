extends CanvasLayer
## In-game pause (premium redesign): darkened overlay over the frozen race,
## compact angled menu (RESUME · RESTART RACE · SETTINGS · EXIT TO MAIN MENU)
## and the real race info (event, position, elapsed time) from the RaceManager.
## Same API as before: toggle(), is_open(), restart_requested.

signal restart_requested

var _root: Control
var _menu: VBoxContainer
var _settings: VBoxContainer
var _event_l: Label
var _pos_l: Label
var _time_l: Label


func _ready() -> void:
	_build()
	_root.visible = false


func _build() -> void:
	_root = Control.new()
	_root.theme = UIStyle.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var ic := TextureRect.new(); ic.texture = UIStyle.icon("flag"); ic.modulate = UIStyle.YELLOW
	ic.position = Vector2(70, 92); ic.size = Vector2(40, 40); ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_root.add_child(ic)
	var t := UIStyle.title("PAUSED", 72, Color.WHITE); t.position = Vector2(122, 66)
	_root.add_child(t)
	_menu = VBoxContainer.new()
	_menu.position = Vector2(64, 180)
	_menu.add_theme_constant_override("separation", 10)
	_root.add_child(_menu)
	for spec in [["play", "RESUME", toggle], ["rotate-ccw", "RESTART RACE", _on_restart],
			["settings", "SETTINGS", _open_settings], ["log-out", "EXIT TO MAIN MENU", func(): Game.goto_main_menu()]]:
		var b := Button.new()
		b.text = "   " + spec[1]
		b.icon = UIStyle.icon(spec[0])
		b.add_theme_constant_override("icon_max_width", 22)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(430, 58)
		b.add_theme_font_override("font", UIStyle.head())
		b.add_theme_font_size_override("font_size", 28)
		var on := UIStyle.box(UIStyle.YELLOW, UIStyle.YELLOW)
		b.add_theme_stylebox_override("focus", on)
		b.add_theme_stylebox_override("hover", on)
		for c in ["font_focus_color", "font_hover_color"]:
			b.add_theme_color_override(c, UIStyle.INK)
		b.add_theme_color_override("icon_focus_color", UIStyle.INK)
		b.add_theme_color_override("icon_hover_color", UIStyle.INK)
		b.mouse_entered.connect(func(): b.grab_focus())
		b.pressed.connect(spec[2])
		UIStyle.juice(b)
		_menu.add_child(b)
	# race info card (right)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.PANEL, UIStyle.LINE, 0.0, 1, 6))
	card.anchor_left = 1.0; card.anchor_right = 1.0
	card.offset_left = -470; card.offset_right = -50; card.offset_top = 180; card.offset_bottom = 320
	_root.add_child(card)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(UIStyle.label("CURRENT EVENT", 12, UIStyle.MUTED, UIStyle.bold()))
	_event_l = UIStyle.title("", 36, Color.WHITE); v.add_child(_event_l)
	var g := GridContainer.new(); g.columns = 2; g.add_theme_constant_override("h_separation", 40)
	v.add_child(g)
	g.add_child(UIStyle.label("POSITION", 12, UIStyle.MUTED, UIStyle.bold()))
	g.add_child(UIStyle.label("TIME", 12, UIStyle.MUTED, UIStyle.bold()))
	_pos_l = UIStyle.title("", 40, UIStyle.YELLOW); g.add_child(_pos_l)
	_time_l = UIStyle.title("", 40, Color.WHITE); g.add_child(_time_l)
	# settings sub-panel (volume + graphics), shown from SETTINGS
	_settings = VBoxContainer.new()
	_settings.position = Vector2(64, 180)
	_settings.add_theme_constant_override("separation", 14)
	_settings.visible = false
	_root.add_child(_settings)
	_settings.add_child(UIStyle.title("SETTINGS", 40, UIStyle.YELLOW))
	var vol := HSlider.new(); vol.min_value = 0; vol.max_value = 1; vol.step = 0.05
	vol.value = float(Game.get_setting("volume", 0.8)); vol.custom_minimum_size = Vector2(420, 30)
	vol.value_changed.connect(func(x: float):
		Game.set_setting("volume", x)
		AudioServer.set_bus_volume_db(0, linear_to_db(x)))
	_settings.add_child(UIStyle.label("Volume", 16, Color.WHITE, UIStyle.bold()))
	_settings.add_child(vol)
	var gfx := CheckButton.new(); gfx.text = "High graphics"
	gfx.button_pressed = Game.high_graphics
	gfx.toggled.connect(func(on: bool):
		Game.high_graphics = on
		Game.set_setting("high_graphics", on))
	_settings.add_child(gfx)
	var back := Button.new(); back.text = "‹  BACK"; back.custom_minimum_size = Vector2(200, 50)
	back.pressed.connect(_close_settings); UIStyle.juice(back)
	_settings.add_child(back)


func _open_settings() -> void:
	_menu.visible = false
	_settings.visible = true
	(_settings.get_child(2) as Control).call_deferred("grab_focus")


func _close_settings() -> void:
	_settings.visible = false
	_menu.visible = true
	(_menu.get_child(2) as Control).call_deferred("grab_focus")


func _unhandled_input(ev: InputEvent) -> void:
	if _root.visible and _settings.visible and ev.is_action_pressed("ui_cancel"):
		_close_settings()
		get_viewport().set_input_as_handled()


func _fill_info() -> void:
	var rm: Node = null
	var cs := get_tree().current_scene
	if cs:
		for n in cs.find_children("*", "Node", true, false):
			if n.get("_finish_idx") != null:
				rm = n
				break
	var ev = rm.get("event") if rm else null
	var free := bool(rm.get("_free")) if rm else false
	_event_l.text = ("FREE ROAM" if free else (String(ev.display_name).to_upper() if ev else "FREE DRIVE"))
	var pl = rm.get("_pos_label") if rm else null
	_pos_l.text = (pl.text.replace("POS ", "") if pl and pl.text != "" else "—")
	var el = rm.get("_elapsed") if rm else null
	_time_l.text = UIStyle.fmt_time(float(el)) if el != null and float(el) > 0.0 else "—"


func toggle() -> void:
	var showing := not _root.visible
	if showing:
		_fill_info()
		_settings.visible = false
		_menu.visible = true
		_root.visible = true
		_root.modulate.a = 0.0
		var tw := create_tween(); tw.tween_property(_root, "modulate:a", 1.0, 0.12)
		(_menu.get_child(0) as Control).call_deferred("grab_focus")
	else:
		_root.visible = false
	get_tree().paused = showing


func is_open() -> bool:
	return _root.visible


func _on_restart() -> void:
	get_tree().paused = false
	_root.visible = false
	restart_requested.emit()
	get_tree().reload_current_scene()
