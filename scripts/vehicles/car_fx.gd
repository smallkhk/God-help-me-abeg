class_name CarFX
extends Node3D
## Visual car effects: headlights (night), brake/tail lights, tyre smoke and
## skid marks when sliding, and a little camera shake at high speed.
## Added at runtime by player_driver.gd; reads the VehicleController only.

const MAX_SKIDS := 1500

var vehicle: VehicleController
## Rivals: tail/brake lights, nitro flames, tyre smoke and damage smoke only
## (no headlight spots, reflections, sparks or skid marks: phone budget).
var lite := false
var _bonnet: CPUParticles3D
var _heads: Array[SpotLight3D] = []
var _tail_mats: Array[BaseMaterial3D] = []
var _tail_glow: OmniLight3D
const _TAIL_WORDS := ["tail", "brake", "rear_l", "rearl", "rear l", "backl", "back_l", "back l", "redlight", "red_light", "stop"]
var _smoke: Array[CPUParticles3D] = []
const _SMOKE_TEX := preload("res://assets/textures/fx/smoke_white.png")   # the original puff is near-black: smoke came out black
var _skid_mm: MultiMesh
var _skid_i := 0
var _last_skid := {}
var _flames: Array[CPUParticles3D] = []
var _probe: ReflectionProbe
const _PROBE_STEP := 14.0     # re-capture the street after moving this far


func _ready() -> void:
	if vehicle == null:
		return
	var rear_z := INF; var front_z := -INF; var half_w := 0.8
	for w in vehicle.wheels:
		var p: Vector3 = w.marker.position
		rear_z = minf(rear_z, p.z); front_z = maxf(front_z, p.z); half_w = maxf(half_w, absf(p.x))
	# headlights
	for sx in ([] if lite else [-1.0, 1.0]):
		var l := SpotLight3D.new()
		l.position = Vector3(sx * (half_w - 0.25), 0.75, front_z + 0.9)
		l.rotation_degrees = Vector3(-4, 180, 0)  # car forward is +Z; spot shines along -Z
		l.spot_range = 45.0
		l.spot_angle = 28.0
		l.light_energy = 0.0
		l.light_color = Color(1.0, 0.95, 0.85)
		l.shadow_enabled = false
		vehicle.add_child(l)
		_heads.append(l)
	if not lite:
		add_contact_shadow(vehicle)
		_setup_reflections()
		_setup_sparks()
	# brake / tail lights: light up the model's own tail-light surfaces (the old
	# add-on red boxes floated above the boot)
	_find_tail_lights()
	if _tail_mats.is_empty():
		_tail_glow = OmniLight3D.new()
		_tail_glow.light_color = Color(1.0, 0.08, 0.05)
		_tail_glow.omni_range = 2.5
		_tail_glow.light_energy = 0.0
		_tail_glow.position = Vector3(0, 0.75, rear_z - 1.0)
		vehicle.add_child(_tail_glow)
	# nitro exhaust flames: soft round glow sprites (a bare quad drew as a white box)
	var glow := GradientTexture2D.new()
	glow.width = 64; glow.height = 64
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5); glow.fill_to = Vector2(0.5, 0.0)
	var gg := Gradient.new()
	gg.set_color(0, Color(1, 1, 1, 1)); gg.set_color(1, Color(1, 1, 1, 0))
	gg.add_point(0.35, Color(1, 1, 1, 0.55))
	glow.gradient = gg
	for sx in [-0.35, 0.35]:
		var f := CPUParticles3D.new()
		f.amount = 48
		f.lifetime = 0.22
		f.emitting = false
		f.local_coords = false
		f.direction = Vector3(0, 0, -1)
		f.spread = 8.0
		f.initial_velocity_min = 6.0; f.initial_velocity_max = 10.0
		f.gravity = Vector3.ZERO
		f.scale_amount_min = 0.35; f.scale_amount_max = 0.7
		var fcurve := Curve.new(); fcurve.add_point(Vector2(0, 1.0)); fcurve.add_point(Vector2(1, 0.25))
		f.scale_amount_curve = fcurve
		var fq := QuadMesh.new(); fq.size = Vector2(0.45, 0.45)
		var fm := StandardMaterial3D.new()
		fm.albedo_texture = glow
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		fm.vertex_color_use_as_albedo = true
		fq.material = fm
		f.mesh = fq
		var fg := Gradient.new()
		fg.set_color(0, Color(0.35, 0.55, 1.0, 0.9)); fg.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
		fg.add_point(0.35, Color(0.55, 0.75, 1.0, 0.7))
		f.color_ramp = fg
		f.position = Vector3(sx, 0.45, rear_z - 1.0)
		vehicle.add_child(f)
		_flames.append(f)
	var boost_light := OmniLight3D.new()
	boost_light.name = "NitroLight"
	boost_light.light_color = Color(0.5, 0.7, 1.0)
	boost_light.omni_range = 5.0
	boost_light.light_energy = 0.0
	boost_light.position = Vector3(0, 0.5, rear_z - 1.4)
	if not lite:
		vehicle.add_child(boost_light)

	# tyre smoke at the rear wheels
	for w in vehicle.wheels:
		if w.is_front:
			continue
		var s := CPUParticles3D.new()
		s.amount = 60
		s.angle_min = 0.0; s.angle_max = 360.0
		s.angular_velocity_min = -40.0; s.angular_velocity_max = 40.0
		s.lifetime = 1.6
		s.emitting = false
		s.local_coords = false
		s.direction = Vector3(0, 1, 0)
		s.spread = 35.0
		s.initial_velocity_min = 0.5; s.initial_velocity_max = 1.5
		s.gravity = Vector3(0, 0.6, 0)
		s.scale_amount_min = 1.0; s.scale_amount_max = 2.5
		var curve := Curve.new(); curve.add_point(Vector2(0, 0.4)); curve.add_point(Vector2(1, 1.6))
		s.scale_amount_curve = curve
		var q := QuadMesh.new(); q.size = Vector2(1.6, 1.6)
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = _SMOKE_TEX   # Kenney Particle Pack (CC0) puff
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.vertex_color_use_as_albedo = true
		q.material = sm
		s.mesh = q
		var g := Gradient.new()
		g.set_color(0, Color(0.72, 0.70, 0.68, 0.0)); g.set_color(1, Color(0.80, 0.79, 0.78, 0.0))
		g.add_point(0.12, Color(0.70, 0.68, 0.66, 0.5))
		g.add_point(0.5, Color(0.76, 0.75, 0.73, 0.3))
		s.color_ramp = g
		s.position = w.marker.position + Vector3(0, -0.2, 0)
		vehicle.add_child(s)
		_smoke.append(s)
	if lite:
		_setup_bonnet_smoke(front_z)
		return
	# skid marks: ring buffer of dark quads on the road
	_skid_mm = MultiMesh.new()
	_skid_mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm := PlaneMesh.new(); pm.size = Vector2(0.24, 1.0)
	var km := StandardMaterial3D.new()
	km.albedo_color = Color(0.02, 0.02, 0.02, 0.6)
	km.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	km.roughness = 0.6
	pm.material = km
	_skid_mm.mesh = pm
	_skid_mm.instance_count = MAX_SKIDS
	_skid_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _skid_mm
	mmi.top_level = true
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Damaged engine: grey smoke out of the bonnet (thicker past 60 % damage).
func _setup_bonnet_smoke(front_z: float) -> void:
	_bonnet = CPUParticles3D.new()
	_bonnet.amount = 10
	_bonnet.lifetime = 1.4
	_bonnet.emitting = false
	_bonnet.local_coords = false
	_bonnet.direction = Vector3.UP
	_bonnet.spread = 20.0
	_bonnet.initial_velocity_min = 1.0; _bonnet.initial_velocity_max = 2.2
	_bonnet.gravity = Vector3(0, 0.8, 0)
	_bonnet.scale_amount_min = 0.6; _bonnet.scale_amount_max = 1.4
	var curve := Curve.new(); curve.add_point(Vector2(0, 0.5)); curve.add_point(Vector2(1, 2.0))
	_bonnet.scale_amount_curve = curve
	var q := QuadMesh.new(); q.size = Vector2(1.0, 1.0)
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = _SMOKE_TEX
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	q.material = sm
	_bonnet.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(0.35, 0.35, 0.36, 0.0)); g.set_color(1, Color(0.6, 0.6, 0.62, 0.0))
	g.add_point(0.15, Color(0.38, 0.38, 0.4, 0.6))
	_bonnet.color_ramp = g
	_bonnet.position = Vector3(0, 1.0, front_z + 0.3)
	vehicle.add_child(_bonnet)


## Metal-on-metal sparks: one burst at the contact point per hit.
var _sparks: CPUParticles3D
func _setup_sparks() -> void:
	_sparks = CPUParticles3D.new()
	_sparks.top_level = true
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	_sparks.amount = 40
	_sparks.lifetime = 0.45
	_sparks.direction = Vector3.UP
	_sparks.spread = 75.0
	_sparks.initial_velocity_min = 4.0
	_sparks.initial_velocity_max = 11.0
	_sparks.gravity = Vector3(0, -14.0, 0)
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.22)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.75, 0.3)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.15)
	m.emission_energy_multiplier = 4.0
	m.vertex_color_use_as_albedo = true
	q.material = m
	_sparks.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	g.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	_sparks.color_ramp = g
	add_child(_sparks)
	vehicle.impact.connect(_on_impact)


func _on_impact(point: Vector3, strength: float) -> void:
	_sparks.global_position = point
	_sparks.amount = clampi(int(strength * 6.0), 12, 60)
	_sparks.restart()


func _process(_delta: float) -> void:
	if vehicle == null:
		return
	if _probe and _probe.global_position.distance_to(vehicle.global_position + Vector3.UP) > _PROBE_STEP:
		_probe.global_position = vehicle.global_position + Vector3.UP
		# nudge a property so the once-only probe captures the new spot
		_probe.max_distance = 140.0 if _probe.max_distance != 140.0 else 140.01
	var night: float = Game.night
	for l in _heads:
		l.light_energy = 4.0 * clampf(night * 1.4, 0.0, 1.0)
	var braking := vehicle.brake_input > 0.1 and vehicle.forward_speed > 0.5
	var tail := 3.5 if braking else (1.0 if night > 0.2 else 0.0)
	for m in _tail_mats:
		m.emission_energy_multiplier = tail
	if _tail_glow:
		_tail_glow.light_energy = 1.5 if braking else (0.5 if night > 0.2 else 0.0)

	var slide := absf(vehicle.lateral_speed) > 4.0 or (vehicle.handbrake_input and absf(vehicle.forward_speed) > 5.0)
	var grounded := vehicle.wheels_on_ground > 0
	for s in _smoke:
		s.emitting = slide and grounded
	for f in _flames:
		f.emitting = vehicle.nitro_active
	if _bonnet:
		_bonnet.emitting = vehicle.damage > 0.25
		_bonnet.amount = 10 if vehicle.damage < 0.6 else 24
	var nl := vehicle.get_node_or_null("NitroLight") as OmniLight3D
	if nl:
		nl.light_energy = 2.5 if vehicle.nitro_active else 0.0


func _physics_process(_delta: float) -> void:
	if vehicle == null or lite:
		return
	var slide := absf(vehicle.lateral_speed) > 3.5 or (vehicle.handbrake_input and absf(vehicle.forward_speed) > 4.0)
	for w in vehicle.wheels:
		if not (slide and w.grounded):
			_last_skid.erase(w)
			continue
		var p: Vector3 = w.contact_point + Vector3(0, 0.02, 0)
		if _last_skid.has(w):
			var a: Vector3 = _last_skid[w]
			var d := a.distance_to(p)
			if d < 0.4:
				continue
			if d < 3.0:
				var mid := (a + p) * 0.5
				var dir := (p - a).normalized()
				var b := Basis.looking_at(dir, Vector3.UP).scaled(Vector3(1, 1, d))
				_skid_mm.set_instance_transform(_skid_i, Transform3D(b, mid))
				_skid_i = (_skid_i + 1) % MAX_SKIDS
				_skid_mm.visible_instance_count = maxi(_skid_mm.visible_instance_count, _skid_i)
				if _skid_i == 0:
					_skid_mm.visible_instance_count = MAX_SKIDS
		_last_skid[w] = p



## Tail-light surfaces of the car model: named tail/brake/rear lights, or red
## light/lamp/lens materials. Never the body paint.
func _find_tail_lights() -> void:
	var model := vehicle.get_node_or_null("CarModel")
	if model == null:
		return
	var paint := VehicleController.paint_targets(model)
	var done := {}
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var mat := (mi as MeshInstance3D).get_active_material(si) as BaseMaterial3D
			var src := mesh.surface_get_material(si) as BaseMaterial3D
			if mat == null or src == null or paint.has(src):
				continue
			var nm := src.resource_name.to_lower()
			var c := src.albedo_color
			var named := _TAIL_WORDS.any(func(k): return nm.contains(k)) and not nm.contains("head")
			var red_lens := c.r > 0.45 and c.g < 0.3 and c.b < 0.3 and (nm.contains("light") or nm.contains("lamp") or nm.contains("lens") or nm.contains("glass"))
			if not (named or red_lens):
				continue
			var dup: BaseMaterial3D = done.get(src)
			if dup == null:
				dup = mat.duplicate() as BaseMaterial3D
				dup.emission_enabled = true
				dup.emission = Color(1.0, 0.06, 0.04)
				dup.emission_energy_multiplier = 0.0
				done[src] = dup
				_tail_mats.append(dup)
			(mi as MeshInstance3D).set_surface_override_material(si, dup)


## Soft dark blob projected under a car (a baked contact shadow): grounds it on
## the road where the sun shadow is thin or far away. Decals need the Mobile /
## Forward+ renderer; Compatibility just skips it.
static func add_contact_shadow(car: Node3D) -> void:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility" or car.has_node("ContactShadow"):
		return
	var tex := GradientTexture2D.new()
	tex.width = 64; tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5); tex.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.85)); g.set_color(1, Color(0, 0, 0, 0))
	g.add_point(0.55, Color(0, 0, 0, 0.6))
	tex.gradient = g
	var d := Decal.new()
	d.name = "ContactShadow"
	d.texture_albedo = tex
	d.size = Vector3(2.5, 1.6, 5.0)
	d.position = Vector3(0, -0.2, 0)
	d.upper_fade = 0.2
	d.lower_fade = 0.6
	d.cull_mask = 1     # the road / ground only, never the car body
	car.add_child(d)


## Street reflections in the paint and glass (Mobile renderer, High graphics):
## one box probe that follows the car and re-captures every _PROBE_STEP metres
## (the capture is spread over several frames). Car bodies are on render
## layer 2 (see VehicleController._mount_model) so it doesn't reflect itself.
func _setup_reflections() -> void:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility" or not Game.high_graphics:
		return
	_probe = ReflectionProbe.new()
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.size = Vector3(70, 30, 70)
	_probe.max_distance = 140.0
	_probe.intensity = 1.0
	_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	_probe.cull_mask = 1
	_probe.top_level = true
	add_child(_probe)
	_probe.global_position = vehicle.global_position + Vector3.UP
