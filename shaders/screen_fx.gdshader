shader_type canvas_item;
// Full-screen effects: thermal vision, damage flash, low-health pulse and
// the slow-motion "focus" tint.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float thermal = 0.0;
uniform float damage = 0.0;
uniform float low_health = 0.0;
uniform float focus = 0.0;
uniform float night = 0.0;   // night vision
uniform float sense = 0.0;   // predator sense
uniform float wheel = 0.0;   // forms wheel open: darken and blur the world

vec3 heat(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 c1 = vec3(0.02, 0.0, 0.18);
	vec3 c2 = vec3(0.35, 0.0, 0.55);
	vec3 c3 = vec3(0.95, 0.25, 0.05);
	vec3 c4 = vec3(1.0, 0.9, 0.3);
	vec3 c5 = vec3(1.0, 1.0, 1.0);
	if (t < 0.25) return mix(c1, c2, t / 0.25);
	if (t < 0.5) return mix(c2, c3, (t - 0.25) / 0.25);
	if (t < 0.8) return mix(c3, c4, (t - 0.5) / 0.3);
	return mix(c4, c5, (t - 0.8) / 0.2);
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	vec2 uv = SCREEN_UV - 0.5;
	float vig = smoothstep(0.35, 0.85, length(uv));
	if (thermal > 0.0) {
		float lum = dot(col, vec3(0.3, 0.55, 0.15));
		float t = pow(lum, 0.8) * 0.45;
		// very saturated warm-tinted pixels (people glow in thermal) read as hot
		float hot = clamp((col.r - max(col.g, col.b)) * 2.5, 0.0, 1.0);
		t = max(t, hot);
		vec3 th = heat(t);
		th *= 1.0 - vig * 0.5;
		col = mix(col, th, thermal);
	}
	if (focus > 0.0) {
		float g = dot(col, vec3(0.33));
		col = mix(col, vec3(g * 0.9, g * 1.0, g * 1.15), focus * 0.55);
		col *= 1.0 - vig * focus * 0.4;
	}
	if (night > 0.0) {
		float lum = dot(col, vec3(0.3, 0.59, 0.11));
		float amp = 1.0 - exp(-lum * 9.0);
		float grain = fract(sin(dot(SCREEN_UV * 731.0 + TIME * 13.0, vec2(12.9898, 78.233))) * 43758.5453);
		float scan = 0.94 + 0.06 * sin(SCREEN_UV.y * 900.0);
		vec3 nv = vec3(0.25, 1.0, 0.35) * (amp * 0.95 + grain * 0.08) * scan;
		nv *= 1.0 - vig * 0.75;
		col = mix(col, nv, night);
	}
	if (sense > 0.0) {
		float g = dot(col, vec3(0.33));
		vec3 dim = mix(vec3(g), col, 0.35) * vec3(0.85, 0.82, 0.95);
		col = mix(col, dim, sense * 0.7);
		col *= 1.0 - vig * sense * (0.35 + 0.08 * sin(TIME * 2.5));
	}
	if (wheel > 0.0) {
		vec3 blur = textureLod(screen_tex, SCREEN_UV, 3.0).rgb;
		col = mix(col, blur * 0.45, 0.8);
	}
	float red = damage * 0.6 + low_health * (0.25 + 0.15 * sin(TIME * 6.0));
	col = mix(col, vec3(0.6, 0.0, 0.0), clamp(red * vig * 1.5, 0.0, 0.8));
	COLOR = vec4(col, 1.0);
}
