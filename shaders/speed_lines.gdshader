shader_type canvas_item;
// Radial speed lines around the edge of the screen at high speed.

uniform float intensity = 0.0;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - 0.5;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	uv.x *= aspect;
	float r = length(uv);
	float a = (atan(uv.y, uv.x) / 6.28318 + 0.5) * 110.0;
	float id = floor(a);
	float d = abs(fract(a) - 0.5);
	float m = 1.0 - smoothstep(0.04, 0.12, d);
	float on = step(0.6, hash(id + floor(TIME * 14.0) * 17.3));
	float fall = smoothstep(0.32, 0.75, r);
	COLOR = vec4(line_color.rgb, m * on * fall * intensity * 0.45);
}
