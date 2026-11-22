shader_type spatial;
// A single red balloon caught on the wire, bobbing on its string.
void vertex() {
	vec3 sway = vec3(sin(TIME * 0.9) * 0.08, sin(TIME * 1.7) * 0.02, sin(TIME * 0.7 + 1.0) * 0.05);
	VERTEX += sway * (VERTEX.y + 0.2);
}
void fragment() {
	ALBEDO = vec3(0.45, 0.03, 0.03);
	ROUGHNESS = 0.25;
	SPECULAR = 0.6;
	RIM = 0.2;
}
