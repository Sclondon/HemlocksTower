shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// The meadow's low ground mist: drifts of stepped-alpha pixel cloud (noise
// in world space, as the cloud decks), each with a soft rim round its edge,
// and a bright line where the mist meets anything standing in it (the
// tower's foot, a gravestone, a trunk), like the foam round a rock in toon
// water: found by comparing the mist's depth with what's drawn behind it.

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 color : source_color = vec4(1.0);
uniform vec4 shade : source_color = vec4(0.7, 0.72, 0.85, 1.0);
uniform float coverage : hint_range(0.0, 1.0) = 0.36;
uniform float scale = 75.0;
uniform vec2 wind = vec2(0.006, 0.002);
uniform float fade_near = 45.0;
uniform float fade_far = 140.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float outline = 0.35;               // how wide the soft rim is (metres)
uniform vec4 edge_color : source_color = vec4(0.62, 0.68, 0.82, 0.6);
uniform float foam = 0.35;                  // how thick the line where it meets things is (metres)
uniform vec4 foam_color : source_color = vec4(0.92, 0.95, 1.0, 0.85);

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// How thick the mist is at a point (0 or less: none)
float density(vec2 at, vec2 cam) {
	vec2 uv = at / scale + wind * TIME;
	float n = texture(noise_tex, uv).r * 0.65 + texture(noise_tex, uv * 2.3 + 0.37).r * 0.35;
	float fade = 1.0 - smoothstep(fade_near, fade_far, length(at - cam));
	return (n - (1.0 - coverage)) * 3.0 * fade;
}

void fragment() {
	vec2 cam = CAMERA_POSITION_WORLD.xz;
	float v = density(world.xz, cam);
	if (v <= 0.0) discard;
	float a = v > 0.66 ? 0.8 : (v > 0.33 ? 0.55 : 0.28);
	vec3 col = v > 0.66 ? color.rgb : mix(shade.rgb, color.rgb, 0.45);
	float alpha = a * color.a;
	// The rim: eases in toward the drift's edge (where the mist runs out
	// within `outline` metres), and the very edge feathers away
	float o = min(min(density(world.xz + vec2(outline, 0.0), cam), density(world.xz - vec2(outline, 0.0), cam)),
		min(density(world.xz + vec2(0.0, outline), cam), density(world.xz - vec2(0.0, outline), cam)));
	float rim = 1.0 - smoothstep(-0.1, 0.3, o);
	col = mix(col, edge_color.rgb, rim);
	alpha = mix(alpha, edge_color.a, rim) * smoothstep(0.0, 0.2, v);
	// Where it meets something: how far behind the mist the scene is here
	// (Compatibility renderer: depth maps to NDC as depth * 2 - 1)
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	float gap = (-behind.z / behind.w) - (-VERTEX.z);
	float meet = 1.0 - smoothstep(0.0, foam, gap);
	col = mix(col, foam_color.rgb, meet);
	alpha = max(alpha, foam_color.a * meet);
	ALBEDO = col * tint.rgb;
	ALPHA = alpha;
}
