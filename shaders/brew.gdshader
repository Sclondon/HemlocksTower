shader_type spatial;
render_mode unshaded;
// A cauldron's stew: a slow swirl of its colour, with chunky pixel bubbles
// that swell and pop all over the surface. Put on a flat disc (UV 0..1).

uniform vec4 brew : source_color = vec4(0.3, 0.85, 0.35, 1.0);
uniform vec4 deep : source_color = vec4(0.08, 0.3, 0.12, 1.0);
uniform float pixels = 22.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = floor(UV * pixels) / pixels;
	vec2 c = uv - 0.5;
	float r = length(c);
	float swirl = sin(atan(c.y, c.x) * 3.0 + r * 18.0 - TIME * 1.3) * 0.5 + 0.5;
	vec3 col = mix(deep.rgb, brew.rgb, 0.45 + 0.35 * swirl);
	// Bubbles: each cell of a coarse grid blows one up now and then
	vec2 cell = floor(UV * 6.0);
	float h = hash(cell);
	float life = fract(TIME * (0.35 + h * 0.4) + h * 7.0);
	vec2 centre = (cell + 0.25 + 0.5 * vec2(hash(cell + 3.1), hash(cell + 7.7))) / 6.0;
	float size = life * 0.07;
	float d = length(uv - centre);
	if (life < 0.85 && d < size && d > size - 0.03) {
		col = mix(brew.rgb, vec3(1.0), 0.55);        // the bubble's rim
	} else if (life < 0.85 && d < size) {
		col = brew.rgb * 1.2;
	}
	ALBEDO = col;
}
