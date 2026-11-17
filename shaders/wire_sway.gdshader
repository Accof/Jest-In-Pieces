shader_type spatial;
render_mode cull_disabled;
// Barbed wire and cable: thin rusty lines that sway a little in the wind.
// Vertex colour R is how free a point is to move (0 at a picket or a nail).
uniform vec3 colour : source_color = vec3(0.14, 0.09, 0.06);
uniform float amount = 0.04;

void vertex() {
	float k = COLOR.r;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = sin(TIME * 1.3 + w.x * 0.7 + w.z * 0.3) * 0.6 + sin(TIME * 2.9 + w.x * 1.9) * 0.4;
	VERTEX += vec3(0.3, 0.15, 1.0) * s * amount * k;
}

void fragment() {
	ALBEDO = colour;
	ROUGHNESS = 0.6;
	METALLIC = 0.5;
}
