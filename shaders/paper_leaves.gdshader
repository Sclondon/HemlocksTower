shader_type spatial;
render_mode unshaded, cull_disabled;
// The paper trees' leaf clumps: upright cards of the pixel-art leaf sprite
// set round each clump like the sides of a box. Unshaded, with a stepped
// light from each card's facing (tops lit, undersides in shadow), dimmed at night; the
// scene's fog applies as it does to everything else.

uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform float light = 1.0;
uniform vec3 sun = vec3(0.4, 0.8, 0.45);

varying vec3 wnormal;
varying float dist;
varying vec3 tint;

void vertex() {
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	dist = length((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
	tint = COLOR.rgb;
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	// Cards are two-sided: light whichever face we're looking at
	vec3 n = FRONT_FACING ? wnormal : -wnormal;
	float lit = 0.55 + 0.35 * max(dot(n, normalize(sun)), 0.0) + 0.15 * n.y;
	lit = lit > 0.85 ? 1.0 : (lit > 0.68 ? 0.84 : 0.66);      // stepped, like the pixel art
	ALBEDO = c.rgb * tint * lit * light;
}
