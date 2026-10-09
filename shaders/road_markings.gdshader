shader_type spatial;
render_mode cull_disabled;
// Lane paint: worn, chipped and faded like a real Lagos road.
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float wear = noise(wpos.xz * 1.7) * 0.6 + noise(wpos.xz * 9.0) * 0.4;
	float fade = noise(wpos.xz * 0.02);           // whole stretches faded
	if (wear < 0.32 + fade * 0.25) discard;       // chipped away
	ALBEDO = COLOR.rgb * mix(0.65, 1.0, wear);
	ROUGHNESS = 0.7;
}
