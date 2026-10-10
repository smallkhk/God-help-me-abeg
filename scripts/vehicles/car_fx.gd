class_name CarFX
extends Node3D
## Visual car effects: headlights (night), brake/tail lights, tyre smoke and
## skid marks when sliding, and a little camera shake at high speed.
## Added at runtime by player_driver.gd; reads the VehicleController only.

const MAX_SKIDS := 1500

var vehicle: VehicleController
var _heads: Array[SpotLight3D] = []
var _tail_mat: StandardMaterial3D
var _smoke: Array[CPUParticles3D] = []
const _SMOKE_TEX := preload("res://assets/textures/fx/smoke.png")
var _skid_mm: MultiMesh
var _skid_i := 0
var _last_skid := {}
var _flames: Array[CPUParticles3D] = []


func _ready() -> void:
	if vehicle == null:
		return
	var rear_z := INF; var front_z := -INF; var half_w := 0.8
	for w in vehicle.wheels:
		var p: Vector3 = w.marker.position
		rear_z = minf(rear_z, p.z); front_z = maxf(front_z, p.z); half_w = maxf(half_w, absf(p.x))
	# headlights
	for sx in [-1.0, 1.0]:
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
	# tail / brake light strip
	_tail_mat = StandardMaterial3D.new()
	_tail_mat.albedo_color = Color(0.4, 0.02, 0.02)
	_tail_mat.emission_enabled = true
	_tail_mat.emission = Color(1.0, 0.05, 0.03)
	for sx in [-1.0, 1.0]:
		var t := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(0.45, 0.12, 0.05)
		t.mesh = bm
		t.material_override = _tail_mat
		t.position = Vector3(sx * (half_w - 0.3), 0.75, rear_z - 0.95)
		vehicle.add_child(t)
	# nitro exhaust flames
	for sx in [-0.35, 0.35]:
		var f := CPUParticles3D.new()
		f.amount = 60
		f.lifetime = 0.25
		f.emitting = false
		f.local_coords = false
		f.direction = Vector3(0, 0, -1)
		f.spread = 8.0
		f.initial_velocity_min = 6.0; f.initial_velocity_max = 10.0
		f.gravity = Vector3.ZERO
		f.scale_amount_min = 0.25; f.scale_amount_max = 0.5
		var fq := QuadMesh.new(); fq.size = Vector2(0.5, 0.5)
		var fm := StandardMaterial3D.new()
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		fm.vertex_color_use_as_albedo = true
		fq.material = fm
		f.mesh = fq
		var fg := Gradient.new()
		fg.set_color(0, Color(0.6, 0.8, 1.0, 1.0)); fg.set_color(1, Color(1.0, 0.4, 0.1, 0.0))
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


func _process(_delta: float) -> void:
	if vehicle == null:
		return
	var night: float = Game.night
	for l in _heads:
		l.light_energy = 4.0 * clampf(night * 1.4, 0.0, 1.0)
	var braking := vehicle.brake_input > 0.1 and vehicle.forward_speed > 0.5
	_tail_mat.emission_energy_multiplier = 4.0 if braking else (1.2 if night > 0.2 else 0.3)

	var slide := absf(vehicle.lateral_speed) > 4.0 or (vehicle.handbrake_input and absf(vehicle.forward_speed) > 5.0)
	var grounded := vehicle.wheels_on_ground > 0
	for s in _smoke:
		s.emitting = slide and grounded
	for f in _flames:
		f.emitting = vehicle.nitro_active
	var nl := vehicle.get_node_or_null("NitroLight") as OmniLight3D
	if nl:
		nl.light_energy = 2.5 if vehicle.nitro_active else 0.0


func _physics_process(_delta: float) -> void:
	if vehicle == null:
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
