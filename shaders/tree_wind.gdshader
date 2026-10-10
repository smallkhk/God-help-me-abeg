shader_type spatial;
render_mode cull_disabled;
// Wind for instanced trees: whole-tree sway that grows with height (trunk base
// fixed), fast leaf flutter on the canopy, and gusts that roll across the map
// so neighbouring trees move together but out of step. Cheap: vertex only.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform bool has_orm = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float tree_height = 10.0;     // local-space height of the model
uniform float sway = 0.35;            // metres of sway at the top
uniform float flutter = 0.06;         // leaf jitter amplitude (m)
uniform float alpha_cut = 0.3;
global uniform float tree_wind;       // 0 calm .. 1 normal .. 2.5 storm
varying float h;
void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;   // tree root (instance)
	h = clamp(VERTEX.y / max(tree_height, 0.1), 0.0, 1.0);
	float bend = h * h;                        // stiff trunk, loose top
	float t = TIME;
	float phase = dot(wpos.xz, vec2(0.013, 0.021));
	float gust = 0.6 + 0.4 * sin(t * 0.35 + phase * 2.0) * sin(t * 0.13 + phase);
	float w = tree_wind * gust;
	vec3 wind_dir = normalize(vec3(1.0, 0.0, 0.35));
	vec3 dir_local = normalize((inverse(mat3(MODEL_MATRIX)) * wind_dir) * vec3(1.0, 0.0, 1.0) + vec3(1e-4));
	float s = (sin(t * 1.3 + phase) * 0.6 + sin(t * 2.1 + phase * 1.7) * 0.4 + 0.6) * sway * w * bend;
	VERTEX += dir_local * s;
	VERTEX.y -= s * s * 0.15 / max(tree_height, 0.1) * tree_height * 0.02;   // tiny droop as it bends
	// leaf flutter: high-frequency, per-vertex, only in the canopy
	float leaf = smoothstep(0.35, 0.75, h);
	VERTEX += vec3(sin(t * 7.0 + VERTEX.x * 3.1 + phase * 9.0), sin(t * 9.0 + VERTEX.z * 2.7) * 0.5, cos(t * 6.3 + VERTEX.y * 2.3 + phase * 7.0)) * flutter * w * leaf;
}
void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	if (has_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		ROUGHNESS = orm.g; METALLIC = orm.b;
	} else {
		ROUGHNESS = 0.85;
	}
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	BACKLIGHT = vec3(0.25, 0.3, 0.15) * h;   // sun shining through leaves
}
