shader_type spatial;
// Farm fields: rows of crops over soil, drawn from world position. `kind` picks the crop per field:
// 0 plowed soil, 1 ripe wheat, 2 green crop, 3 pasture. Textures are CC0 (assets/CREDITS.md).

uniform sampler2D soil_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wetness = 0.0;
instance uniform float kind = 0.0;
instance uniform float rows_x = 0.0;   // 1: rows run along x, 0: along z

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float across = rows_x > 0.5 ? p.y : p.x;
	float row = 0.5 + 0.5 * sin(across * TAU / 1.3);
	vec3 soil = texture(soil_col, p / 4.0).rgb * vec3(0.72, 0.58, 0.44);
	vec3 grass = texture(grass_col, p / 4.0).rgb;
	float patchy = noise(p * 0.05);
	vec3 col;
	vec3 nm = texture(soil_nrm, p / 4.0).rgb;
	float rough = 0.95;
	if (kind < 0.5) {
		col = soil * (0.65 + 0.35 * row);   // furrows
	} else if (kind < 1.5) {
		vec3 wheat = vec3(0.86, 0.72, 0.36) * (0.82 + 0.25 * noise(p * 3.0)) * (0.9 + 0.2 * patchy);
		col = mix(soil * 0.8, wheat, smoothstep(0.15, 0.55, row));
		nm = mix(nm, vec3(0.5, 0.5, 1.0), 0.5);
	} else if (kind < 2.5) {
		vec3 crop = grass * vec3(0.75, 1.15, 0.6) * (0.85 + 0.3 * patchy);
		col = mix(soil * 0.75, crop, smoothstep(0.3, 0.7, row));
		nm = mix(nm, texture(grass_nrm, p / 4.0).rgb, 0.6);
	} else {
		col = grass * (0.9 + 0.2 * patchy);
		nm = texture(grass_nrm, p / 4.0).rgb;
	}
	col *= mix(1.0, 0.7, wetness);
	ALBEDO = col;
	NORMAL_MAP = nm;
	ROUGHNESS = mix(rough, 0.5, wetness);
}
