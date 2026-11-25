shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
uniform vec4 col = vec4(0.16, 0.01, 0.008, 1.0);
void fragment() {
	ALBEDO = col.rgb;
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
}
