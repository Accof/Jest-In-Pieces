// A run of blood down a wall (the blood overhaul's Phase D, 25 Nov 2026).
//
// A quad hung below a heavy wall mark, a few millimetres off the surface. The
// mask (art/blood/splat2/drip_mask.png) holds eight runs: R is when each
// pixel of a run is reached (0 at the top, 1 at its bead), G its coverage,
// B the resting bead. `progress` 0..1 reveals the runs from the top down; a
// glistening head rides the front of each run while it moves, and the bead
// sits where it stopped. `tint` dries the colour over the minutes after.
shader_type spatial;
// Opaque pass with an alpha cut-off, not blend_mix: a transparent quad gets no GI
// (SDFGI / SSIL bounce) while the wall and its decal do, so the runs rendered
// near-black beside the mark under the same lamp.
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D mask : filter_linear_mipmap, repeat_enable;   // data, not colour
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 1.0);
// (25 Nov) These match the marks AS THEY RENDER: Godot's decal atlas shows a
// decal's albedo without the sRGB decode, so the library's linear palette
// (thin 0.16 / deep 0.04) displays as its sRGB encoding (0.44 / 0.22). Measured
// in scenes/exp_runlight.tscn: the decal's core (50,13,5) sits between flat
// quads at these values; a quad at the linear deep colour was (9,3,1) - the
// "drips far darker than the splat" he saw. Plain vec4, not source_color.
uniform vec4 deep = vec4(0.27, 0.050, 0.055, 1.0);
uniform vec4 thin = vec4(0.44, 0.100, 0.086, 1.0);
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
	// the quad's top sits inside the mass: nothing starts on a line
	a *= smoothstep(0.0, 0.1, UV.y);
	// the run itself thins toward its end: the lower, the thinner
	float thick = clamp(on * (1.0 - 0.5 * reach) + head + rest, 0.0, 1.0);
	// mostly the red of a fresh run; only the heads and beads go deep
	// the same ramp as the library's finish(): thick^0.45 toward deep
	vec3 col = mix(thin.rgb, deep.rgb, pow(thick, 0.45)) * tint.rgb;
	ALBEDO = col;
	ALPHA = a * tint.a;
	ALPHA_SCISSOR_THRESHOLD = 0.3;
	METALLIC = 0.0;
	// (25 Nov, "too shiny compared to the splat") the marks carry no gloss map
	// and take the wall's roughness, so a run must sit close to matt too: a
	// little sheen on the moving head only, none once it has dried
	ROUGHNESS = mix(0.92, 0.62, wet * clamp(head * 2.0 + thick * 0.4, 0.0, 1.0));
	SPECULAR = 0.2;
}
