shader_type spatial;
// Lagos Lagoon: animated ripples, fresnel sky reflection, murky green-brown depth.
global uniform float night_factor;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float waves(vec2 p, float t) {
	return noise(p * 0.12 + vec2(t * 0.05, t * 0.03)) * 0.6 + noise(p * 0.4 - vec2(t * 0.11, -t * 0.07)) * 0.4;
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = TIME;
	float e = 0.5;
	float h = waves(wpos.xz, t);
	float hx = waves(wpos.xz + vec2(e, 0.0), t) - h;
	float hz = waves(wpos.xz + vec2(0.0, e), t) - h;
	vec3 n = normalize(vec3(-hx * 3.0, 1.0, -hz * 3.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 deep = mix(vec3(0.10, 0.22, 0.22), vec3(0.02, 0.04, 0.07), night_factor);
	vec3 sky = mix(vec3(0.55, 0.62, 0.68), vec3(0.06, 0.08, 0.14), night_factor);
	ALBEDO = mix(deep, sky, fres * 0.7);
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
	SPECULAR = 0.8;
}
