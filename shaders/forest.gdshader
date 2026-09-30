shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;
// Pixel-art trees drawn as a MultiMesh: each instance is a quad standing on
// the ground that turns round its upright axis to face the camera. The
// instance's scale sets its size; its colour darkens / tints it.
// Unshaded, so the art keeps its own colours (lit from the front it came out
// flat and pale); the game dims it at night instead. The scene's fog applies
// as it does to everything else.

uniform sampler2D tex : source_color, filter_nearest;
uniform float light = 1.0;           // 1 by day, lower at night

varying vec3 tint;
varying float dist;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - origin;
	to_cam.y = 0.0;
	to_cam = normalize(to_cam);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 world = origin + right * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	tint = COLOR.rgb;
	dist = length(world - cam);
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	vec3 col = c.rgb * tint * light;
	ALBEDO = col;
}
