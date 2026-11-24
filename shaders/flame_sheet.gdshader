// A flame: a billboard playing the 8 x 8 looping sprite sheet
// (art/level/fx_flame_sheet.png, 64 frames of a burning tongue), additive,
// unlit, with a flicker. For GPUParticles3D (each particle on its own phase,
// fading with its colour ramp) and for the lanterns' MultiMesh (one quad each,
// INSTANCE_CUSTOM.x the phase, .y the brightness).
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform float frame_rate = 24.0;      // frames a second through the 64
uniform float brightness = 1.0;
uniform float flicker = 0.25;         // how much the whole flame breathes
uniform vec3 tint : source_color = vec3(1.0, 0.92, 0.8);

varying float v_frame;
varying float v_bright;
varying vec4 v_col;

void vertex() {
	// a billboard that keeps the flame upright (world up stays up)
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
	vec3 right = normalize(cross(up, to_cam));
	vec3 fwd = cross(right, up);
	mat3 bb = mat3(right, up, fwd);
	float phase = INSTANCE_CUSTOM.x;
	float t = TIME * frame_rate / 64.0 + phase;
	v_frame = fract(t) * 64.0;
	float br = INSTANCE_CUSTOM.y > 0.0 ? INSTANCE_CUSTOM.y : 1.0;
	float f = sin(TIME * 9.3 + phase * 40.0) * 0.5 + sin(TIME * 23.7 + phase * 13.0) * 0.3 + sin(TIME * 3.1 + phase * 7.0) * 0.2;
	v_bright = br * (1.0 + flicker * f);
	v_col = COLOR;
	// the instance's scale (a particle's, a lantern's) kept; its rotation not
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	vec3 world = MODEL_MATRIX[3].xyz + bb * (VERTEX * sc);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(to_cam, 0.0)).xyz);
}

void fragment() {
	float fr = floor(v_frame);
	vec2 cell = vec2(mod(fr, 8.0), floor(fr / 8.0));
	vec2 uv = (UV + cell) / 8.0;
	vec4 s = texture(sheet, uv);
	// blend toward the next frame so the loop is smooth at 24 fps
	float fr2 = mod(fr + 1.0, 64.0);
	vec2 cell2 = vec2(mod(fr2, 8.0), floor(fr2 / 8.0));
	vec4 s2 = texture(sheet, (UV + cell2) / 8.0);
	s = mix(s, s2, fract(v_frame));
	vec3 col = s.rgb * tint * brightness * v_bright * v_col.rgb;
	ALBEDO = col * s.a * v_col.a;
	ALPHA = 1.0;
}
