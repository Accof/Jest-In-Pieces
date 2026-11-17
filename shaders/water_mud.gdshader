shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always;
// Standing water after the rain: opaque, muddy brown-grey, mostly calm,
// a slow shiver of wind across it, soft where it meets the mud.
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform vec3 colour : source_color = vec3(0.24, 0.21, 0.18);
uniform vec3 deep : source_color = vec3(0.16, 0.14, 0.12);
uniform float wind = 0.012;

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 t = vec2(TIME * wind, TIME * wind * 0.6);
	float a = texture(noise_tex, wp.xz * 0.35 + t).b;
	float b = texture(noise_tex, wp.xz * 0.9 - t * 1.7).b;
	vec3 n = normalize(vec3((a - 0.5) * 0.06 + (b - 0.5) * 0.03, 1.0, (b - 0.5) * 0.06 - (a - 0.5) * 0.03));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// how deep the water is here: the mud under it from the depth buffer
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float depth = clamp((VERTEX.z - vpos.z), 0.0, 1.0);
	ALBEDO = mix(colour, deep, smoothstep(0.02, 0.25, depth));
	ROUGHNESS = 0.12;
	SPECULAR = 0.35;
	ALPHA = smoothstep(0.0, 0.05, depth) * 0.97;
}
