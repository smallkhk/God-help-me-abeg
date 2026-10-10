shader_type spatial;
render_mode cull_disabled;
// Off-road dirt trail: packed laterite with two worn wheel ruts, loose gravel,
// grass creeping in from the verges and a crown of weeds down the middle.
varying vec3 wpos;
varying vec2 ruv;
global uniform float wetness;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform float half_width = 5.5;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) { return noise(p) * 0.5 + noise(p * 2.03) * 0.25 + noise(p * 4.1) * 0.125 + noise(p * 8.3) * 0.0625; }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ruv = UV;
}
void fragment() {
	vec3 dirt = texture(tex_dirt, wpos.xz * 0.22).rgb;
	vec3 grass = texture(tex_grass, wpos.xz * 0.18).rgb;
	// Lagos laterite: push the dirt towards red-orange
	dirt *= vec3(1.12, 0.86, 0.68);
	float lat = ruv.x + (fbm(vec2(ruv.y * 0.05, 1.0)) - 0.5) * 1.2;   // ruts wander
	float a = abs(lat);
	float rut = exp(-pow((a - 1.0) / 0.38, 2.0));
	float big = fbm(wpos.xz * 0.15);
	vec3 alb = dirt * (0.75 + big * 0.5);
	alb = mix(alb, alb * vec3(0.62, 0.55, 0.5), rut * 0.8);             // compacted ruts, darker
	float gravel = step(0.82, hash(floor(wpos.xz * 14.0))) * (1.0 - rut);
	alb = mix(alb, vec3(0.62, 0.58, 0.52), gravel * 0.6);
	float verge = smoothstep(half_width - 2.2, half_width - 0.2, abs(ruv.x) + (fbm(wpos.xz * 0.4) - 0.5) * 1.8);
	float crown = (1.0 - smoothstep(0.15, 0.45, a)) * step(0.45, fbm(wpos.xz * 0.7)) * 0.6;
	alb = mix(alb, grass * 0.85, clamp(verge + crown, 0.0, 1.0));
	// puddle in the occasional dip of a rut
	float pud = smoothstep(0.72 - wetness * 0.2, 0.8 - wetness * 0.2, fbm(wpos.xz * 0.08 + 7.0)) * rut;
	alb *= 1.0 - wetness * 0.35;   // mud
	alb = mix(alb, alb * 0.35 + vec3(0.03, 0.03, 0.035), pud);
	ALBEDO = alb;
	ROUGHNESS = mix(0.95, 0.08, pud);
	SPECULAR = 0.3 + pud * 0.4;
	// small-scale bump from noise
	float e = 0.05;
	float h0 = fbm(wpos.xz * 3.0);
	float hx = fbm((wpos.xz + vec2(e, 0.0)) * 3.0);
	float hz = fbm((wpos.xz + vec2(0.0, e)) * 3.0);
	vec3 wn = normalize(vec3(-(hx - h0) * 6.0 * (1.0 - pud), 1.0, -(hz - h0) * 6.0 * (1.0 - pud)));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
