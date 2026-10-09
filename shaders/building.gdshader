shader_type spatial;
render_mode cull_disabled;
// Lagos buildings: painted walls with per-floor window grid, corrugated zinc /
// concrete roofs. UV.x = metres along the wall, UV.y = metres up from ground.
global uniform float night_factor;

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
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
	vec3 base = COLOR.rgb;
	bool roof = abs(wnorm.y) > 0.7;
	if (roof) {
		// big flat roofs (towers) = concrete, small = corrugated zinc w/ rust
		float zinc = step(0.35, COLOR.a);
		float ridges = 0.5 + 0.5 * sin(wpos.x * 18.0 + wpos.z * 3.0);
		float rust = smoothstep(0.45, 0.8, noise(wpos.xz * 0.35));
		vec3 metal = mix(vec3(0.62, 0.64, 0.66), vec3(0.52, 0.28, 0.16), rust) * (0.85 + 0.15 * ridges);
		vec3 conc = vec3(0.55, 0.54, 0.52) * (0.85 + 0.15 * noise(wpos.xz * 0.8));
		ALBEDO = mix(conc, metal, zinc);
		ROUGHNESS = mix(0.95, 0.55, zinc);
		METALLIC = mix(0.0, 0.4, zinc * (1.0 - rust));
	} else {
		vec2 uv = UV;
		float grime = noise(vec2(uv.x * 0.4, uv.y * 0.15)) * 0.18 + smoothstep(2.0, 0.0, uv.y) * 0.12;
		vec3 wall = base * (1.0 - grime);
		vec2 cell = vec2(floor(uv.x / 3.0), floor(uv.y / 3.2));
		vec2 f = vec2(fract(uv.x / 3.0), fract(uv.y / 3.2));
		float win = step(0.22, f.x) * step(f.x, 0.78) * step(0.32, f.y) * step(f.y, 0.78) * step(1.0, uv.y);
		vec3 glass = vec3(0.16, 0.20, 0.25) + 0.08 * hash(cell);
		ALBEDO = mix(wall, glass, win);
		ROUGHNESS = mix(0.9, 0.15, win);
		float lit = step(0.55, hash(cell + 7.3)) * win * night_factor;
		EMISSION = lit * vec3(1.0, 0.78, 0.45) * 1.6;
	}
}
