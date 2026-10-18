shader_type sky;
// Sky with a sun, drifting clouds and stars. Colors are driven by daynight.gd.

uniform vec3 top_color : source_color = vec3(0.3, 0.45, 0.65);
uniform vec3 horizon_color : source_color = vec3(0.8, 0.75, 0.7);
uniform vec3 ground_color : source_color = vec3(0.2, 0.19, 0.18);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.75);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float night = 0.0;
uniform float cloud_cover = 0.45;
uniform float cloud_dark = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col;
	if (h >= 0.0) {
		float t = pow(clamp(h, 0.0, 1.0), 0.45);
		col = mix(horizon_color, top_color, t);
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 4.0, 0.0, 1.0));
	}
	// sun (or moon at night) glow
	vec3 sd = LIGHT0_DIRECTION;
	float sdot = max(dot(dir, sd), 0.0);
	col += sun_color * pow(sdot, 600.0) * 18.0 * LIGHT0_ENERGY;
	col += sun_color * pow(sdot, 8.0) * 0.25 * LIGHT0_ENERGY;
	if (h > 0.0 && !AT_CUBEMAP_PASS) {
		// stars
		vec2 sp = dir.xz / (dir.y + 0.15) * 90.0;
		float star = step(0.996, hash(floor(sp))) * smoothstep(0.5, 0.0, length(fract(sp) - 0.5));
		col += vec3(star) * night * smoothstep(0.0, 0.25, h) * 1.5;
	}
	if (h > 0.0) {
		// clouds projected onto a flat layer
		vec2 uv = dir.xz / (dir.y + 0.08) * 0.9 + vec2(TIME * 0.004, TIME * 0.002);
		float c = fbm(uv * 1.3);
		c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.35, c);
		c *= smoothstep(0.0, 0.18, h);
		vec3 cc = mix(cloud_color, cloud_color * 0.35, cloud_dark);
		cc += sun_color * pow(sdot, 4.0) * 0.4;
		col = mix(col, cc, c * 0.85);
	}
	COLOR = col;
}
