shader_type canvas_item;
// Full-screen effects: thermal vision, damage flash, low-health pulse and
// the slow-motion "focus" tint.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float thermal = 0.0;
uniform float damage = 0.0;
uniform float low_health = 0.0;
uniform float focus = 0.0;

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
	float red = damage * 0.6 + low_health * (0.25 + 0.15 * sin(TIME * 6.0));
	col = mix(col, vec3(0.6, 0.0, 0.0), clamp(red * vig * 1.5, 0.0, 0.8));
	COLOR = vec4(col, 1.0);
}
