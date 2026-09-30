shader_type spatial;
render_mode unshaded, cull_back;

// Puffy clouds from spheres. Noise sampled in world space scrolls across
// them, so they boil and drift; where it's thin near the silhouette the
// sphere is cut away, leaving ragged, wispy edges instead of a ball. Shading
// is stepped into three tones (lit tops, shadowed bellies) to match the
// pixel-art cloud decks. Cut-out, not blended, so overlapping puffs sort fine.

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 color : source_color = vec4(1.0);
uniform vec4 shade : source_color = vec4(0.7, 0.72, 0.85, 1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float scale = 22.0;
uniform vec3 drift = vec3(0.02, 0.012, 0.015);
uniform float fade_near = 220.0;
uniform float fade_far = 560.0;

varying vec3 world;
varying vec3 wnormal;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = world / scale + drift * TIME;
	float n = texture(noise_tex, p.xz + p.y * 0.37).r * 0.6 + texture(noise_tex, p.zy * 1.7 + 0.5).r * 0.4;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - world);
	float facing = clamp(dot(wnormal, to_cam), 0.0, 1.0);    // 1 mid-puff, 0 at the silhouette
	float fade = 1.0 - smoothstep(fade_near, fade_far, length(world - CAMERA_POSITION_WORLD));
	if (facing * 1.4 + n * 0.9 < 0.75 || n > fade + 0.25) {
		discard;
	}
	float light = wnormal.y * 0.5 + 0.5 + (n - 0.5) * 0.7;
	vec3 c = light > 0.62 ? color.rgb : (light > 0.36 ? mix(shade.rgb, color.rgb, 0.5) : shade.rgb);
	ALBEDO = c * tint.rgb;
}
