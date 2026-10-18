class_name RaceFlair
extends Node
## Race excitement layer (child of the RaceManager): earn nitro by driving
## with style - DRIFT, NEAR MISS (passing traffic close at speed), OVERTAKE,
## AIRTIME - with pop-up rewards; an animated 3-2-1-GO countdown with beeps;
## a WRONG WAY warning; position change toasts. Counts the style events for
## the results screen.

var rm: Node            # the RaceManager
var stats := {"drift": 0, "near": 0, "overtake": 0, "air": 0, "best_drift": 0.0}

var _layer: CanvasLayer
var _pops: Array[Label] = []
var _wrong: Label
var _beep: AudioStreamPlayer
var _last_count := -1
var _drift_t := 0.0
var _drift_off := 0.0
var _air_t := 0.0
var _last_z := {}          # traffic instance id -> longitudinal offset last check
var _near_cd := {}         # traffic instance id -> cooldown
var _scan_t := 0.0
var _last_pos := 0
var _pend_pos := 0
var _pend_t := 0.0
const TAUNT_PASS := ["Comot for road!", "Oga shift!", "Na so you dey drive?", "Danfo driver pass you!", "Learner!", "See you for front o!", "Ehen! Who be oga now?"]
const TAUNT_LOST := ["Ehn! You try o", "I go catch you!", "Na fluke!", "Wetin be this?", "No vex, I dey come", "Chai! My engine!", "Abeg slow down!"]
var _sfx: AudioStreamPlayer
var _start_armed := true        # perfect-start window not used yet
var _early := false
var _slip_t := 0.0
var _slip_shown := false
const NITRO := {"drift_per_s": 0.07, "near": 0.12, "overtake": 0.10, "air": 0.10}


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 11
	add_child(_layer)
	_wrong = _label(64, Color(1.0, 0.2, 0.15))
	_wrong.text = "WRONG WAY"
	_wrong.anchor_left = 0.0; _wrong.anchor_right = 1.0
	_wrong.offset_top = 150; _wrong.offset_bottom = 230
	_wrong.visible = false
	_layer.add_child(_wrong)
	_beep = AudioStreamPlayer.new()
	_beep.stream = load("res://assets/audio/ui/click.ogg")
	_beep.volume_db = 2.0
	add_child(_beep)
	_sfx = AudioStreamPlayer.new()
	_sfx.stream = load("res://assets/audio/ui/slide.ogg")
	_sfx.volume_db = -2.0
	add_child(_sfx)


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Reward pop-up under the top buttons: rises and fades.
func popup(text: String, col: Color, nitro := 0.0) -> void:
	var p := rm.get("_player") as VehicleController
	if nitro > 0.0 and p:
		p.nitro_amount = minf(p.nitro_amount + nitro, 1.0)
	if OS.get_environment("FLAIR_LOG") == "1":
		print("[flair] ", text, " nitro+", nitro)
	if nitro > 0.0 and _sfx:
		_sfx.pitch_scale = randf_range(1.0, 1.3)
		_sfx.play()
	var l := _label(34, col)
	l.text = text + ("   +NITRO" if nitro > 0.0 else "")
	l.anchor_left = 0.0; l.anchor_right = 1.0
	l.offset_top = 120 + _pops.size() * 44
	l.offset_bottom = l.offset_top + 44
	l.pivot_offset = Vector2(640, 22)
	l.scale = Vector2(1.35, 1.35)
	_layer.add_child(l)
	_pops.append(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.18)
	tw.tween_interval(1.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.parallel().tween_property(l, "offset_top", l.offset_top - 30.0, 0.5)
	tw.tween_callback(func() -> void:
		_pops.erase(l)
		l.queue_free())


func _process(delta: float) -> void:
	if rm == null:
		return
	var st: int = rm.get("_state")
	_countdown_fx(st)
	var p := rm.get("_player") as VehicleController
	if p == null or st != 2:   # RUNNING
		_wrong.visible = false
		_last_pos = 0
		return
	_wrong_way(p)
	_drift(p, delta)
	_airtime(p, delta)
	_slipstream(p, delta)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.08
		_near_miss(p)
	_position_toast()


# --- 3-2-1-GO ---
func _countdown_fx(st: int) -> void:
	var cl := rm.get("_center_label") as Label
	if cl == null:
		return
	if st == 1:   # COUNTDOWN
		var c: float = rm.get("_countdown")
		var pl := rm.get("_player") as VehicleController
		if pl and pl.throttle_input > 0.5 and c > 0.45:
			_early = true          # gas held too early: no perfect start
		if pl and pl.throttle_input < 0.1 and c > 0.45:
			_early = false
		var n := ceili(c)
		var frac: float = c - floorf(c)
		cl.scale = Vector2.ONE * (1.0 + frac * 0.8)
		cl.modulate = Color(1, 0.85, 0.2, 0.4 + 0.6 * frac)
		if n != _last_count:
			_last_count = n
			_beep.pitch_scale = 0.8
			_beep.play()
	elif _last_count != -1:
		_last_count = -1
		if st == 2:
			_beep.pitch_scale = 1.6
			_beep.play()
			var pl2 := rm.get("_player") as VehicleController
			if pl2 and pl2.throttle_input > 0.5 and not _early:
				popup("PERFECT START!", Color(0.3, 1.0, 0.9), 0.35)
			_early = false
			cl.modulate = Color(0.3, 1.0, 0.4)
			cl.scale = Vector2(1.6, 1.6)
			var tw := cl.create_tween()
			tw.tween_property(cl, "scale", Vector2.ONE, 0.35)
	elif st == 2 and cl.text == "":
		cl.modulate = Color.WHITE
		cl.scale = Vector2.ONE


# --- WRONG WAY ---
func _wrong_way(p: VehicleController) -> void:
	var route: Array = rm.get("_route")
	var i: int = rm.get("_player_prog")
	if route.is_empty() or i < 0 or i >= route.size():
		return
	var h: float = route[i]["heading_rad"]
	var road := Vector3(sin(h), 0, cos(h))
	var wrong := p.linear_velocity.length() > 4.0 and p.linear_velocity.normalized().dot(road) < -0.4
	_wrong.visible = wrong and fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.55


# --- DRIFT: body slip > 12 deg at > 40 km/h ---
func _drift(p: VehicleController, delta: float) -> void:
	var v := p.linear_velocity
	var b := p.global_transform.basis
	var beta := absf(atan2(v.dot(b.x), v.dot(b.z)))
	if v.length() > 11.0 and beta > deg_to_rad(12.0) and p.wheels_on_ground >= 3:
		_drift_t += delta
		_drift_off = 0.0
		p.nitro_amount = minf(p.nitro_amount + NITRO["drift_per_s"] * delta, 1.0)
	elif _drift_t > 0.0:
		_drift_off += delta
		if _drift_off > 0.3:
			if _drift_t > 0.6:
				stats["drift"] += 1
				stats["best_drift"] = maxf(stats["best_drift"], _drift_t)
				popup("DRIFT  %.1f s" % _drift_t, Color(1.0, 0.55, 0.15), 0.04)
			_drift_t = 0.0


# --- SLIPSTREAM: tucked in 4-22 m behind a rival at > 80 km/h ---
func _slipstream(p: VehicleController, delta: float) -> void:
	var b := p.global_transform.basis
	var sp := p.linear_velocity.length()
	var tucked := false
	if sp > 22.0:
		for r in rm.get("_rivals"):
			if not is_instance_valid(r):
				continue
			var rel: Vector3 = r.global_position - p.global_position
			var z := rel.dot(b.z)
			if z > 4.0 and z < 22.0 and absf(rel.dot(b.x)) < 1.6:
				tucked = true
				break
	if tucked:
		_slip_t += delta
		# the car ahead takes the air: ~40 % less drag
		p.apply_central_force(p.linear_velocity.normalized() * p.data.drag_coefficient * 1.35 * sp * sp * 0.4)
		p.nitro_amount = minf(p.nitro_amount + 0.04 * delta, 1.0)
		if _slip_t > 0.8 and not _slip_shown:
			_slip_shown = true
			popup("SLIPSTREAM", Color(0.7, 0.8, 1.0))
	else:
		_slip_t = 0.0
		_slip_shown = false


## A rival shouts something Lagos-style from its car (speech bubble above it).
func taunt(rival: Node3D, lost: bool) -> void:
	if rival == null or not is_instance_valid(rival):
		return
	var lines: Array = TAUNT_LOST if lost else TAUNT_PASS
	var lb := Label3D.new()
	lb.text = "%s: %s" % [String(rival.name).trim_prefix("Rival_"), lines[randi() % lines.size()]]
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.font_size = 64
	lb.pixel_size = 0.012
	lb.outline_size = 14
	lb.modulate = Color(1.0, 0.92, 0.3)
	lb.position = Vector3(0, 2.9, 0)
	rival.add_child(lb)
	var tw := lb.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(lb, "modulate:a", 0.0, 0.5)
	tw.tween_callback(lb.queue_free)


func _nearest_rival(p: VehicleController, ahead: bool) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for r in rm.get("_rivals"):
		if not is_instance_valid(r):
			continue
		var rel: Vector3 = r.global_position - p.global_position
		var z := rel.dot(p.global_transform.basis.z)
		if (z > 0.0) != ahead:
			continue
		if rel.length() < bd:
			bd = rel.length(); best = r
	return best


# --- AIRTIME ---
func _airtime(p: VehicleController, delta: float) -> void:
	if p.wheels_on_ground == 0:
		_air_t += delta
	else:
		if _air_t > 0.35:
			stats["air"] += 1
			popup("AIRTIME  %.1f s" % _air_t, Color(0.5, 0.85, 1.0), NITRO["air"])
		_air_t = 0.0


# --- NEAR MISS: traffic passed within ~2.5 m at > 60 km/h without touching ---
func _near_miss(p: VehicleController) -> void:
	var sp := p.linear_velocity.length()
	var b := p.global_transform.basis
	var touching := {}
	if p.contact_monitor:
		for c in p.get_colliding_bodies():
			touching[c.get_instance_id()] = true
	for t in get_tree().get_nodes_in_group(&"traffic"):
		var n := t as Node3D
		if n == null:
			continue
		var id := n.get_instance_id()
		var rel := n.global_position - p.global_position
		if rel.length() > 14.0:
			_last_z.erase(id)
			continue
		var z := rel.dot(b.z)
		var x := absf(rel.dot(b.x))
		var cd: float = _near_cd.get(id, 0.0)
		if _last_z.has(id) and float(_last_z[id]) > 0.0 and z <= 0.0 and x < 2.6 and sp > 16.7 \
				and not touching.has(id) and Time.get_ticks_msec() / 1000.0 > cd:
			stats["near"] += 1
			_near_cd[id] = Time.get_ticks_msec() / 1000.0 + 3.0
			popup("NEAR MISS!", Color(1.0, 0.95, 0.3), NITRO["near"])
		_last_z[id] = z


# --- position changes ---
func _position_toast() -> void:
	var pos: int = rm.get("player_position")
	if pos <= 0:
		return
	# a new position must hold for a second (side by side it flips back and
	# forth, which spammed OVERTAKE and free nitro)
	if pos != _pend_pos:
		_pend_pos = pos
		_pend_t = 0.0
		return
	_pend_t += get_process_delta_time()
	if _pend_t < 1.0:
		return
	if _last_pos > 0 and pos != _last_pos:
		var pl := rm.get("_player") as VehicleController
		if pos < _last_pos:
			stats["overtake"] += 1
			popup("OVERTAKE!  %s" % _ord(pos), Color(0.4, 1.0, 0.45), NITRO["overtake"])
			if pl and randf() < 0.7:
				taunt(_nearest_rival(pl, false), true)   # the one you just passed
		else:
			popup("▼  %s" % _ord(pos), Color(1.0, 0.35, 0.3))
			if pl and randf() < 0.8:
				taunt(_nearest_rival(pl, true), false)   # the one who passed you
	_last_pos = pos


static func _ord(n: int) -> String:
	var s := "th"
	if n % 100 < 11 or n % 100 > 13:
		s = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, s]
