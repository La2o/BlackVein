shader_type spatial;
// Pulsing web of infected veins spreading over the ground around a hive.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float pulse = 0.0;
uniform vec3 vein_color : source_color = vec3(0.55, 0.03, 0.03);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	// radial veins with a wobble, plus a noisy web
	float veins = abs(sin(ang * 9.0 + noise(p * 3.0) * 4.0));
	veins = 1.0 - smoothstep(0.0, 0.12, veins);
	float web = 1.0 - smoothstep(0.0, 0.08, abs(noise(p * 6.0) - 0.5));
	float m = max(veins, web * 0.7);
	float fade = 1.0 - smoothstep(0.55, 1.0, r);
	float glow = 0.6 + 0.4 * sin(pulse * 3.0 - r * 10.0);
	ALBEDO = vein_color * (0.6 + glow * 0.8);
	ALPHA = m * fade * 0.8 + fade * 0.12;
}
