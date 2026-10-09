class_name CarAudio
extends Node3D
## Procedural engine + tyre-screech sound (no audio files needed).
## Engine pitch follows transmission rpm; screech follows sideways slip.

const RATE := 22050.0

var vehicle: VehicleController
var _player: AudioStreamPlayer3D
var _pb: AudioStreamGeneratorPlayback
var _phase := 0.0
var _freq := 30.0
var _vol := 0.2
var _screech := 0.0
var _noise := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	_player = AudioStreamPlayer3D.new()
	_player.stream = gen
	_player.unit_size = 12.0
	_player.volume_db = -4.0
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback()


func _process(_delta: float) -> void:
	if vehicle == null or _pb == null:
		return
	var rpm: float = vehicle.transmission.engine_rpm
	# 4-cylinder firing frequency = rpm/60 * 2
	_freq = lerpf(_freq, rpm / 30.0, 0.3)
	_vol = lerpf(_vol, 0.18 + 0.32 * vehicle.throttle_input, 0.1)
	var slip := absf(vehicle.lateral_speed)
	var target := clampf((slip - 3.0) / 6.0, 0.0, 1.0) if vehicle.wheels_on_ground > 0 else 0.0
	if vehicle.handbrake_input and absf(vehicle.forward_speed) > 5.0 and vehicle.wheels_on_ground > 0:
		target = maxf(target, 0.7)
	_screech = lerpf(_screech, target, 0.15)
	_fill()


func _fill() -> void:
	var n := _pb.get_frames_available()
	var step := _freq / RATE
	for i in n:
		_phase = fmod(_phase + step, 1.0)
		# rough engine: saw + its half-frequency rumble
		var saw := _phase * 2.0 - 1.0
		var rumble := sin(_phase * PI) * 0.6
		var e := (saw * 0.5 + rumble) * _vol
		var s := 0.0
		if _screech > 0.01:
			_noise = lerpf(_noise, randf() * 2.0 - 1.0, 0.35)
			s = (_noise + sin(_phase * 40.0) * 0.3) * _screech * 0.35
		var v := clampf(e + s, -1.0, 1.0)
		_pb.push_frame(Vector2(v, v))
