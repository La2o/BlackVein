shader_type spatial;
// Asphalt streets with dashed center lines and crosswalks, laid out on the
// same grid the city uses for its blocks.

uniform float period = 60.0;
uniform float street = 16.0;
uniform vec2 origin = vec2(0.0);
uniform float infection = 0.0;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
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
	float noise = hash(floor(wpos.xz * 2.0)) * 0.03;
	vec3 col = vec3(0.085 + noise);
	float line = 0.0;
	if (in_x_street && !in_z_street) {
		line = (1.0 - step(0.12, c.x)) * step(0.5, fract(p.y / 5.0));
		// edge lines
		line = max(line, (1.0 - step(0.08, abs(c.x - street * 0.5 + 0.6))) * 0.6);
	}
	if (in_z_street && !in_x_street) {
		line = max(line, (1.0 - step(0.12, c.y)) * step(0.5, fract(p.x / 5.0)));
		line = max(line, (1.0 - step(0.08, abs(c.y - street * 0.5 + 0.6))) * 0.6);
	}
	// crosswalk stripes near intersections
	if (in_x_street && in_z_street) {
		col = vec3(0.075 + noise);
	} else if (in_x_street) {
		float d = min(m.y - street, period - m.y);
		if (d < 0.0) { d = 99.0; }
		float near_cross = step(abs(m.y - street - 2.0), 1.6) + step(abs(m.y - (period - 2.0)), 1.6);
		line = max(line, near_cross * step(0.5, fract(m.x / 1.2)) * 0.9);
	} else if (in_z_street) {
		float near_cross = step(abs(m.x - street - 2.0), 1.6) + step(abs(m.x - (period - 2.0)), 1.6);
		line = max(line, near_cross * step(0.5, fract(m.y / 1.2)) * 0.9);
	}
	col = mix(col, vec3(0.82, 0.78, 0.66), clamp(line, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.92;
}
