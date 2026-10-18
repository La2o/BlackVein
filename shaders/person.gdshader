shader_type spatial;
// Quaternius base body (CC0) with clothes painted on. Each vertex carries a region in its colour,
// worked out once from the rest pose by person.gd: r = trousers, g = shirt, b = shoes,
// a = 1 where a long sleeve or a coat covers skin. The fabric gets a little weave from the UVs.

uniform sampler2D skin_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap;
uniform vec3 skin_tint : source_color = vec3(1.0);
uniform vec3 shirt_color : source_color = vec3(0.3, 0.35, 0.45);
uniform vec3 pants_color : source_color = vec3(0.2, 0.22, 0.3);
uniform vec3 shoe_color : source_color = vec3(0.1, 0.09, 0.08);
uniform float long_sleeves = 1.0;
uniform float shirtless = 0.0;   // infected: torn down to skin
uniform float camo = 0.0;
uniform float denim = 0.0;
uniform vec3 glow_color : source_color = vec3(0.0);   // veins / tech lights
uniform float glow = 0.0;
uniform float vein_amount = 1.0;   // 1 = infected, lower = a few faint veins

varying vec4 region;

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
	region = COLOR;
}

void fragment() {
	vec3 skin = texture(skin_tex, UV).rgb * skin_tint;
	// soft edges so hems don't follow the mesh's triangles
	float pants = smoothstep(0.35, 0.65, region.r);
	float shoes = smoothstep(0.35, 0.65, region.b);
	float shirt = smoothstep(0.35, 0.65, region.g) * (1.0 - shirtless);
	float sleeve = smoothstep(0.35, 0.65, region.a) * long_sleeves * (1.0 - shirtless);
	shirt = max(shirt, sleeve);
	float cloth = max(max(pants, shirt), shoes);
	float weave = noise(UV * 900.0) * 0.06 + noise(UV * 60.0) * 0.08;
	vec3 shirt_c = shirt_color;
	vec3 pants_c = pants_color;
	if (camo > 0.5) {
		float c1 = noise(UV * 40.0);
		float c2 = noise(UV * 85.0 + 7.0);
		vec3 camo_c = mix(vec3(0.24, 0.27, 0.18), vec3(0.36, 0.33, 0.24), step(0.5, c1));
		camo_c = mix(camo_c, vec3(0.13, 0.14, 0.1), step(0.62, c2));
		shirt_c = mix(shirt_c, camo_c, 0.85);
		pants_c = mix(pants_c, camo_c, 0.85);
	}
	if (denim > 0.5) {
		pants_c *= 0.9 + noise(vec2(UV.x * 1600.0, UV.y * 400.0)) * 0.2;
	}
	vec3 col = skin;
	col = mix(col, pants_c * (0.92 + weave), pants);
	col = mix(col, shirt_c * (0.92 + weave), shirt);
	col = mix(col, shoe_color, shoes);
	float rough = texture(rough_tex, UV).r;
	rough = mix(rough, 0.85, cloth);
	rough = mix(rough, 0.45, shoes);
	ALBEDO = col;
	ROUGHNESS = rough;
	// clothes hide most of the muscle detail of the body underneath
	NORMAL_MAP = mix(texture(normal_tex, UV).rgb, vec3(0.5, 0.5, 1.0), cloth * 0.85);
	// glowing veins: thin bright lines wandering over bare skin
	float vein = 1.0 - smoothstep(0.0, 0.035 * vein_amount, abs(noise(UV * 55.0) - 0.5));
	vein *= smoothstep(1.0 - vein_amount, 1.0, noise(UV * 9.0 + 3.0));
	EMISSION = glow_color * glow * vein * 2.5 * (1.0 - cloth);
	ALBEDO = mix(ALBEDO, ALBEDO * 0.7 + glow_color * 0.3, glow * vein * (1.0 - cloth));
}
