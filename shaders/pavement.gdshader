shader_type spatial;
// Concrete pavement slabs (60 x 60 cm) with worn joints, dust and stains.
// UV: x = metres across the pavement, y = metres along it.
uniform sampler2D tex_concrete : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_concrete_n : hint_normal, filter_linear_mipmap, repeat_enable;
global uniform float wetness;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = UV;
	vec2 cell = floor(uv / 0.6);
	vec2 f = fract(uv / 0.6);
	float joint = 1.0 - smoothstep(0.0, 0.04, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	vec3 c = texture(tex_concrete, uv * 0.5).rgb;
	c = c / max(dot(c, vec3(0.333)), 0.05) * vec3(0.62, 0.61, 0.59);
	c *= 0.9 + 0.18 * hash(cell);                                     // slab to slab variation
	c = mix(c, vec3(0.55, 0.47, 0.36), smoothstep(0.6, 0.9, noise(wpos.xz * 0.15)) * 0.25);   // red dust
	c *= 1.0 - smoothstep(0.62, 0.9, noise(wpos.xz * 0.7 + 7.0)) * 0.3;                          // stains
	c *= 1.0 - joint * 0.35;
	c *= 1.0 - wetness * 0.35;
	ALBEDO = c;
	ROUGHNESS = mix(0.92, 0.35, wetness);
	vec3 tn = texture(tex_concrete_n, uv * 0.5).rgb * 2.0 - 1.0;
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(normalize(vec3(tn.x * 0.4, 1.0, -tn.y * 0.4)), 0.0)).xyz, 0.6));
}
