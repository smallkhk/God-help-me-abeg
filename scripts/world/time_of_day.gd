extends Node
## Day / Sunset / Night presets (spec §4.2, §14). Press N to cycle.
## Drives the sun, sky, ambient light, fog and the global `night_factor` shader
## parameter (building windows light up, the lagoon darkens). Finds the sibling
## WorldEnvironment and DirectionalLight3D named "Sun".

enum Preset { DAY, SUNSET, NIGHT }
@export var start_preset: Preset = Preset.SUNSET

var _preset: int
var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D

const PRESETS := {
	Preset.DAY: {
		"sun_rot": Vector3(-55, 30, 0), "sun_col": Color(1.0, 0.97, 0.9), "sun_e": 1.3,
		"top": Color(0.28, 0.50, 0.80), "hor": Color(0.70, 0.80, 0.90),
		"amb": Color(0.75, 0.78, 0.85), "amb_e": 0.6, "fog": Color(0.75, 0.82, 0.9), "night": 0.0,
	},
	Preset.SUNSET: {
		"sun_rot": Vector3(-12, -60, 0), "sun_col": Color(1.0, 0.70, 0.45), "sun_e": 1.2,
		"top": Color(0.20, 0.30, 0.52), "hor": Color(0.98, 0.58, 0.32),
		"amb": Color(0.75, 0.62, 0.60), "amb_e": 0.45, "fog": Color(0.92, 0.66, 0.48), "night": 0.25,
	},
	Preset.NIGHT: {
		"sun_rot": Vector3(-40, 120, 0), "sun_col": Color(0.55, 0.62, 0.85), "sun_e": 0.12,
		"top": Color(0.01, 0.02, 0.06), "hor": Color(0.07, 0.07, 0.14),
		"amb": Color(0.25, 0.28, 0.40), "amb_e": 0.35, "fog": Color(0.05, 0.06, 0.10), "night": 1.0,
	},
}


func _ready() -> void:
	var p := get_parent()
	var we := p.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_sun = p.get_node_or_null("Sun") as DirectionalLight3D
	if we and we.environment:
		_env = we.environment
		if _env.sky and _env.sky.sky_material is ProceduralSkyMaterial:
			_sky = _env.sky.sky_material
	apply(start_preset)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_N:
		apply((_preset + 1) % 3)


func apply(preset: int) -> void:
	_preset = preset
	var c: Dictionary = PRESETS[preset]
	if _sun:
		var r: Vector3 = c["sun_rot"]
		_sun.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))
		_sun.light_color = c["sun_col"]
		_sun.light_energy = c["sun_e"]
		_sun.shadow_opacity = 1.0 - 0.8 * float(c["night"])
	if _sky:
		_sky.sky_top_color = c["top"]
		_sky.sky_horizon_color = c["hor"]
		_sky.ground_horizon_color = c["hor"]
	if _env:
		_env.ambient_light_color = c["amb"]
		_env.ambient_light_energy = c["amb_e"]
		_env.fog_light_color = c["fog"]
	RenderingServer.global_shader_parameter_set("night_factor", c["night"])
