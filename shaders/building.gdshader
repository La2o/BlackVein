shader_type spatial;
// Procedural skyscraper facade: windows with frames and blinds, floor bands,
// pilasters, ground-floor storefronts, grime and per-building color variety,
// all drawn from world position so every building of any size looks right.
// Walls are concrete, brick or plaster photo textures (CC0, assets/CREDITS.md),
// picked per building; roofs are gravel.
// `style` picks the kind of building: 0 city block, 1 house (painted clapboard, framed windows,
// a door), 2 warehouse (corrugated metal, roll-up doors, a high window strip), 3 barn (red planks).

uniform vec3 wall_color : source_color = vec3(0.6, 0.58, 0.54);
uniform vec3 glass_color : source_color = vec3(0.14, 0.17, 0.21);
uniform vec3 lit_color : source_color = vec3(1.0, 0.78, 0.48);
uniform float floor_height = 3.5;
uniform float window_width = 2.6;
uniform float window_fill = 0.62;
uniform float lit_chance = 0.25;
uniform float night = 0.0;
uniform float wetness = 0.0;
uniform sampler2D concrete_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
instance uniform float tint = 0.0;     // -1..1, per-building brightness/hue shift
instance uniform float seed = 0.0;
instance uniform float style = 0.0;
instance uniform vec4 paint : source_color = vec4(0.85, 0.82, 0.74, 1.0);   // house / warehouse colour
uniform sampler2D siding_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D siding_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D barn_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D barn_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

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

// Small buildings outside the city: houses, warehouses and barns.
void small_building(vec3 n, out vec3 col, out float rough, out float metal, out vec3 emit, out vec3 nmap) {
	bool x_face = n.x > n.z;
	float u = x_face ? wpos.z : wpos.x;
	float y = wpos.y;
	float face_id = (x_face ? sign(wnorm.x) * 3.0 : sign(wnorm.z) * 7.0) + seed * 17.0;
	vec2 tuv = vec2(u, -y);
	col = paint.rgb;
	rough = 0.8;
	metal = 0.0;
	emit = vec3(0.0);
	nmap = vec3(0.5, 0.5, 1.0);
	if (style < 1.5) {
		// house: clapboard siding painted, windows every 3.4 m on each floor, a door on the ground floor
		col = texture(siding_col, tuv / 2.5).rgb * paint.rgb * 1.25;
		nmap = texture(siding_nrm, tuv / 2.5).rgb;
		vec2 cell = vec2(u / 3.4, (y - 0.15) / 3.0);
		vec2 f = fract(cell);
		float h = hash(floor(cell) + vec2(face_id, face_id * 0.37));
		float win = step(0.3, f.x) * step(f.x, 0.7) * step(0.3, f.y) * step(f.y, 0.78);
		float trim = step(0.25, f.x) * step(f.x, 0.75) * step(0.25, f.y) * step(f.y, 0.83) - win;
		bool ground = y < 3.0;
		float door = (ground && h < 0.22) ? step(0.32, f.x) * step(f.x, 0.68) * step(f.y, 0.75) : 0.0;
		if (door > 0.5) {
			col = mix(vec3(0.25, 0.12, 0.08), vec3(0.12, 0.18, 0.3), step(0.5, fract(seed * 13.0)));
			nmap = vec3(0.5, 0.5, 1.0);
		} else if (win > 0.5) {
			col = glass_color * 0.9;
			rough = 0.08;
			metal = 0.4;
			nmap = vec3(0.5, 0.5, 1.0);
			if (h < 0.35) {
				emit = lit_color * (0.04 + night * 0.7);
			}
		} else if (trim > 0.5) {
			col = vec3(0.9, 0.89, 0.85);
			nmap = vec3(0.5, 0.5, 1.0);
		}
		// a darker foundation strip
		col = mix(col, vec3(0.35, 0.34, 0.32), step(y, 0.55));
	} else if (style < 2.5) {
		// warehouse: corrugated metal (ribs run up the wall), roll-up doors, a high window strip
		vec2 muv = vec2(-y, u) / 3.0;
		col = texture(metal_col, muv).rgb * paint.rgb * 1.3;
		nmap = texture(metal_nrm, muv).rgb;
		metal = 0.35;
		rough = 0.55;
		float bay = fract(u / 12.0);
		float roll = step(0.33, bay) * step(bay, 0.67) * step(y, 4.8) * step(0.5, hash(vec2(floor(u / 12.0), face_id)));
		if (roll > 0.5) {
			col = vec3(0.55, 0.56, 0.55) * (0.8 + 0.2 * step(0.5, fract(y * 3.0)));
			metal = 0.5;
		}
		float wstrip = step(0.5, fract(u / 2.0)) ;
		// clerestory windows a little below the roof line (roof height comes from the box: use 8 m+)
		if (y > 6.2 && y < 7.4 && wstrip > 0.5) {
			col = glass_color;
			rough = 0.1;
			emit = lit_color * night * 0.35 * step(0.6, hash(vec2(floor(u / 2.0), face_id)));
			nmap = vec3(0.5, 0.5, 1.0);
		}
		col = mix(col, vec3(0.3, 0.3, 0.3), step(y, 0.4));
	} else {
		// barn: red planks running up the wall, white trim, a big double door
		vec2 buv = vec2(-y, u) / 3.0;
		col = texture(barn_col, buv).rgb * vec3(1.55, 0.75, 0.62) * paint.rgb;
		nmap = texture(barn_nrm, buv).rgb;
		float door_w = 4.5;
		float centre = abs(fract(u / 30.0) - 0.5) * 30.0;
		if (centre < door_w * 0.5 && y < 5.0) {
			col *= 0.8;
			// the white X on the doors
			float dx = (centre / (door_w * 0.5));
			float dy = y / 5.0;
			float xline = min(abs(dx - dy), abs(dx - (1.0 - dy)));
			if (xline < 0.06 || dy > 0.96 || dx > 0.94) {
				col = vec3(0.92, 0.9, 0.85);
			}
		}
	}
}


void fragment() {
	vec3 n = abs(wnorm);
	if (style > 0.5 && n.y < 0.5) {
		vec3 c;
		float r;
		float m;
		vec3 e;
		vec3 nm;
		small_building(n, c, r, m, e, nm);
		c *= mix(1.0, 0.75, wetness * (1.0 - m));
		ALBEDO = c;
		NORMAL_MAP = nm;
		ROUGHNESS = mix(r, r * 0.4, wetness);
		METALLIC = m;
		EMISSION = e;
	} else {
	vec3 base = wall_color * (1.0 + tint * 0.18);
	base = mix(base, base * vec3(1.06, 1.0, 0.92), max(tint, 0.0));
	vec3 col = base;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	if (n.y < 0.5) {
		bool x_face = n.x > n.z;
		float u = x_face ? wpos.z : wpos.x;
		// the wall material: concrete, brick or plaster, chosen per building
		float pick = fract(seed * 7.31 + 0.13);
		vec2 tuv = vec2(u, -wpos.y);
		vec3 wall_tex;
		if (pick < 0.4) {
			wall_tex = texture(concrete_col, tuv / 4.0).rgb;
			nmap = texture(concrete_nrm, tuv / 4.0).rgb;
			base *= wall_tex * 1.7;
		} else if (pick < 0.72) {
			wall_tex = texture(brick_col, tuv / 2.4).rgb;
			nmap = texture(brick_nrm, tuv / 2.4).rgb;
			base = wall_tex * (1.0 + tint * 0.15);   // brick keeps its own colour
		} else {
			wall_tex = texture(plaster_col, tuv / 3.0).rgb;
			nmap = texture(plaster_nrm, tuv / 3.0).rgb;
			base *= wall_tex * 1.45;
		}
		col = base;
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
				nmap = vec3(0.5, 0.5, 1.0);
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
				nmap = vec3(0.5, 0.5, 1.0);
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
				nmap = vec3(0.5, 0.5, 1.0);
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
				nmap = vec3(0.5, 0.5, 1.0);
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
		if (style > 1.5 && style < 2.5) {
			// warehouse: a corrugated metal roof
			col = texture(metal_col, wpos.xz / 3.0).rgb * paint.rgb * 1.1;
			nmap = texture(metal_nrm, wpos.xz / 3.0).rgb;
			metal = 0.4;
			rough = 0.5;
		} else {
			// roof: gravel with tar patches
			vec3 gravel = texture(gravel_col, wpos.xz / 3.0).rgb;
			nmap = texture(gravel_nrm, wpos.xz / 3.0).rgb;
			float tar = smoothstep(0.55, 0.6, noise(wpos.xz * 0.3 + seed * 5.0));
			col = mix(gravel * 0.62, vec3(0.06), tar * 0.8) * (1.0 + tint * 0.1);
			rough = mix(0.95, 0.6, tar);
		}
	}
	// rain makes surfaces darker and shinier
	col *= mix(1.0, 0.75, wetness * (1.0 - metal));
	rough = mix(rough, rough * 0.4, wetness);
	ALBEDO = col;
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
	}
}
