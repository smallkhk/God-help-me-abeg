shader_type spatial;
render_mode cull_disabled;
// Lagos ground: sandy soil with dusty dirt and patchy grass, world-space tiled.
// Vertex alpha: 1 = open ground, 0 = shoreline wall, 0.5 = side street (laterite/sand road).
uniform sampler2D tex_sand : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz * 0.12;
	vec3 sand = texture(tex_sand, uv).rgb;
	vec3 dirt = texture(tex_dirt, uv * 0.8).rgb;
	vec3 grass = texture(tex_grass, uv * 0.6).rgb;
	float n1 = noise(wpos.xz * 0.02) * 0.6 + noise(wpos.xz * 0.08) * 0.4;
	float n2 = noise(wpos.xz * 0.035 + 17.0);
	vec3 col = mix(sand, dirt, smoothstep(0.35, 0.7, n1));
	col = mix(col, grass, smoothstep(0.62, 0.8, n2) * 0.8);
	if (COLOR.a < 0.25) {
		col = COLOR.rgb;                              // shoreline wall
	} else if (COLOR.a < 0.75) {
		// side street: compacted reddish laterite with tyre ruts
		vec3 lat = dirt * vec3(1.05, 0.82, 0.68);
		float rut = smoothstep(0.08, 0.0, abs(fract(UV.x) - 0.3)) + smoothstep(0.08, 0.0, abs(fract(UV.x) - 0.7));
		col = mix(lat, lat * 0.75, rut * 0.6);
	}
	ALBEDO = col;
	ROUGHNESS = 0.97;
}
