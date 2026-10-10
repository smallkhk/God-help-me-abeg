shader_type spatial;
render_mode cull_disabled;
// Lagos ground: sun-baked sand, red laterite, cracked dry mud, patchy grass,
// sachet-water litter, bumpy normals and rain puddles. World-space tiled with
// two scales mixed (no visible tiling), all from the three CC0 photo textures.
// Vertex alpha: 1 = open ground, 0 = shoreline wall, 0.5 = side street (laterite/sand road).
uniform sampler2D tex_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
global uniform float wetness;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) { return noise(p) * 0.5 + noise(p * 2.1) * 0.25 + noise(p * 4.3) * 0.125 + noise(p * 8.7) * 0.0625; }
// distance to the nearest Voronoi edge -> dried-mud cracks
float crack(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	float d1 = 8.0, d2 = 8.0;
	for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y));
		vec2 o = hash2(i + g);
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return d2 - d1;
}
vec3 tex2(sampler2D t, vec2 uv) {
	// two scales, rotated, blended by noise: kills the photo-tile repeat
	vec2 r = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * uv * 0.37;
	return mix(texture(t, uv).rgb, texture(t, r).rgb, 0.35 + noise(uv * 0.21) * 0.3);
}
float lum(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz * 0.12;
	vec3 sand = tex2(tex_sand, uv) * vec3(1.06, 1.0, 0.9);
	vec3 dirt = tex2(tex_dirt, uv * 0.8) * vec3(1.12, 0.84, 0.66);   // red laterite
	vec3 grass = tex2(tex_grass, uv * 0.6) * vec3(0.9, 1.08, 0.82);
	float n1 = fbm(wpos.xz * 0.018);
	float n2 = fbm(wpos.xz * 0.03 + 17.0);
	float n3 = fbm(wpos.xz * 0.06 + 41.0);
	vec3 col = mix(sand, dirt, smoothstep(0.38, 0.62, n1));
	// dry cracked mud plates in the laterite
	float mud = smoothstep(0.55, 0.7, n3) * smoothstep(0.45, 0.6, n1);
	float cr = 1.0 - smoothstep(0.0, 0.06, crack(wpos.xz * 0.9));
	col = mix(col, col * vec3(1.08, 0.98, 0.9), mud * 0.6);
	col *= 1.0 - cr * mud * 0.55;
	// grass patches with ragged edges
	float gm = smoothstep(0.58, 0.72, n2 + (noise(wpos.xz * 0.7) - 0.5) * 0.12);
	col = mix(col, grass, gm * 0.9);
	// macro tone: sun-bleached vs damp/shaded zones
	col *= 0.86 + fbm(wpos.xz * 0.006 + 3.0) * 0.3;
	// litter: sachet-water bags, bottle caps, nylon (Lagos roadside)
	vec2 lc = floor(wpos.xz * 2.2);
	float lit = step(0.986, hash(lc + 7.7)) * (1.0 - gm * 0.7);
	vec2 lf = fract(wpos.xz * 2.2) - 0.5;
	lit *= step(length(lf * vec2(1.0, 1.6)), 0.3);
	vec3 litc = mix(vec3(0.85, 0.9, 0.95), mix(vec3(0.15, 0.35, 0.8), vec3(0.8, 0.15, 0.1), hash(lc + 3.0)), step(0.6, hash(lc)));
	col = mix(col, litc, lit * 0.9);
	// pebbles
	float peb = step(0.93, hash(floor(wpos.xz * 6.0))) * (1.0 - gm);
	col = mix(col, vec3(0.55, 0.5, 0.45) * (0.7 + hash(floor(wpos.xz * 6.0) + 1.0) * 0.6), peb * 0.5);

	float rough = mix(0.96, 0.85, gm);
	// rain: darker soaked ground and puddles in the low spots
	float pud = smoothstep(0.62, 0.7, fbm(wpos.xz * 0.05 + 9.0) + (1.0 - wetness) * 0.4) * wetness * (1.0 - gm);
	col *= 1.0 - wetness * 0.35;
	col = mix(col, col * 0.35 + vec3(0.02, 0.025, 0.03), pud);
	rough = mix(rough, 0.05, max(pud, wetness * 0.2));

	if (COLOR.a < 0.25) {
		col = COLOR.rgb;                              // shoreline wall
	} else if (COLOR.a < 0.75) {
		// side street: compacted reddish laterite with tyre ruts
		vec3 lat = dirt;
		float rut = smoothstep(0.08, 0.0, abs(fract(UV.x) - 0.3)) + smoothstep(0.08, 0.0, abs(fract(UV.x) - 0.7));
		col = mix(lat, lat * 0.72, rut * 0.6) * (1.0 - wetness * 0.3);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35 + pud * 0.5;
	// bump from the photo luminance + cracks (cheap normal mapping)
	float e = 0.02;
	float h0 = lum(texture(tex_dirt, uv * 0.8).rgb) + lum(texture(tex_sand, uv).rgb) - cr * mud * 0.6;
	float hx = lum(texture(tex_dirt, (uv + vec2(e, 0.0)) * 0.8).rgb) + lum(texture(tex_sand, uv + vec2(e, 0.0)).rgb);
	float hz = lum(texture(tex_dirt, (uv + vec2(0.0, e)) * 0.8).rgb) + lum(texture(tex_sand, uv + vec2(0.0, e)).rgb);
	float bs = 1.6 * (1.0 - pud);
	vec3 wn = normalize(vec3(-(hx - h0) * bs, 1.0, -(hz - h0) * bs));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
