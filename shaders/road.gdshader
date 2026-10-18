shader_type spatial;
// Asphalt streets with lane markings, crosswalks, cracks and patches, laid
// out on the same grid the city uses for its blocks. Gets glossy and dark
// with puddles when it rains.

uniform float period = 60.0;
uniform float street = 16.0;
uniform vec2 origin = vec2(0.0);
uniform float wetness = 0.0;
uniform sampler2D asphalt_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz - origin;
	vec2 m = mod(p, period);
	vec2 c = abs(m - street * 0.5);
	bool in_x_street = m.x < street; // street running along Z
	bool in_z_street = m.y < street; // street running along X
	// asphalt: a photo texture (CC0, assets/CREDITS.md) with large blotches on top
	vec2 auv = wpos.xz / 3.5;
	float blotch = fbm(wpos.xz * 0.08);
	vec3 col = texture(asphalt_col, auv).rgb * 0.42 * (0.85 + blotch * 0.3);
	vec3 nmap = texture(asphalt_nrm, auv).rgb;
	float base_rough = texture(asphalt_rough, auv).r;
	// patched squares
	vec2 patch_cell = floor(wpos.xz / 7.0);
	if (hash(patch_cell) > 0.93) {
		vec2 pf = fract(wpos.xz / 7.0);
		if (pf.x > 0.15 && pf.x < 0.8 && pf.y > 0.2 && pf.y < 0.7) {
			col *= 0.75;
		}
	}
	// thin cracks
	float crack = smoothstep(0.03, 0.0, abs(fbm(wpos.xz * 0.35) - 0.5));
	col *= 1.0 - crack * 0.35;
	float line = 0.0;
	vec3 line_col = vec3(0.85, 0.82, 0.72);
	if (in_x_street && !in_z_street) {
		// double yellow center line
		float yl = max(1.0 - step(0.08, abs(m.x - street * 0.5 - 0.18)), 1.0 - step(0.08, abs(m.x - street * 0.5 + 0.18)));
		if (yl > 0.5) { line = 1.0; line_col = vec3(0.85, 0.65, 0.12); }
		// dashed lane dividers
		line = max(line, (1.0 - step(0.07, abs(c.x - street * 0.25))) * step(0.5, fract(p.y / 6.0)));
		line = max(line, (1.0 - step(0.08, abs(c.x - street * 0.5 + 0.6))) * 0.7);
	}
	if (in_z_street && !in_x_street) {
		float yl = max(1.0 - step(0.08, abs(m.y - street * 0.5 - 0.18)), 1.0 - step(0.08, abs(m.y - street * 0.5 + 0.18)));
		if (yl > 0.5) { line = 1.0; line_col = vec3(0.85, 0.65, 0.12); }
		line = max(line, (1.0 - step(0.07, abs(c.y - street * 0.25))) * step(0.5, fract(p.x / 6.0)));
		line = max(line, (1.0 - step(0.08, abs(c.y - street * 0.5 + 0.6))) * 0.7);
	}
	if (in_x_street && in_z_street) {
		col *= 0.92;
	} else if (in_x_street) {
		float near_cross = step(abs(m.y - street - 2.0), 1.6) + step(abs(m.y - (period - 2.0)), 1.6);
		line = max(line, near_cross * step(0.5, fract(m.x / 1.2)) * 0.9);
		if (near_cross > 0.5) { line_col = vec3(0.85, 0.82, 0.72); }
	} else if (in_z_street) {
		float near_cross = step(abs(m.x - street - 2.0), 1.6) + step(abs(m.x - (period - 2.0)), 1.6);
		line = max(line, near_cross * step(0.5, fract(m.y / 1.2)) * 0.9);
		if (near_cross > 0.5) { line_col = vec3(0.85, 0.82, 0.72); }
	}
	// worn paint
	line *= 0.75 + 0.25 * noise(wpos.xz * 3.0);
	col = mix(col, line_col, clamp(line, 0.0, 1.0));
	// rain: darker, glossy, with puddles in the low spots
	float puddle = smoothstep(0.55, 0.62, fbm(wpos.xz * 0.12 + 3.7)) * wetness;
	float wet = clamp(wetness * 0.8 + puddle, 0.0, 1.0);
	col *= mix(1.0, 0.55, wet);
	ALBEDO = col;
	// paint lines and puddles are smooth; bare asphalt keeps its grain
	NORMAL_MAP = mix(nmap, vec3(0.5, 0.5, 1.0), clamp(max(line, wet), 0.0, 1.0));
	ROUGHNESS = mix(base_rough, 0.08, wet);
	SPECULAR = mix(0.4, 0.7, wet);
}
