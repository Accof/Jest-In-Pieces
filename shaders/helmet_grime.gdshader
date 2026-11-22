shader_type spatial;
// A soldier's helmet as he has worn it: the shell's own material (colour,
// texture, PBR maps) with his own dust and mud over it. Each man gets his own
// amounts and seed (Clown._grime_helmet), so no two helmets in a trench match:
// some still clean and glossy, some dull with dust settled on the crown,
// some splashed from below, some smeared over entirely.
//
// The helmet is a rigid mesh on the head bone; its own space has +Y up the
// crown and the origin at the helmet's middle, so dust settles on the faces
// pointing up its own +Y and mud thickens toward the rim.

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;
// glTF metal/roughness map (G roughness, B metallic) and normal map, if it has them
uniform bool use_mr = false;
uniform sampler2D mr_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;

// 0 none .. 1 a dull film all over (thickest on the crown)
uniform float dust = 0.0;
// 0 none .. 1 smeared over entirely
uniform float mud = 0.0;
uniform float seed = 0.0;
uniform float half_height = 0.12;        // half the helmet's height (m)
uniform float mid_y = 0.0;               // the helmet's middle, in its own space
uniform vec3 dust_color : source_color = vec3(0.41, 0.36, 0.28);
uniform vec3 mud_wet : source_color = vec3(0.075, 0.056, 0.038);
uniform vec3 mud_dry : source_color = vec3(0.27, 0.23, 0.17);

varying vec3 obj_pos;
varying vec3 obj_nrm;

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
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

void fragment() {
	vec3 col = albedo_color.rgb;
	if (use_tex) {
		col *= texture(albedo_tex, UV).rgb;
	}
	float rough = roughness;
	float metal = metallic;
	if (use_mr) {
		vec3 mr = texture(mr_tex, UV).rgb;
		rough = mr.g;
		metal = mr.b;
	}
	vec3 q = obj_pos + vec3(seed * 1.73, seed * 0.91, seed * 2.37);
	vec3 n = normalize(obj_nrm);
	float h = clamp((obj_pos.y - mid_y) / max(half_height, 0.01), -1.0, 1.0);   // -1 rim .. 1 crown
	float big = noise3(q * 9.0);
	float mid = noise3(q * 28.0);
	float fine = noise3(q * 110.0);

	// --- dust: a dry film, settled thickest on what faces up, washed into
	// streaks down the sides by rain, thinnest where it is handled (the brim's
	// front edge)
	float up = smoothstep(-0.2, 0.85, n.y);
	float streak = noise3(vec3(q.x * 55.0, q.y * 5.0, q.z * 55.0));
	float film = dust * (0.3 + 0.7 * up) * (0.55 + 0.6 * mid) * (0.7 + 0.45 * streak);
	// wiped and rubbed: patches where the shine still comes through
	film *= smoothstep(0.28, 0.5, big + (streak - 0.5) * 0.3);
	film += dust * smoothstep(0.7, 0.85, fine) * 0.35;               // grit
	film = clamp(film, 0.0, 1.0);

	// --- mud: thrown up from below and smeared on by hand. Patches grow as
	// `mud` rises until at 1 the shell is covered; heavier toward the rim.
	float smear = noise3(vec3(q.x * 14.0 + q.y * 9.0, q.y * 4.0, q.z * 14.0 - q.y * 7.0));
	float field = big * 0.45 + mid * 0.25 + smear * 0.3 + (0.25 - h * 0.25) * 0.35;
	float t = mix(0.95, 0.3, mud);
	float caked = smoothstep(t, t + 0.07, field + (fine - 0.5) * 0.08);
	// flecks: a splash or two even on a mostly clean one
	float flecks = smoothstep(0.86 - 0.18 * mud - 0.06 * dust, 0.9 - 0.18 * mud - 0.06 * dust, noise3(q * 75.0)) * (0.4 + 0.6 * smoothstep(0.6, -0.6, h));
	float m = clamp(max(caked, flecks * 0.9), 0.0, 1.0);
	// thick in the middle of a patch, thin and drying at its edge
	float thick = smoothstep(t, t + 0.35, field) * m;
	float drying = clamp(0.35 + (1.0 - thick) * 0.4 + (big - 0.5) * 0.6 + h * 0.15, 0.0, 1.0);
	vec3 mc = mix(mud_wet, mud_dry, drying) * (0.8 + 0.12 * mid + 0.3 * big);
	// a dried, paler crust on the thickest lumps
	mc = mix(mc, mud_dry * 1.15, smoothstep(0.6, 0.8, big) * thick * 0.35);

	col = mix(col, dust_color * (0.82 + 0.3 * fine), film * 0.68);
	col = mix(col, mc, m * 0.96);

	// relief: lumps of caked mud stand off the steel
	float relief = thick * (0.6 * mid + 0.4 * fine);
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(relief);
	float dhdy = dFdy(relief);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	NORMAL = normalize(abs(det) * NORMAL - 0.004 * grad);

	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 1.0 - clamp(m * 0.9 + film * 0.4, 0.0, 1.0);
	}
	// dust dulls the shine; dried mud is chalky, fresh mud has a dull wet sheen
	float cover = clamp(m + film * 0.85, 0.0, 1.0);
	ALBEDO = col;
	METALLIC = metal * (1.0 - cover);
	ROUGHNESS = mix(mix(rough, 0.9, film), mix(0.5, 0.95, drying), m);
	SPECULAR = mix(mix(specular_amount, 0.25, film), mix(0.45, 0.2, drying), m);
}
