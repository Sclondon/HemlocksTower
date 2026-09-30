shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// A flat cloud deck. Noise is sampled in world space and the alpha is
// stepped into three levels so it reads as pixel art, not a smooth fog.

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 color : source_color = vec4(1.0);
uniform vec4 shade : source_color = vec4(0.7, 0.72, 0.85, 1.0);
uniform float coverage : hint_range(0.0, 1.0) = 0.55;
uniform float scale = 110.0;
uniform vec2 wind = vec2(0.006, 0.002);
uniform float fade_near = 260.0;           // fade by distance from the camera, so
uniform float fade_far = 620.0;            // there's never a visible edge
uniform float offset = 0.0;
uniform vec4 tint : source_color = vec4(1.0);

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// How thick the cloud is at a point on the plane (0 or less: clear sky)
float density(vec2 at, vec2 cam) {
	vec2 uv = at / scale + wind * TIME + vec2(offset);
	float n = texture(noise_tex, uv).r * 0.65 + texture(noise_tex, uv * 2.3 + 0.37).r * 0.35;
	float edge = 1.0 - smoothstep(fade_near, fade_far, length(at - cam));
	return (n - (1.0 - coverage)) * 3.0 * edge;
}

void fragment() {
	float v = density(world.xz, CAMERA_POSITION_WORLD.xz);
	if (v <= 0.0) discard;
	float a = v > 0.66 ? 0.8 : (v > 0.33 ? 0.55 : 0.28);
	ALBEDO = (v > 0.66 ? color.rgb : mix(shade.rgb, color.rgb, 0.45)) * tint.rgb;
	ALPHA = a * color.a;
}
