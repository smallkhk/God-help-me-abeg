class_name UIStyle
extends RefCounted
## Shared look for every menu (main menu, race select, map, garage, pause):
## asphalt-black glass panels, racing-yellow accent, angled motorsport shapes,
## Bebas Neue headings + Montserrat body, Lucide icons, UI click/hover sounds.

const YELLOW := Color(0.98, 0.76, 0.12)
const YELLOW_DIM := Color(0.98, 0.76, 0.12, 0.35)
const INK := Color(0.04, 0.05, 0.07)
const PANEL := Color(0.06, 0.07, 0.09, 0.86)
const PANEL_HI := Color(0.12, 0.13, 0.16, 0.94)
const LINE := Color(1, 1, 1, 0.12)
const TEXT := Color(0.95, 0.95, 0.96)
const MUTED := Color(1, 1, 1, 0.6)
const SKEW := 0.18   # angled panels (StyleBoxFlat.skew)

static var _head: Font
static var _body: Font
static var _bold: Font
static var _theme: Theme
static var _sfx := {}


static func head() -> Font:
	if _head == null:
		_head = load("res://assets/ui/fonts/BebasNeue-Regular.ttf")
	return _head


static func body() -> Font:
	if _body == null:
		var v := FontVariation.new()
		v.base_font = load("res://assets/ui/fonts/Montserrat.ttf")
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
		_body = v
	return _body


static func bold() -> Font:
	if _bold == null:
		var v := FontVariation.new()
		v.base_font = load("res://assets/ui/fonts/Montserrat.ttf")
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
		_bold = v
	return _bold


static func icon(name: String) -> Texture2D:
	var p := "res://assets/ui/icons/%s.svg" % name
	return load(p) if ResourceLoader.exists(p) else null


## Angled glass panel.
static func box(col := PANEL, border := LINE, skew := SKEW, bw := 1, radius := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.skew = Vector2(skew, 0.0)
	s.content_margin_left = 18; s.content_margin_right = 18
	s.content_margin_top = 8; s.content_margin_bottom = 8
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	# buttons: dark angled glass, yellow when focused / hovered
	t.set_stylebox("normal", "Button", box())
	t.set_stylebox("hover", "Button", box(PANEL_HI, YELLOW, SKEW, 2))
	t.set_stylebox("focus", "Button", box(PANEL_HI, YELLOW, SKEW, 2))
	t.set_stylebox("pressed", "Button", box(YELLOW, YELLOW))
	t.set_stylebox("disabled", "Button", box(Color(0.05, 0.05, 0.06, 0.6), LINE))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", YELLOW)
	t.set_color("font_focus_color", "Button", YELLOW)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	t.set_font("font", "Button", bold())
	t.set_font_size("font_size", "Button", 18)
	# sliders
	var groove := StyleBoxFlat.new(); groove.bg_color = Color(1, 1, 1, 0.12)
	groove.content_margin_top = 3; groove.content_margin_bottom = 3; groove.set_corner_radius_all(3)
	var fill := groove.duplicate() as StyleBoxFlat; fill.bg_color = YELLOW
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_font("font", "CheckButton", body())
	t.set_stylebox("focus", "CheckButton", box(Color(0, 0, 0, 0), YELLOW, 0.0, 2))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 0.0))
	_theme = t
	return t


static func label(text: String, size := 18, col := TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	return l


static func title(text: String, size := 44, col := TEXT) -> Label:
	return label(text, size, col, head())


## Plays a UI sound (hover / click / slide). Uses one player per kind.
static func sfx(owner: Node, kind: String) -> void:
	if owner == null or not owner.is_inside_tree():
		return
	var tree := owner.get_tree()
	var p: AudioStreamPlayer = _sfx.get(kind)
	if p == null or not is_instance_valid(p):
		p = AudioStreamPlayer.new()
		p.stream = load("res://assets/audio/ui/%s.ogg" % kind)
		p.volume_db = -8.0 if kind == "hover" else -3.0
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child.call_deferred(p)
		_sfx[kind] = p
		p.call_deferred("play")
		return
	p.play()


## Hover/focus/press sounds + a small slide-in nudge on any button.
static func juice(b: BaseButton) -> void:
	b.mouse_entered.connect(func(): sfx(b, "hover"))
	b.focus_entered.connect(func(): sfx(b, "hover"))
	b.pressed.connect(func(): sfx(b, "click"))
	b.focus_mode = Control.FOCUS_ALL


## Slide + fade a control in.
static func enter(c: Control, from_x := -40.0, delay := 0.0) -> void:
	c.modulate.a = 0.0
	var p := c.position
	c.position.x += from_x
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.28).set_delay(delay)
	tw.tween_property(c, "position:x", p.x, 0.32).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


static func fmt_time(t: float) -> String:
	if t <= 0.0:
		return "—"
	return "%02d:%02d.%03d" % [int(t) / 60, int(t) % 60, int((t - int(t)) * 1000.0)]


## grab_focus on the next frame, only if the control is still on screen.
static func focus_later(c: Control) -> void:
	if c == null or not c.is_inside_tree():
		return
	c.get_tree().process_frame.connect(func():
		if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
			c.grab_focus(), CONNECT_ONE_SHOT)
