class_name CarAudio
extends Node3D
## Car sound: real recorded engine loops (CC0, OpenGameArt "Racing car engine
## sound loops") cross-faded by RPM and pitch-shifted, like racing games do.
## Tyre screech stays procedural. H = horn. Plays a start-up sound once.

const LOOP_RPM := [1000.0, 2500.0, 3800.0, 5000.0, 6200.0, 7400.0]
const RATE := 22050.0

var vehicle: VehicleController
var is_player := true
var _layers: Array[AudioStreamPlayer3D] = []
var _horn: AudioStreamPlayer3D
var _scr: AudioStreamPlayer3D
var _wind: AudioStreamPlayer3D
var _crash: AudioStreamPlayer3D
var _nitro: AudioStreamPlayer3D
var _screech := 0.0
var _last_speed := 0.0
var _was_nitro := false
var _crash_cd := 0.0


func _ready() -> void:
	for i in LOOP_RPM.size():
		var path := "res://assets/audio/engine/engine_%d.wav" % i
		if not ResourceLoader.exists(path):
			continue
		var st := load(path) as AudioStreamWAV
		if st:
			st = st.duplicate()
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = st.data.size() / (2 if st.format == AudioStreamWAV.FORMAT_16_BITS else 1) / (2 if st.stereo else 1)
		var p := AudioStreamPlayer3D.new()
		p.stream = st
		p.unit_size = 14.0 if is_player else 9.0
		p.max_db = 3.0
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_layers.append(p)
	# horn + start-up
	if is_player:
		_horn = AudioStreamPlayer3D.new()
		_horn.stream = load("res://assets/audio/horn.ogg")
		add_child(_horn)
		var start := AudioStreamPlayer3D.new()
		start.stream = load("res://assets/audio/engine_start.ogg")
		start.volume_db = -6.0
		add_child(start)
		start.play()
	# tyre screech, wind, crash, nitro (recorded/generated samples)
	_scr = _loop_player("res://assets/audio/sfx/screech.ogg", 12.0)
	if is_player:
		_wind = _loop_player("res://assets/audio/sfx/wind.ogg", 30.0)
		_crash = AudioStreamPlayer3D.new()
		_crash.stream = load("res://assets/audio/sfx/crash.ogg")
		_crash.unit_size = 20.0
		add_child(_crash)
		_nitro = AudioStreamPlayer3D.new()
		_nitro.stream = load("res://assets/audio/sfx/nitro.ogg")
		_nitro.unit_size = 20.0
		add_child(_nitro)


func _loop_player(path: String, unit: float) -> AudioStreamPlayer3D:
	var st: AudioStream = load(path)
	if st is AudioStreamOggVorbis:
		st = st.duplicate()
		st.loop = true
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.unit_size = unit
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p


func _unhandled_input(ev: InputEvent) -> void:
	if is_player and _horn and InputMap.has_action("horn") and ev.is_action_pressed("horn") and not ev.is_echo():
		_horn.play()


func _process(_delta: float) -> void:
	if vehicle == null:
		return
	var rpm: float = vehicle.transmission.engine_rpm
	var load := 0.55 + 0.45 * vehicle.throttle_input
	# find the two loops around this rpm and cross-fade them
	var n := _layers.size()
	for i in n:
		var ref: float = LOOP_RPM[i]
		var w := 0.0
		if i == 0 and rpm <= ref:
			w = 1.0
		elif i == n - 1 and rpm >= ref:
			w = 1.0
		else:
			var lo: float = LOOP_RPM[i - 1] if i > 0 else ref
			var hi: float = LOOP_RPM[i + 1] if i < n - 1 else ref
			if rpm >= lo and rpm <= ref and ref > lo:
				w = (rpm - lo) / (ref - lo)
			elif rpm > ref and rpm <= hi and hi > ref:
				w = 1.0 - (rpm - ref) / (hi - ref)
		var p := _layers[i]
		if w > 0.01:
			p.volume_db = linear_to_db(w * load) + (0.0 if is_player else -4.0)
			p.pitch_scale = clampf(rpm / ref, 0.5, 2.0)
		else:
			p.volume_db = -80.0
	# screech
	var slip := absf(vehicle.lateral_speed)
	var target := clampf((slip - 3.0) / 6.0, 0.0, 1.0) if vehicle.wheels_on_ground > 0 else 0.0
	if vehicle.handbrake_input and absf(vehicle.forward_speed) > 5.0 and vehicle.wheels_on_ground > 0:
		target = maxf(target, 0.7)
	_screech = lerpf(_screech, target, 0.15)
	_scr.volume_db = linear_to_db(maxf(_screech, 0.0001)) - 2.0
	_scr.pitch_scale = 0.9 + _screech * 0.2
	var spd := vehicle.linear_velocity.length()
	if _wind:
		var wv := clampf((spd - 12.0) / 40.0, 0.0, 1.0)
		_wind.volume_db = linear_to_db(maxf(wv * 0.8, 0.0001))
		_wind.pitch_scale = 0.8 + wv * 0.5
	# crash: a sudden loss of speed means we hit something
	_crash_cd -= _delta
	if _crash and _crash_cd <= 0.0 and _last_speed - spd > 5.0 and _last_speed > 8.0:
		_crash.volume_db = linear_to_db(clampf((_last_speed - spd) / 15.0, 0.3, 1.0)) + 2.0
		_crash.play()
		_crash_cd = 0.8
	_last_speed = spd
	if _nitro and vehicle.nitro_active and not _was_nitro:
		_nitro.play()
	_was_nitro = vehicle.nitro_active
