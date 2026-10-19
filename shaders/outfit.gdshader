shader_type spatial;
// Clothing from the Quaternius outfit packs, recoloured: the texture's green cloth and brown leather
// each get their own tint (keeping the texture's detail), or a skin tint for bare arms and hands.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform vec4 cloth_tint : source_color = vec4(0.16, 0.03, 0.035, 1.0);
uniform vec4 leather_tint : source_color = vec4(0.13, 0.12, 0.13, 1.0);
uniform float recolor = 1.0;        // 0 keeps the texture's own colours
uniform bool roughness_only = false; // the skin set has a plain roughness map instead of ORM
uniform vec4 glow_color : source_color = vec4(1.0, 0.16, 0.1, 1.0);
uniform float glow = 0.0;            // faint pulsing veins in the cloth

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float cloth = smoothstep(0.0, 0.06, c.g - c.r);
	vec3 tint = mix(leather_tint.rgb, cloth_tint.rgb, cloth);
	// stretch the contrast a little so seams and folds still read on dark colours
	vec3 recoloured = tint * (0.35 + 1.9 * l);
	ALBEDO = mix(c, recoloured, recolor);
	vec3 orm = texture(orm_tex, UV).rgb;
	if (roughness_only) {
		ROUGHNESS = orm.r;
	} else {
		AO = orm.r;
		ROUGHNESS = orm.g;
		METALLIC = orm.b;
	}
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	if (glow > 0.0) {
		// a few thin veins in the dark parts of the cloth, slowly pulsing
		float f = fract(UV.x * 9.0 + sin(UV.y * 23.0) * 0.35 + sin(UV.x * 31.0) * 0.1);
		float v = smoothstep(0.47, 0.5, f) * smoothstep(0.53, 0.5, f) * step(l, 0.35);
		EMISSION = glow_color.rgb * v * glow * cloth * (0.55 + 0.45 * sin(TIME * 1.7));
	}
}
