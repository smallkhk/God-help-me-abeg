shader_type spatial;
render_mode cull_disabled;
// Asphalt deck (speckled, worn) + concrete barriers (vertical faces).
varying vec3 wpos;
varying vec3 wnorm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	if (abs(wnorm.y) > 0.6) {
		float speck = hash(floor(wpos.xz * 25.0)) * 0.08;
		float patches = noise(wpos.xz * 0.08) * 0.12;
		float v = 0.20 + speck + patches;
		ALBEDO = vec3(v, v, v * 1.03);
		ROUGHNESS = 0.92 - patches;
	} else {
		float n = noise(wpos.xz * 0.5 + wpos.y) * 0.15;
		ALBEDO = vec3(0.72, 0.70, 0.66) * (0.9 + n);
		ROUGHNESS = 0.95;
	}
}
