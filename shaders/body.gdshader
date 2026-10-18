shader_type spatial;
// Colors a person. Meshes from scripts/body_kit.gd carry a material slot in COLOR.r
// and ambient occlusion in COLOR.g.

uniform vec3 c_skin : source_color = vec3(0.75, 0.58, 0.45);
uniform vec3 c_top : source_color = vec3(0.4, 0.4, 0.45);
uniform vec3 c_bottom : source_color = vec3(0.2, 0.2, 0.25);
uniform vec3 c_shoes : source_color = vec3(0.08, 0.07, 0.07);
uniform vec3 c_hair : source_color = vec3(0.12, 0.08, 0.05);
uniform vec3 c_gear : source_color = vec3(0.25, 0.3, 0.2);
uniform vec3 c_accent : source_color = vec3(0.3, 0.3, 0.3);
uniform vec3 c_glow : source_color = vec3(1.0, 0.15, 0.1);
uniform float camo = 0.0;      // 1 = military camouflage on clothing
uniform float infected = 0.0;  // 1 = blotchy, sickly skin

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	int s = int(COLOR.r * 255.0 + 0.5);
	float ao = COLOR.g;
	vec3 col = c_top;
	float rough = 0.85;
	float metal = 0.0;
	float spec = 0.35;
	vec3 emit = vec3(0.0);
	bool cloth = false;
	if (s == 0) {          // skin
		col = c_skin;
		rough = 0.55;
		spec = 0.4;
		if (infected > 0.5) {
			float b = noise(lpos * 22.0);
			col = mix(col, vec3(0.35, 0.08, 0.07), smoothstep(0.62, 0.8, b));
		}
	} else if (s == 1) { col = c_top; cloth = true; }
	else if (s == 2) { col = c_bottom; cloth = true; }
	else if (s == 3) { col = c_shoes; rough = 0.45; spec = 0.5; }
	else if (s == 4) { col = c_hair; rough = 0.6; spec = 0.45; }
	else if (s == 5) { col = c_gear; rough = 0.55; cloth = camo > 0.5; }
	else if (s == 6) { col = vec3(0.035, 0.032, 0.03); rough = 0.4; }
	else if (s == 7) { col = vec3(0.12, 0.12, 0.13); metal = 0.75; rough = 0.35; }
	else if (s == 8) { col = vec3(0.9, 0.88, 0.85); rough = 0.25; spec = 0.6; }
	else if (s == 9) { col = c_glow * 0.3; emit = c_glow * 3.2; rough = 0.3; }
	else if (s == 10) { col = c_accent; cloth = true; }
	else if (s == 11) { col = c_skin * vec3(0.8, 0.55, 0.55); rough = 0.4; }
	else if (s == 12) { col = vec3(0.32, 0.03, 0.04); rough = 0.25; spec = 0.6; emit = c_glow * 0.25; }
	if (cloth) {
		// fine weave + soft folds so cloth isn't flat
		col *= 0.9 + 0.1 * noise(lpos * 140.0);
		col *= 0.92 + 0.12 * noise(lpos * 9.0);
		if (camo > 0.5) {
			float n = noise(lpos * 9.0 + 3.1) * 0.65 + noise(lpos * 21.0) * 0.35;
			col *= n > 0.62 ? 0.55 : (n > 0.45 ? 0.82 : 1.12);
		}
	}
	ALBEDO = col * mix(0.42, 1.0, ao);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
	if (s == 0) {
		// a touch of warm light bleeding through skin
		BACKLIGHT = c_skin * vec3(0.25, 0.08, 0.05);
	}
}
