shader_type spatial;
// A soap bubble: almost clear face-on, a thin film of shifting colour toward
// the rim, a sharp highlight. `fade` takes it out (or pops it).
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx;

instance uniform float fade = 1.0;
instance uniform float swirl = 0.0;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = 1.0 - facing;
	// thin-film colour: the film's thickness changes over the bubble and in time
	float film = rim * 1.7 + swirl + TIME * 0.35 + 0.15 * sin(UV.y * 9.0 + TIME * 1.3);
	vec3 hue = 0.55 + 0.45 * cos(6.2831 * (film + vec3(0.0, 0.33, 0.67)));
	ALBEDO = mix(vec3(0.85), hue, 0.75);
	ROUGHNESS = 0.03;
	SPECULAR = 1.0;
	METALLIC = 0.0;
	EMISSION = hue * 0.05 * pow(rim, 2.0);
	ALPHA = clamp((0.05 + 0.6 * pow(rim, 2.2)) * fade, 0.0, 1.0);
}
