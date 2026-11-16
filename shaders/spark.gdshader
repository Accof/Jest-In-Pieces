shader_type spatial;
// A spark: a short, white-hot streak drawn along the way it is flying (the
// particle's Y axis is lined up with its velocity) and turned round that line
// to face the camera, like a hot fleck of metal seen with motion blur.
// Brighter than white so the glow picks it up; colour comes from the particle
// (white-yellow when fresh, orange, then dull red as it cools).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float energy = 9.0;
// width of the streak as a share of its length
uniform float thinness = 0.11;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 along = MODEL_MATRIX[1].xyz;
	float len = length(along);
	along = len > 0.0 ? along / len : vec3(0.0, 1.0, 0.0);
	float wide = len * thinness;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - centre);
	vec3 side = cross(along, to_cam);
	side = length(side) > 0.0001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	vec3 world = centre + side * VERTEX.x * wide + along * VERTEX.y * len;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	// hot core down the middle, fading to the sides and toward the tail
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float tail = smoothstep(0.0, 0.6, 1.0 - UV.y);
	ALBEDO = COLOR.rgb * energy;
	ALPHA = COLOR.a * across * across * (0.35 + 0.65 * tail);
}
