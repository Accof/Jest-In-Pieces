shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always;
// Standing water after the rain: opaque, muddy brown-grey, mostly calm,
// a slow shiver of wind across it, soft where it meets the mud.
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform vec3 colour : source_color = vec3(0.15, 0.135, 0.12);   // dark, muddy: it shows the sky by reflection, not by colour
uniform vec3 deep : source_color = vec3(0.075, 0.07, 0.065);
uniform float wind = 0.012;
instance uniform float round = 0.0;       // 1: a disc (shell-hole water), fading at its edge

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
	ROUGHNESS = 0.16;      // the sky in it, but no hard white sun spot
	SPECULAR = 0.32;
	ALPHA = smoothstep(0.0, 0.05, depth) * 0.97;
	if (round > 0.5) {
		float r = length(UV - 0.5) * 2.0;
		ALPHA *= 1.0 - smoothstep(0.75, 1.0, r);
	}
}

// Direct light by hand: the sun is behind cloud, so the water takes a soft
// sheen from it, never a hard white spot (the stock GGX peak on a smooth
// surface blew out to a disc). The sky reflection itself is untouched.
void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR / PI;
	vec3 h = normalize(VIEW + LIGHT);
	float sheen = pow(clamp(dot(NORMAL, h), 0.0, 1.0), 40.0) * 0.05;
	SPECULAR_LIGHT += sheen * ATTENUATION * LIGHT_COLOR / PI;
}

