shader_type spatial;
// Procedural skyscraper facade: windows, floor bands and a roof, drawn from
// world position so every building of any size gets correct-looking windows.

uniform vec3 wall_color : source_color = vec3(0.6, 0.58, 0.54);
uniform vec3 glass_color : source_color = vec3(0.14, 0.17, 0.21);
uniform vec3 lit_color : source_color = vec3(1.0, 0.78, 0.48);
uniform float floor_height = 3.5;
uniform float window_width = 2.6;
uniform float window_fill = 0.62;
uniform float lit_chance = 0.25;
uniform float night = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(wnorm);
	vec3 col = wall_color;
	float rough = 0.9;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	if (n.y < 0.5) {
		bool x_face = n.x > n.z;
		float u = x_face ? wpos.z : wpos.x;
		float face_id = x_face ? sign(wnorm.x) * 3.0 : sign(wnorm.z) * 7.0;
		vec2 cell = vec2(u / window_width, wpos.y / floor_height);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float half_gap = (1.0 - window_fill) * 0.5;
		float win = step(half_gap, f.x) * step(f.x, 1.0 - half_gap) * step(0.22, f.y) * step(f.y, 0.86);
		if (wpos.y < 0.6) {
			win = 0.0;
		}
		float h = hash(id + vec2(face_id * 13.7, face_id * 3.1));
		if (win > 0.5) {
			float tint = 0.85 + h * 0.3;
			col = glass_color * tint;
			rough = 0.12;
			metal = 0.4;
			if (h < lit_chance) {
				emit = lit_color * (0.15 + night * 2.2) * (0.6 + fract(h * 91.0) * 0.6);
			}
		} else {
			float band = step(0.93, f.y);
			col = mix(col, col * 0.78, band);
			// subtle grime towards the ground
			col *= mix(0.82, 1.0, clamp(wpos.y / 25.0, 0.0, 1.0));
		}
	} else {
		col = wall_color * 0.55;
		rough = 0.95;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
