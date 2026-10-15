class_name Speedometer
extends Control
## Analogue speedometer (bottom centre of the race HUD): needle on a 240°
## dial scaled to the car's top speed, big digital speed, gear, an RPM ring
## that turns red near the limiter, and the nitro tank as a blue outer arc.

var vehicle: VehicleController
var _max_kmh := 240.0
var _needle := 0.0          # smoothed km/h shown by the needle
const R := 70.0
const A0 := deg_to_rad(150.0)     # dial start (bottom left)
const SWEEP := deg_to_rad(240.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(R * 2.0 + 24.0, R * 2.0 + 10.0)
	anchor_left = 0.5; anchor_right = 0.5; anchor_top = 1.0; anchor_bottom = 1.0
	offset_left = -R - 12.0; offset_right = R + 12.0
	offset_top = -R * 2.0 - 14.0; offset_bottom = -4.0


func set_vehicle(v: VehicleController) -> void:
	vehicle = v
	if v and v.data:
		# dial end ~15 % above the car's estimated top speed, rounded to 20
		# top gear pulls only (top ratio / first ratio) of the launch force
		var gr: PackedFloat32Array = v.data.gear_ratios
		var g_top := gr[gr.size() - 1] / maxf(gr[0], 0.01) if gr.size() > 0 else 0.3
		var top := sqrt(v.data.max_drive_force * 0.75 * 0.8 * g_top / maxf(v.data.drag_coefficient * 1.35, 0.05)) * 3.6
		_max_kmh = clampf(ceilf(top * 1.15 / 20.0) * 20.0, 100.0, 360.0)


func _process(delta: float) -> void:
	if vehicle == null:
		return
	_needle = lerpf(_needle, vehicle.linear_velocity.length() * 3.6, clampf(delta * 12.0, 0.0, 1.0))
	queue_redraw()


func _ang(kmh: float) -> float:
	return A0 + SWEEP * clampf(kmh / _max_kmh, 0.0, 1.0)


func _draw() -> void:
	if vehicle == null:
		return
	var c := Vector2(size.x * 0.5, R + 6.0)
	var font := ThemeDB.fallback_font
	# face
	draw_circle(c, R, Color(0.03, 0.04, 0.06, 0.72))
	draw_arc(c, R, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 2.0, true)
	# nitro (outer, blue)
	var n := vehicle.nitro_amount
	draw_arc(c, R + 5.0, A0, A0 + SWEEP, 48, Color(1, 1, 1, 0.12), 4.0, true)
	if n > 0.01:
		draw_arc(c, R + 5.0, A0, A0 + SWEEP * n, 48, Color(0.3, 0.75, 1.0, 0.95 if vehicle.nitro_active else 0.75), 4.0, true)
	# RPM ring (inner): white, red near the limiter
	var tr := vehicle.transmission
	var rf := clampf((tr.engine_rpm - vehicle.data.idle_rpm) / maxf(vehicle.data.max_rpm - vehicle.data.idle_rpm, 1.0), 0.0, 1.0)
	draw_arc(c, R - 14.0, A0, A0 + SWEEP, 48, Color(1, 1, 1, 0.08), 5.0, true)
	draw_arc(c, R - 14.0, A0, A0 + SWEEP * rf, 48, Color(1.0, 0.25, 0.2) if rf > 0.85 else Color(1, 1, 1, 0.55), 5.0, true)
	# ticks + numbers
	var step := 20.0
	var k := 0.0
	while k <= _max_kmh + 0.1:
		var a := _ang(k)
		var dir := Vector2(cos(a), sin(a))
		var major := int(k) % (40 if _max_kmh > 140.0 else 20) == 0
		draw_line(c + dir * (R - (12.0 if major else 7.0)), c + dir * (R - 2.0), Color(1, 1, 1, 0.9 if major else 0.5), 2.0 if major else 1.0, true)
		if major:
			var s := str(int(k))
			var tp := c + dir * (R - 28.0) - Vector2(font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x * 0.5, -5.0)
			draw_string(font, tp, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))
		k += step
	# needle
	var na := _ang(_needle)
	var nd := Vector2(cos(na), sin(na))
	draw_line(c - nd * 10.0, c + nd * (R - 8.0), Color(1.0, 0.18, 0.12), 3.0, true)
	draw_circle(c, 7.0, Color(0.15, 0.15, 0.17))
	draw_circle(c, 4.0, Color(1.0, 0.18, 0.12))
	# digital speed + unit + gear
	var sp := str(roundi(vehicle.linear_velocity.length() * 3.6))
	var fs := 28
	draw_string(font, c + Vector2(-font.get_string_size(sp, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, 36.0), sp, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	draw_string(font, c + Vector2(-13.0, 50.0), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
	var g := tr.gear_label()
	draw_rect(Rect2(c + Vector2(-12.0, 53.0), Vector2(24.0, 20.0)), Color(1, 1, 1, 0.12))
	draw_string(font, c + Vector2(-font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x * 0.5, 69.0), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1.0, 0.85, 0.3))
