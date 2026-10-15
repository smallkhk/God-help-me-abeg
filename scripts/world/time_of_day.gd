extends Node
## Day / Sunset / Night presets (spec §4.2, §14). Press N to cycle.
## Drives the sun, sky, ambient light, fog and the global `night_factor` shader
## parameter (building windows light up, the lagoon darkens). Finds the sibling
## WorldEnvironment and DirectionalLight3D named "Sun".

enum Preset { DAY, SUNSET, NIGHT }
@export var start_preset: Preset = Preset.DAY

var _preset: int
var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _we: WorldEnvironment

const PRESETS := {
	Preset.DAY: {
		"sun_rot": Vector3(-42, 35, 0), "sun_col": Color(1.0, 0.93, 0.80), "sun_e": 1.6,
		"top": Color(0.12, 0.38, 0.88), "hor": Color(0.62, 0.80, 0.97),
		"amb": Color(0.86, 0.84, 0.80), "amb_e": 0.42, "fog": Color(0.68, 0.80, 0.97), "night": 0.0,
		"fog_d": 0.0007, "hdri": "day", "sky_e": 0.72,
	},
	Preset.SUNSET: {
		"sun_rot": Vector3(-12, -60, 0), "sun_col": Color(1.0, 0.70, 0.45), "sun_e": 1.2,
		"top": Color(0.20, 0.30, 0.52), "hor": Color(0.98, 0.58, 0.32),
		"amb": Color(0.75, 0.62, 0.60), "amb_e": 0.45, "fog": Color(0.92, 0.66, 0.48), "night": 0.25,
		"fog_d": 0.0019, "hdri": "sunset", "sky_e": 0.9,
	},
	Preset.NIGHT: {
		"sun_rot": Vector3(-40, 120, 0), "sun_col": Color(0.55, 0.62, 0.85), "sun_e": 0.12,
		"top": Color(0.01, 0.02, 0.06), "hor": Color(0.07, 0.07, 0.14),
		"amb": Color(0.25, 0.28, 0.40), "amb_e": 0.35, "fog": Color(0.05, 0.06, 0.10), "night": 1.0,
		"fog_d": 0.0022, "hdri": "night", "sky_e": 0.6,
	},
}


func _ready() -> void:
	var p := get_parent()
	var we := p.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_we = we
	_sun = p.get_node_or_null("Sun") as DirectionalLight3D
	if we and we.environment:
		_env = we.environment
		if _env.sky and _env.sky.sky_material is ProceduralSkyMaterial:
			_sky = _env.sky.sky_material
	# menu setting "Race time" overrides the map's default (EVENT keeps it)
	var st := String(Game.get_setting("start_time", "event"))
	var preset: int = {"day": Preset.DAY, "sunset": Preset.SUNSET, "night": Preset.NIGHT}.get(st, start_preset)
	apply.call_deferred(preset)


func _unhandled_input(ev: InputEvent) -> void:
	if InputMap.has_action("time_next") and ev.is_action_pressed("time_next") and not ev.is_echo():
		apply((_preset + 1) % 3)
	# F6: toggle High / Low graphics (photo sky, glow, shadows)
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_F6:
		Game.high_graphics = not Game.high_graphics
		Game.set_setting("high_graphics", Game.high_graphics)
		apply(_preset)


func apply(preset: int) -> void:
	_preset = preset
	var c: Dictionary = PRESETS[preset]
	if _sun:
		var r: Vector3 = c["sun_rot"]
		_sun.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))
		_sun.light_color = c["sun_col"]
		_sun.light_energy = c["sun_e"]
		_sun.shadow_opacity = 1.0 - 0.8 * float(c["night"])
	var high: bool = Game.high_graphics
	# smooth edges: 4x MSAA on High, 2x on Low, plus FXAA to soften
	# shimmering texture/specular edges MSAA can't touch
	var vp := get_viewport()
	# 2x MSAA on High (4x was the biggest GPU cost at native phone resolution),
	# FXAA only on Low. Phones render 3D at 85 % of native res (UI stays sharp).
	var mobile := OS.has_feature("mobile")
	# Mobile renderer (Metal on iOS): tile GPUs resolve MSAA almost for free, and
	# MetalFX / FSR upscale the 80 % render far sharper than bilinear
	var mob_r := RenderingServer.get_current_rendering_method() == "mobile"
	vp.msaa_3d = Viewport.MSAA_2X if (high and not mobile) or mob_r else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if mob_r else Viewport.SCREEN_SPACE_AA_FXAA
	if mobile and mob_r:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_SPATIAL if OS.get_name() == "iOS" else Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = 0.8
	elif mobile:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 0.75
	if _env and _env.sky:
		var hdri := "res://assets/sky/%s.hdr" % c["hdri"]
		# the photo sky (blue sky + clouds) on every device: one 8 MB texture
		if ResourceLoader.exists(hdri):
			var pano := PanoramaSkyMaterial.new()
			pano.panorama = load(hdri)
			pano.energy_multiplier = c["sky_e"]
			_env.sky.sky_material = pano
		elif _sky:
			_env.sky.sky_material = _sky
	if _sun:
		_sun.shadow_enabled = true
		_sun.directional_shadow_max_distance = (80.0 if mobile else 250.0) if high else (50.0 if mobile else 120.0)
		# phones: one shadow pass instead of four cascades (two on the Mobile renderer)
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if mobile else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		if mobile and mob_r and high:
			_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			_sun.directional_shadow_max_distance = 130.0
		_sun.shadow_blur = 1.5
	if _sky:
		_sky.sky_top_color = c["top"]
		_sky.sky_horizon_color = c["hor"]
		_sky.ground_horizon_color = c["hor"]
	if _env:
		_env.ambient_light_color = c["amb"]
		_env.ambient_light_energy = c["amb_e"]
		_env.fog_light_color = c["fog"]
		_env.fog_density = c["fog_d"]
		# car paint, glass and wet road reflect the sky (all renderers, also
		# Compatibility on phones); ambient is part sky, part the preset colour
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		_env.ambient_light_sky_contribution = 0.45
		_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		if _env.sky:
			# static sky: the reflection map is filtered once, small on phones
			_env.sky.radiance_size = Sky.RADIANCE_SIZE_128 if mobile else Sky.RADIANCE_SIZE_256
			_env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
		# ACES keeps white paint and bright walls from burning out
		_env.tonemap_mode = Environment.TONE_MAPPER_ACES
		_env.tonemap_exposure = 0.92 if preset == Preset.DAY else 1.0
		_env.tonemap_white = 6.0
		_env.adjustment_enabled = true
		# racing-game grade: rich but not neon colour, a little extra punch
		_env.adjustment_saturation = 1.28 if preset == Preset.DAY else 1.1
		_env.adjustment_contrast = 1.12 if preset == Preset.DAY else 1.08
		# bloom: lit windows, streetlights and car lights glow (High only)
		_env.glow_enabled = high and (not mobile or mob_r)
		_env.glow_intensity = 0.6 if preset == Preset.NIGHT else 0.35
		_env.glow_bloom = 0.06
		_env.glow_hdr_threshold = 0.95
		_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT if preset == Preset.DAY else Environment.GLOW_BLEND_MODE_ADDITIVE
		# Forward+ only extras (ignored by the Compatibility renderer):
		# ambient occlusion, screen-space reflections on the lagoon/road, soft GI
		var fplus := RenderingServer.get_current_rendering_method() == "forward_plus"
		_env.ssao_enabled = high and fplus
		_env.ssao_intensity = 1.6
		_env.ssr_enabled = high and fplus
		_env.ssr_max_steps = 48
		_env.ssil_enabled = high and fplus
		_env.volumetric_fog_enabled = high and fplus and preset != Preset.DAY
		_env.volumetric_fog_density = 0.004
		if fplus and high:
			_env.ambient_light_sky_contribution = 0.6
	RenderingServer.global_shader_parameter_set("night_factor", c["night"])
	Game.night = c["night"]
