shader_type spatial;
// Test-only: paints each pixel with its distance from the camera, so a test
// can compare what is drawn with what the physics world says is there.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float d = min(length(v.xyz / v.w), 63.0);
	ALBEDO = to_linear(vec3(floor(d * 4.0) / 255.0, fract(d * 4.0), 0.0));
}
