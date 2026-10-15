class_name MiniMap
extends CanvasLayer
## Race mini-map (top left): the route around the player, turning with the
## car (heading up), shortcuts in orange, rivals as red dots, the next
## checkpoint in yellow and the finish line. Tap it for the full map
## (north up, whole route); tap again to close.

var vehicle: VehicleController
var _pts: PackedVector2Array = PackedVector2Array()   # route x,z (every 3rd sample)
var _loop := false
var _shortcuts: Array = []            # Array[PackedVector2Array]
var _race: Node
var _small: Control
var _full: Control
const SIZE := 190.0
const SCALE := 0.55                   # px per metre on the small map


func _ready() -> void:
	layer = 21   # above the touch controls so it can be tapped
	_small = Control.new()
	_small.position = Vector2(14, 14)
	_small.size = Vector2(SIZE, SIZE)
	_small.clip_contents = true
	_small.mouse_filter = Control.MOUSE_FILTER_STOP
	_small.draw.connect(_draw_small)
	_small.gui_input.connect(_on_tap.bind(true))
	add_child(_small)
	_full = Control.new()
	_full.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full.visible = false
	_full.mouse_filter = Control.MOUSE_FILTER_STOP
	_full.draw.connect(_draw_full)
	_full.gui_input.connect(_on_tap.bind(false))
	add_child(_full)
	_load_route.call_deferred()


func _load_route() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mb := scene.find_child("MapBuilder", true, false)
	_race = scene.find_child("RaceManager", true, false)
	if mb == null or not mb.has_method("get_chunk"):
		return
	var ch: Dictionary = mb.get_chunk()
	if ch.is_empty():
		return
	_loop = bool(ch.get("loop", false))
	var s: Array = ch["road"]["samples"]
	for i in range(0, s.size(), 3):
		_pts.append(Vector2(s[i]["x"], s[i]["z"]))
	for sc in ch.get("shortcuts", []):
		var p := PackedVector2Array()
		for q in sc["samples"]:
			p.append(Vector2(q["x"], q["z"]))
		_shortcuts.append(p)


func _on_tap(ev: InputEvent, small: bool) -> void:
	var tapped: bool = (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT)
	if not tapped:
		return
	_full.visible = small
	_small.visible = not small
	if small:
		_small.accept_event()
	else:
		_full.accept_event()


func _process(_d: float) -> void:
	if vehicle == null or _pts.is_empty():
		return
	if _small.visible:
		_small.queue_redraw()
	if _full.visible:
		_full.queue_redraw()


# --- markers shared by both maps ---
func _markers() -> Dictionary:
	var out := {"rivals": [], "next": null, "finish": null}
	if _race == null:
		return out
	for r in _race.get("_rivals"):
		if is_instance_valid(r):
			out["rivals"].append(Vector2(r.global_position.x, r.global_position.z))
	var gates: Array = _race.get("_gates")
	if not gates.is_empty():
		var nx: int = clampi(int(_race.get("_next")), 0, gates.size() - 1)
		out["next"] = Vector2(gates[nx].global_position.x, gates[nx].global_position.z)
		var last: Node3D = gates[gates.size() - 1]
		out["finish"] = Vector2(last.global_position.x, last.global_position.z)
	return out


func _draw_route(c: CanvasItem, xf: Callable, w_road: float) -> void:
	var pts := PackedVector2Array()
	for p in _pts:
		pts.append(xf.call(p))
	if _loop and pts.size() > 1:
		pts.append(pts[0])
	c.draw_polyline(pts, Color(0, 0, 0, 0.6), w_road + 4.0, true)
	c.draw_polyline(pts, Color(0.92, 0.92, 0.95), w_road, true)
	for sc in _shortcuts:
		var sp := PackedVector2Array()
		for p in sc:
			sp.append(xf.call(p))
		c.draw_polyline(sp, Color(1.0, 0.55, 0.15), maxf(w_road * 0.6, 2.0), true)


func _draw_marks(c: CanvasItem, xf: Callable, rot: float, scale: float) -> void:
	var m := _markers()
	if m["finish"] != null:
		var f: Vector2 = xf.call(m["finish"])
		for k in 4:
			c.draw_rect(Rect2(f + Vector2((k % 2) * 5.0 - 5.0, (k / 2) * 5.0 - 5.0) * scale, Vector2(5, 5) * scale), Color.WHITE if (k % 3 == 0) else Color.BLACK)
	if m["next"] != null:
		var nxp: Vector2 = xf.call(m["next"])
		c.draw_circle(nxp, 6.0 * scale, Color(0, 0, 0, 0.6))
		c.draw_circle(nxp, 4.5 * scale, Color(1.0, 0.85, 0.1))
	for r in m["rivals"]:
		var rp: Vector2 = xf.call(r)
		c.draw_circle(rp, 4.5 * scale, Color(0, 0, 0, 0.6))
		c.draw_circle(rp, 3.2 * scale, Color(1.0, 0.25, 0.2))
	# the player: white arrow
	var pp: Vector2 = xf.call(Vector2(vehicle.global_position.x, vehicle.global_position.z))
	var tri := PackedVector2Array([Vector2(0, -9), Vector2(6, 7), Vector2(0, 3), Vector2(-6, 7)])
	for i in tri.size():
		tri[i] = pp + tri[i].rotated(rot) * scale
	c.draw_colored_polygon(tri, Color(0.2, 0.75, 1.0))
	c.draw_polyline(tri + PackedVector2Array([tri[0]]), Color.WHITE, 1.5, true)


func _draw_small() -> void:
	var c := _small
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.05, 0.07, 0.1, 0.72))
	var me := Vector2(vehicle.global_position.x, vehicle.global_position.z)
	var b := vehicle.global_transform.basis
	var fwd := Vector2(b.z.x, b.z.z).normalized()
	var right := Vector2(-b.x.x, -b.x.z).normalized()   # the car's own right side
	var centre := c.size * 0.5 + Vector2(0, 30)
	var xf := func(p: Vector2) -> Vector2:
		var d := p - me
		return centre + Vector2(d.dot(right), -d.dot(fwd)) * SCALE
	_draw_route(c, xf, 5.0)
	_draw_marks(c, xf, 0.0, 1.0)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(1, 1, 1, 0.35), false, 2.0)
	c.draw_string(ThemeDB.fallback_font, Vector2(8, c.size.y - 8), "TAP: MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))


func _draw_full() -> void:
	var c := _full
	var vs := c.size
	c.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.05, 0.82))
	var lo := _pts[0]; var hi := _pts[0]
	for p in _pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y)); hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var pad := 70.0
	var sc := minf((vs.x - pad * 2.0) / maxf(hi.x - lo.x, 1.0), (vs.y - pad * 2.0) / maxf(hi.y - lo.y, 1.0))
	var off := (vs - (hi - lo) * sc) * 0.5
	# top-down: world +z up the screen, the car's right (-x) to the right
	var xf := func(p: Vector2) -> Vector2:
		return Vector2(vs.x - (off.x + (p.x - lo.x) * sc), off.y + (hi.y - p.y) * sc)
	_draw_route(c, xf, 6.0)
	var b := vehicle.global_transform.basis
	var f := Vector2(b.z.x, b.z.z)
	var rot := atan2(-f.x, f.y)   # arrow follows the car's heading on the north-up map
	_draw_marks(c, xf, rot, 1.6)
	var font := ThemeDB.fallback_font
	c.draw_string(font, Vector2(pad, 46), "MAP  ·  you (blue arrow)   rivals (red)   next checkpoint (yellow)   finish (flag)   shortcuts (orange)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))
	c.draw_string(font, Vector2(pad, vs.y - 30), "Tap anywhere to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
