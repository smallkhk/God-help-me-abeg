shader_type spatial;
render_mode cull_disabled;
// Stylised Lagos buildings. Vertex alpha = surface type:
//   ~0.0 painted wall with windows   ~0.25 concrete roof   ~0.5 zinc
//   ~0.75 clay tile                  ~1.0 plain colour (parapet, awning, tank)
// Wall UV: x = metres along wall, y = metres up. Roof UV: x along, y up-slope.
global uniform float night_factor;
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float box(vec2 f, vec2 lo, vec2 hi) { return step(lo.x, f.x) * step(f.x, hi.x) * step(lo.y, f.y) * step(f.y, hi.y); }

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec3 col = COLOR.rgb;
	float k = COLOR.a;
	float rough = 0.9;
	float metal = 0.0;
	vec3 emit = vec3(0.0);

	if (k < 0.12) {
		// --- painted wall with framed windows ---
		vec2 uv = UV;
		float fh = 3.2;              // floor height
		float ww = 2.8;              // window bay width
		vec2 cell = vec2(floor(uv.x / ww), floor(uv.y / fh));
		vec2 f = vec2(fract(uv.x / ww), fract(uv.y / fh));
		float upper = step(fh, uv.y);
		float frame = box(f, vec2(0.24, 0.30), vec2(0.76, 0.80)) * upper;
		float glass = box(f, vec2(0.29, 0.35), vec2(0.71, 0.76)) * upper;
		float bar = (1.0 - step(0.012, abs(f.x - 0.5))) * glass;       // centre mullion
		float sill = box(f, vec2(0.22, 0.27), vec2(0.78, 0.31)) * upper;
		float slab = (1.0 - step(0.035, f.y)) * upper;                  // floor line
		float ground = 1.0 - upper;
		// ground floor: doors / shop shutters
		float door = box(f, vec2(0.30, 0.0), vec2(0.70, 0.78)) * ground;
		float grime = noise(vec2(uv.x * 0.35, uv.y * 0.12)) * 0.10 + smoothstep(1.2, 0.0, uv.y) * 0.10;
		vec3 wall = col * 0.88 * (1.0 - grime);
		wall = mix(wall, wall * 0.82, slab);
		vec3 gcol = mix(vec3(0.18, 0.26, 0.34), vec3(0.35, 0.50, 0.62), hash(cell) * 0.6);
		vec3 fcol = vec3(0.95, 0.95, 0.93);
		vec3 shutter = vec3(0.45, 0.47, 0.50) * (0.85 + 0.15 * step(0.5, fract(uv.y * 6.0)));
		col = wall;
		col = mix(col, fcol, max(frame, sill));
		col = mix(col, gcol, glass);
		col = mix(col, fcol, bar);
		col = mix(col, shutter, door);
		rough = mix(0.92, 0.12, glass);
		float lit = step(0.5, hash(cell + 7.3)) * glass * night_factor;
		emit = lit * vec3(1.0, 0.80, 0.48) * 1.6;
	} else if (k < 0.37) {
		// --- flat concrete roof ---
		col = vec3(0.66, 0.64, 0.60) * (0.85 + 0.2 * noise(wpos.xz * 0.6));
		rough = 0.95;
	} else if (k < 0.62) {
		// --- corrugated zinc ---
		float ridges = 0.5 + 0.5 * sin(UV.x * 22.0);
		float rust = smoothstep(0.5, 0.85, noise(wpos.xz * 0.3));
		col = mix(vec3(0.70, 0.72, 0.74), vec3(0.58, 0.32, 0.18), rust) * (0.82 + 0.18 * ridges);
		rough = 0.5;
		metal = 0.35 * (1.0 - rust);
	} else if (k < 0.87) {
		// --- clay tiles ---
		float row = fract(UV.y * 2.6);
		float off = step(0.5, fract(UV.y * 1.3)) * 0.5;
		float tcol = fract(UV.x * 3.0 + off);
		float shade = 0.78 + 0.22 * smoothstep(0.0, 0.5, row) - 0.1 * step(0.92, tcol);
		col = col * shade * (0.92 + 0.12 * hash(floor(wpos.xz * 0.5)));
		rough = 0.8;
	} else {
		// --- plain painted part ---
		col *= 0.95 + 0.05 * noise(wpos.xz * 2.0 + wpos.y);
		rough = 0.85;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
