shader_type spatial;
render_mode unshaded, fog_disabled;
// The mountains on the horizon. The engine's fog would swallow them whole at
// that distance, so they do their own: a haze toward the fog colour (fed in
// by the game, like the forest's), stronger for the far ring, and much
// stronger in thick weather, when they all but disappear. A fixed light gives
// their faces a lit side and a shadow side; night dims them.

uniform float light = 1.0;
uniform vec3 haze : source_color = vec3(0.55, 0.55, 0.65);
uniform float fade_far = 320.0;      // the forest's fade distance: short in fog, long when clear
uniform vec3 sun = vec3(0.5, 0.6, 0.6);

varying vec3 col;
varying vec3 wnormal;
varying float dist;

void vertex() {
	col = COLOR.rgb;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	dist = length((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz.xz - CAMERA_POSITION_WORLD.xz);
}

void fragment() {
	float lit = 0.6 + 0.4 * max(dot(wnormal, normalize(sun)), 0.0);
	float thick = 1.0 - clamp((fade_far - 200.0) / 220.0, 0.0, 1.0);    // 0 clear .. 1 foggy
	float far = smoothstep(500.0, 1000.0, dist);
	float amount = clamp(0.3 + 0.2 * far + 0.5 * thick, 0.0, 0.95);
	ALBEDO = mix(col * lit * light, haze, amount);
}
