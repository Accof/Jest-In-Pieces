// A run of blood down a wall (the blood overhaul's Phase D, 25 Nov 2026).
//
// A quad hung below a heavy wall mark, a few millimetres off the surface. The
// mask (art/blood/splat2/drip_mask.png) holds eight runs: R is when each
// pixel of a run is reached (0 at the top, 1 at its bead), G its coverage,
// B the resting bead. `progress` 0..1 reveals the runs from the top down; a
// glistening head rides the front of each run while it moves, and the bead
// sits where it stopped. `tint` dries the colour over the minutes after.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform sampler2D mask : filter_linear_mipmap, repeat_enable;   // data, not colour
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 deep : source_color = vec4(0.045, 0.003, 0.004, 1.0);
uniform vec4 thin : source_color = vec4(0.30, 0.016, 0.012, 1.0);
uniform float wet = 1.0;          // 1 fresh and glossy, 0 dried and matt

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec4 m = texture(mask, uv);
	float reach = m.r;
	float cov = m.g;
	float bead = m.b;
	// revealed where the run has got this far; the front edge is soft
	float on = cov * (1.0 - smoothstep(progress - 0.02, progress + 0.01, reach));
	// the head: a thicker, brighter drop riding the front
	float head = cov * (1.0 - smoothstep(0.0, 0.05, abs(reach - progress))) * step(progress, 0.995);
	// the bead where it came to rest, once it has
	float rest = bead * smoothstep(0.97, 1.0, progress);
	float a = clamp(on + head * 0.6 + rest, 0.0, 1.0);
	// the run itself thins toward its end: the lower, the thinner
	float thick = clamp(on * (1.0 - 0.5 * reach) + head + rest, 0.0, 1.0);
	// mostly the red of a fresh run; only the heads and beads go deep
	vec3 col = mix(thin.rgb, deep.rgb, pow(thick, 0.6) * 0.55) * tint.rgb;
	ALBEDO = col;
	ALPHA = a * tint.a;
	METALLIC = 0.0;
	ROUGHNESS = mix(0.85, 0.18, wet * clamp(head * 3.0 + thick, 0.0, 1.0));
	SPECULAR = 0.5;
}
