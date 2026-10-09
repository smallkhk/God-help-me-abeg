extends CanvasLayer
## First-prototype HUD (spec §15): speed in km/h, gear / automatic mode, RPM,
## pause/restart hints, optional route timer, and a toggleable debug overlay
## (spec §7). The HUD only reads vehicle state; it never mutates physics.

@export var vehicle_path: NodePath

var _vehicle: VehicleController
var _debug_visible: bool = false

@onready var _speed_label: Label = %SpeedLabel
@onready var _gear_label: Label = %GearLabel
@onready var _rpm_bar: ProgressBar = %RpmBar
@onready var _mode_label: Label = %ModeLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _debug_panel: Panel = %DebugPanel
@onready var _debug_label: Label = %DebugLabel

var _race_time: float = 0.0
var _race_running: bool = false


func _ready() -> void:
	_vehicle = get_node_or_null(vehicle_path) as VehicleController
	_debug_panel.visible = _debug_visible
	_timer_label.visible = false


func set_vehicle(v: VehicleController) -> void:
	_vehicle = v


func start_timer() -> void:
	_race_time = 0.0
	_race_running = true
	_timer_label.visible = true


func stop_timer() -> float:
	_race_running = false
	return _race_time


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		_debug_visible = not _debug_visible
		_debug_panel.visible = _debug_visible


func _process(delta: float) -> void:
	if _race_running:
		_race_time += delta
		_timer_label.text = _format_time(_race_time)

	if _vehicle == null:
		return

	var speed_kmh := _vehicle.linear_velocity.length() * 3.6
	_speed_label.text = "%d km/h" % roundi(speed_kmh)
	_gear_label.text = _vehicle.transmission.gear_label()
	_mode_label.text = "AUTO" if _vehicle.transmission.automatic else "MANUAL"

	var rpm := _vehicle.transmission.engine_rpm
	_rpm_bar.max_value = _vehicle.data.max_rpm
	_rpm_bar.value = rpm

	if _debug_visible:
		_update_debug(speed_kmh, rpm)


func _update_debug(speed_kmh: float, rpm: float) -> void:
	var v := _vehicle
	var frame_ms := 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)
	var phys_ms := 1000.0 / float(Engine.physics_ticks_per_second)
	var avg_slip := 0.0
	for w in v.wheels:
		avg_slip += absf(w.slip_angle)
	if v.wheels.size() > 0:
		avg_slip /= v.wheels.size()

	_debug_label.text = "\n".join([
		"SPEED      %6.1f km/h  (%5.1f m/s)" % [speed_kmh, v.linear_velocity.length()],
		"FORWARD    %6.1f m/s" % v.forward_speed,
		"LATERAL    %6.1f m/s" % v.lateral_speed,
		"STEER      %6.1f deg" % rad_to_deg(v.current_steer_angle),
		"SLIP(avg)  %6.1f deg" % rad_to_deg(avg_slip),
		"GEAR       %s   RPM %5d" % [v.transmission.gear_label(), roundi(rpm)],
		"THROTTLE   %4.2f   BRAKE %4.2f" % [v.throttle_input, v.brake_input],
		"WHEELS DN  %d / %d" % [v.wheels_on_ground, v.wheels.size()],
		"WETNESS    %4.2f" % v.wetness,
		"FRAME      %5.2f ms   PHYS %5.2f ms" % [frame_ms, phys_ms],
		"FPS        %5d" % roundi(Engine.get_frames_per_second()),
	])


static func _format_time(t: float) -> String:
	var minutes := int(t) / 60
	var seconds := int(t) % 60
	var millis := int((t - int(t)) * 1000.0)
	return "%02d:%02d.%03d" % [minutes, seconds, millis]
