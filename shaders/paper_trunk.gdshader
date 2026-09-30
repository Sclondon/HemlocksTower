shader_type spatial;
render_mode unshaded;
// The paper trees' trunks: real 3D, with chunky pixel bark. Unshaded like the
// rest of the forest, with a simple fixed light so the round trunk still has
// a lit side and a shadow side. The scene's fog applies as it does to everything else.

uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform float light = 1.0;
uniform vec3 sun = vec3(0.5, 0.35, 0.8);

varying vec3 wnormal;
varying float dist;

void vertex() {
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	dist = length((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
}

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float lit = 0.62 + 0.38 * max(dot(wnormal, normalize(sun)), 0.0);
	lit = lit > 0.85 ? 1.0 : (lit > 0.7 ? 0.82 : 0.66);     // stepped, like the pixel art
	ALBEDO = c * lit * light;
}
