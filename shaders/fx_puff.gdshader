shader_type spatial;
// Camera-facing puff of fire or smoke for explosions. Fades out where it
// meets walls and floors so it never shows a hard edge.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float emissive = 0.0;
uniform sampler2D depth_tex : hint_depth_texture;
instance uniform float fade = 1.0;

void vertex() {
	// billboard, keeping the per-instance roll and scale
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	float roll = atan(MODEL_MATRIX[0].y, MODEL_MATRIX[0].x);
	vec2 v = VERTEX.xy * scale.xy;
	v = mat2(vec2(cos(roll), sin(roll)), vec2(-sin(roll), cos(roll))) * v;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX = vec3(v, 0.0);
}

void fragment() {
	vec4 c = texture(tex, UV);
	float scene = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene, 1.0);
	float scene_z = -world.z / world.w;
	float soft = clamp((scene_z - (-VERTEX.z)) / 0.6, 0.0, 1.0);
	ALBEDO = c.rgb * (1.0 + emissive * fade);
	ALPHA = c.a * fade * soft;
}
