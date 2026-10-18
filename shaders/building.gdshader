shader_type spatial;
// Procedural skyscraper facade: windows with frames and blinds, floor bands,
// pilasters, ground-floor storefronts, grime and per-building color variety,
// all drawn from world position so every building of any size looks right.

uniform vec3 wall_color : source_color = vec3(0.6, 0.58, 0.54);
uniform vec3 glass_color : source_color = vec3(0.14, 0.17, 0.21);
uniform vec3 lit_color : source_color = vec3(1.0, 0.78, 0.48);
uniform float floor_height = 3.5;
uniform float window_width = 2.6;
uniform float window_fill = 0.62;
uniform float lit_chance = 0.25;
uniform float night = 0.0;
uniform float wetness = 0.0;
instance uniform float tint = 0.0;     // -1..1, per-building brightness/hue shift
instance uniform float seed = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

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
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(wnorm);
	vec3 base = wall_color * (1.0 + tint * 0.18);
	base = mix(base, base * vec3(1.06, 1.0, 0.92), max(tint, 0.0));
	vec3 col = base;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	if (n.y < 0.5) {
		bool x_face = n.x > n.z;
		float u = x_face ? wpos.z : wpos.x;
		float face_id = (x_face ? sign(wnorm.x) * 3.0 : sign(wnorm.z) * 7.0) + seed * 17.0;
		float y = wpos.y;
		// streaks of grime running down from the windows
		float streak = noise(vec2(u * 1.7, y * 0.05 + seed * 9.0));
		float grime = mix(0.8, 1.0, clamp(y / 30.0, 0.0, 1.0)) * (0.92 + streak * 0.08);
		if (y < 4.6) {
			// ground floor: tall shop windows with a dark frame and a sign band
			float cell_w = 5.0;
			float fu = fract(u / cell_w);
			float shop = step(0.08, fu) * step(fu, 0.92) * step(0.35, y) * step(y, 3.4);
			float sign_band = step(3.6, y) * step(y, 4.4);
			float h = hash(vec2(floor(u / cell_w), face_id));
			if (shop > 0.5) {
				vec3 inside = mix(vec3(0.9, 0.75, 0.5), vec3(0.6, 0.8, 0.95), step(0.6, h));
				col = mix(glass_color * 0.7, inside * 0.35, 0.4);
				rough = 0.08;
				metal = 0.3;
				emit = inside * (0.04 + night * 0.4) * step(0.25, h);
			} else if (sign_band > 0.5) {
				vec3 sign_col = vec3(0.7, 0.15, 0.1);
				if (h > 0.25) sign_col = vec3(0.1, 0.35, 0.6);
				if (h > 0.5) sign_col = vec3(0.15, 0.45, 0.25);
				if (h > 0.75) sign_col = vec3(0.75, 0.55, 0.1);
				col = sign_col * 0.6;
				emit = sign_col * night * 0.9 * step(0.3, h);
				rough = 0.5;
			} else {
				col = base * 0.45;
			}
		} else {
			vec2 cell = vec2(u / window_width, y / floor_height);
			vec2 id = floor(cell);
			vec2 f = fract(cell);
			float half_gap = (1.0 - window_fill) * 0.5;
			float win = step(half_gap, f.x) * step(f.x, 1.0 - half_gap) * step(0.22, f.y) * step(f.y, 0.86);
			float frame = step(half_gap - 0.04, f.x) * step(f.x, 1.0 - half_gap + 0.04) * step(0.18, f.y) * step(f.y, 0.9) - win;
			float h = hash(id + vec2(face_id * 13.7, face_id * 3.1));
			// pilaster every 4 window columns
			float pilaster = 1.0 - step(0.06, abs(fract(cell.x / 4.0) - 0.0)) ;
			if (win > 0.5) {
				float tint_g = 0.85 + h * 0.3;
				col = glass_color * tint_g;
				rough = 0.06 + h * 0.08;
				metal = 0.55;
				// blinds pulled partway down on some windows
				float blind = step(1.0 - fract(h * 37.0) * 0.6, 1.0 - (f.y - 0.22) / 0.64) * step(0.55, fract(h * 11.0));
				col = mix(col, vec3(0.75, 0.72, 0.65) * 0.5, blind);
				rough = mix(rough, 0.8, blind);
				metal = mix(metal, 0.0, blind);
				if (h < lit_chance) {
					emit = lit_color * (0.06 + night * 0.75) * (0.5 + fract(h * 91.0) * 0.6);
					emit *= mix(1.0, 0.45, blind);
				}
			} else if (frame > 0.5) {
				col = base * 0.55;
				rough = 0.4;
				metal = 0.2;
			} else {
				float band = step(0.93, f.y);
				col = mix(base, base * 0.75, band);
				col = mix(col, base * 1.08, pilaster * 0.6);
			}
			col *= grime;
		}
	} else {
		// roof: gravel with tar patches
		float g = noise(wpos.xz * 2.5) * 0.15 + hash(floor(wpos.xz * 8.0)) * 0.05;
		col = base * (0.42 + g);
		rough = 0.95;
	}
	// rain makes surfaces darker and shinier
	col *= mix(1.0, 0.75, wetness * (1.0 - metal));
	rough = mix(rough, rough * 0.4, wetness);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
