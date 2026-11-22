shader_type spatial;
render_mode cull_disabled;
// Torn canvas hung over a doorway: pinned along the top, lifting and
// rippling in the wind toward the bottom, with ragged holes.
uniform vec3 albedo : source_color = vec3(0.26, 0.23, 0.17);

void vertex() {
	float hang = 1.0 - UV.y;                       // UV.y 0 at the top
	hang = 1.0 - hang;
	float w = sin(TIME * 1.7 + UV.x * 4.0) * 0.6 + sin(TIME * 3.1 + UV.y * 6.0 + UV.x * 2.0) * 0.3;
	VERTEX.z += w * 0.09 * hang * hang;
	VERTEX.x += sin(TIME * 1.1 + UV.y * 3.0) * 0.03 * hang;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 cellv = floor(UV * vec2(9.0, 13.0));
	float holes = step(0.93, hash(cellv)) * step(0.35, UV.y);
	float ragged = step(0.92 - 0.15 * hash(vec2(floor(UV.x * 23.0), 1.0)), UV.y);
	if (holes > 0.5 || ragged > 0.5) {
		discard;
	}
	float stain = smoothstep(0.4, 1.0, UV.y) * 0.5;
	ALBEDO = albedo * (1.0 - stain * 0.6);
	ROUGHNESS = 0.95;
}
