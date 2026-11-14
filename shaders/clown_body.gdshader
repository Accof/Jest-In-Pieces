shader_type spatial;
// Clown body: bullet wounds (dents + blood soaking into the cloth) and
// per-segment hiding for dismemberment. One shader is shared by every surface.
// Drawn double-sided: through a blast hole you see the raw inside of the far wall.
render_mode cull_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Rest-pose position of each vertex is baked into vertex colour.
uniform vec3 rest_min = vec3(-0.953, -0.005, -0.155);
uniform vec3 rest_size = vec3(1.906, 1.887, 0.353);

// Bit n set = segment n is blown off (see clown_segments.json).
uniform int hidden_mask = 0;

const int MAX_WOUNDS = 16;
uniform int wound_count = 0;
uniform vec4 wounds[MAX_WOUNDS];    // xyz = rest-space position, w = radius (m)
uniform vec4 wound_fx[MAX_WOUNDS];  // x = dent depth (m), y = soak 0..1, z = seed, w = blown-out hole radius (m)
uniform vec3 blood_color : source_color = vec3(0.25, 0.012, 0.016);
uniform vec3 hole_color : source_color = vec3(0.035, 0.0, 0.002);
uniform vec3 meat_color : source_color = vec3(0.42, 0.035, 0.04);
uniform vec3 inside_color : source_color = vec3(0.16, 0.008, 0.012);

varying vec3 rest_pos;
varying float hide;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	rest_pos = COLOR.rgb * rest_size + rest_min;
	int seg = int(UV2.x * 16.0);
	bool gone = ((hidden_mask >> seg) & 1) == 1;
	bool wound_cap = UV2.y < 0.4;       // stump faces: only drawn once the limb is gone
	hide = (wound_cap ? !gone : gone) ? 1.0 : 0.0;
	if (hide > 0.5) {
		VERTEX = vec3(0.0);
	} else {
		for (int i = 0; i < wound_count; i++) {
			float d = distance(rest_pos, wounds[i].xyz);
			float f = 1.0 - smoothstep(0.0, wounds[i].w * 1.7, d);
			VERTEX -= NORMAL * wound_fx[i].x * f * f;
		}
	}
}

void fragment() {
	if (hide > 0.5) {
		discard;
	}
	vec3 col = albedo_color.rgb;
	if (use_tex) {
		col *= texture(albedo_tex, UV).rgb;
	}
	float blood = 0.0;
	float hole = 0.0;
	float torn = 0.0;       // ragged meat around a blown-out hole
	for (int i = 0; i < wound_count; i++) {
		vec3 d = rest_pos - wounds[i].xyz;
		float r = wounds[i].w;
		float n = noise3(rest_pos * 46.0 + wound_fx[i].z);
		float n2 = noise3(rest_pos * 140.0 + wound_fx[i].z);
		float blast = wound_fx[i].w;
		if (blast > 0.0) {
			// A shotgun blast takes a ragged bite clean out of the body.
			float ragged = length(d) + (n - 0.5) * blast * 0.7 + (n2 - 0.5) * blast * 0.3;
			if (ragged < blast) {
				discard;
			}
			torn = max(torn, 1.0 - smoothstep(blast, blast * 1.45, ragged));
		}
		d.y *= d.y < 0.0 ? 0.5 : 1.3;   // blood runs down the body
		float dist = length(d) + (n - 0.5) * r * 0.9 + (n2 - 0.5) * r * 0.25;
		hole = max(hole, 1.0 - smoothstep(r * 0.22, r * 0.36, dist));
		float soak_r = r * (1.3 + 2.6 * wound_fx[i].y);
		blood = max(blood, 1.0 - smoothstep(soak_r * 0.5, soak_r, dist));
	}
	col = mix(col, blood_color * (0.7 + 0.6 * noise3(rest_pos * 90.0)), blood * 0.9);
	col = mix(col, hole_color, hole);
	col = mix(col, meat_color * (0.55 + 0.9 * noise3(rest_pos * 210.0)), torn);
	float wet = max(max(blood * 0.6, hole), torn);
	if (!FRONT_FACING) {
		col = inside_color * (0.6 + 0.8 * noise3(rest_pos * 60.0));
		wet = 1.0;
	}
	ALBEDO = col;
	ROUGHNESS = mix(roughness, 0.2, wet);
	METALLIC = metallic;
	SPECULAR = mix(0.5, 0.75, wet);
}
