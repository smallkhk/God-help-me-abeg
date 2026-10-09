shader_type spatial;
render_mode cull_disabled;
// Asphalt deck (speckled, worn) + concrete barriers (vertical faces).
varying vec3 wpos;
uniform sampler2D tex_asphalt : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_concrete : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_asphalt_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_asphalt_r : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_concrete_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float bump_strength = 1.0;
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
		float v = 0.10 + speck * 0.7 + patches * 0.6;
		// real asphalt photo (CC0) at 4 m tiling + large-scale wear patches
		vec3 a = texture(tex_asphalt, wpos.xz * 0.25).rgb;
		vec3 alb = a * (0.55 + patches * 2.0) + vec3(speck * 0.2);
		// tar patches (darker repair rectangles)
		vec2 pc = floor(wpos.xz / vec2(6.0, 9.0));
		vec2 pf = fract(wpos.xz / vec2(6.0, 9.0));
		float tarp = step(0.86, hash(pc + 3.1)) * step(0.15, pf.x) * step(pf.x, 0.75) * step(0.2, pf.y) * step(pf.y, 0.7);
		alb = mix(alb, alb * 0.55, tarp);
		// potholes: small dark wet dips
		vec2 hc = floor(wpos.xz / 4.0);
		vec2 hp = (fract(wpos.xz / 4.0) - 0.5) * 4.0 + (vec2(hash(hc), hash(hc + 9.0)) - 0.5) * 2.0;
		float hole = step(0.965, hash(hc + 17.0)) * (1.0 - smoothstep(0.35, 0.6 + noise(wpos.xz * 3.0) * 0.3, length(hp)));
		alb = mix(alb, vec3(0.04, 0.035, 0.03), hole);
		ALBEDO = alb;
		ROUGHNESS = clamp(texture(tex_asphalt_r, wpos.xz * 0.25).r - patches * 0.5 - hole * 0.6, 0.15, 1.0);
		vec3 tn = texture(tex_asphalt_n, wpos.xz * 0.25).rgb * 2.0 - 1.0;
		vec3 wn = normalize(vec3(tn.x, 1.0, -tn.y) * vec3(bump_strength, 1.0, bump_strength));
		NORMAL = normalize((VIEW_MATRIX * vec4(wn * sign(wnorm.y), 0.0)).xyz);
	} else {
		// Lagos-style kerb paint: black / white blocks along the barrier
		float n = noise(wpos.xz * 0.5 + wpos.y) * 0.1;
		float stripe = step(0.5, fract((wpos.x + wpos.z) * 0.25));
		// land roads: Lagos yellow/black kerbs; bridge: black/white
		vec3 light = wpos.y < 4.0 ? vec3(0.95, 0.78, 0.10) : vec3(0.92, 0.92, 0.90);
		vec3 paint = mix(light, vec3(0.10, 0.10, 0.11), stripe);
		vec3 conc = texture(tex_concrete, vec2(wpos.x + wpos.z, wpos.y) * 0.3).rgb;
		ALBEDO = paint * (0.75 + n) * (conc / max(dot(conc, vec3(0.333)), 0.05) * 0.4 + 0.6);
		ROUGHNESS = 0.95;
		vec3 cn = texture(tex_concrete_n, vec2(wpos.x + wpos.z, wpos.y) * 0.3).rgb * 2.0 - 1.0;
		vec3 n0 = normalize(wnorm);
		vec3 tx = normalize(cross(vec3(0.0, 1.0, 0.0), n0));
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n0 + (tx * cn.x + vec3(0.0, 1.0, 0.0) * cn.y) * 0.8), 0.0)).xyz);
	}
}
