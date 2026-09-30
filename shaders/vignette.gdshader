shader_type canvas_item;
// Darkens the screen's edges (and a little everywhere, by `base`) so menu
// text reads over the live tower behind it.

uniform vec4 tint : source_color = vec4(0.03, 0.01, 0.06, 1.0);
uniform float base = 0.15;
uniform float strength = 0.8;

void fragment() {
	vec2 uv = UV - 0.5;
	float edge = smoothstep(0.3, 0.8, length(uv * vec2(1.1, 1.0)));
	// A soft pool of shade behind the menu column
	float column = (1.0 - smoothstep(0.0, 0.45, abs(uv.x))) * 0.25;
	COLOR = vec4(tint.rgb, clamp(base + edge * strength + column, 0.0, 1.0));
}
