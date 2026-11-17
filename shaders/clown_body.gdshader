shader_type spatial;
// Clown body: bullet wounds (dents + blood soaking into the cloth) and
// per-segment hiding for dismemberment. One shader is shared by every surface.
// Drawn double-sided: through a blast hole you see the raw inside of the far wall.
render_mode cull_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
// How much plain highlight the dry surface takes (0.5 is Godot's default; cloth wants less).
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Rest-pose position of each vertex is baked into vertex colour.
uniform vec3 rest_min = vec3(-0.953, -0.005, -0.155);
uniform vec3 rest_size = vec3(1.906, 1.887, 0.353);

// Bit n set = segment n is blown off (see clown_segments.json).
uniform int hidden_mask = 0;
// Segments whose stump faces must stay hidden: everything below the cut when a
// whole chain comes off (otherwise the knee and ankle caps float in the air).
uniform int cap_hide_mask = 0;

const int MAX_WOUNDS = 16;
uniform int wound_count = 0;
uniform vec4 wounds[MAX_WOUNDS];    // xyz = rest-space position, w = radius (m)
uniform vec4 wound_fx[MAX_WOUNDS];  // x = dent depth (m), y = soak 0..1, z = seed, w = blown-out hole radius (m)
// Holes punched clean through the body (a shotgun at point blank): a ragged
// tunnel along the shot, so you can see out the other side.
const int MAX_TUNNELS = 4;
uniform int tunnel_count = 0;
uniform vec4 tunnels[MAX_TUNNELS];      // xyz = rest-space point on the line, w = radius (m)
uniform vec4 tunnel_dirs[MAX_TUNNELS];  // xyz = rest-space direction, w = how far along it the hole reaches either way
uniform vec3 blood_color : source_color = vec3(0.30, 0.012, 0.018);
// Blood soaked into cloth: how dark and saturated the soak goes, and how much
// spray and runs there are round a wound.
uniform float soak_darkness : hint_range(0.0, 1.0) = 0.8;
uniform float spatter_amount : hint_range(0.0, 2.0) = 1.0;
uniform vec3 hole_color : source_color = vec3(0.035, 0.0, 0.002);
uniform vec3 meat_color : source_color = vec3(0.42, 0.035, 0.04);
uniform vec3 inside_color : source_color = vec3(0.16, 0.008, 0.012);
// A box of the rest pose cut away (the Klappersoldat loses the gas mask's
// canister under its porcelain face). Off unless cut_max is above cut_min.
// 0..1: long dead and left to rot somewhere damp (the locker joker): the
// colours sour to a grey-green pallor with black mould blooming through.
uniform float decay = 0.0;
uniform vec3 cut_min = vec3(1.0);
uniform vec3 cut_max = vec3(0.0);

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
	// Stump faces: only drawn once the limb is gone. They are flagged 0.25 in
	// Blender; the glTF export flips V, so accept either side of 0.5.
	bool wound_cap = abs(UV2.y - 0.5) > 0.1;
	bool cap_off = ((cap_hide_mask >> seg) & 1) == 1;
	hide = (wound_cap ? (!gone || cap_off) : gone) ? 1.0 : 0.0;
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
	if (all(greaterThan(rest_pos, cut_min)) && all(lessThan(rest_pos, cut_max))) {
		discard;
	}
	vec3 col = albedo_color.rgb;
	if (use_tex) {
		col *= texture(albedo_tex, UV).rgb;
	}
	if (decay > 0.0) {
		float grey = dot(col, vec3(0.3, 0.59, 0.11));
		col = mix(col, grey * vec3(0.82, 0.92, 0.74), decay * 0.7);
		float m = noise3(rest_pos * 7.0) * 0.6 + noise3(rest_pos * 26.0) * 0.4;
		float mould = smoothstep(0.56, 0.74, m) * decay;
		col = mix(col, vec3(0.1, 0.13, 0.06) * (0.5 + noise3(rest_pos * 150.0)), mould * 0.85);
		// damp tide-mark up the legs from standing in its own seepage
		float tide = (1.0 - smoothstep(0.35, 0.6, rest_pos.y + (noise3(rest_pos * 12.0) - 0.5) * 0.12)) * decay;
		col = mix(col, vec3(0.16, 0.08, 0.04), tide * 0.6);
	}
	float blood = 0.0;      // soaked into the cloth
	float tide = 0.0;       // the darker rim of a soak
	float fresh = 0.0;      // wet blood right round the hole
	float spat = 0.0;       // spray
	float drip = 0.0;       // runs
	float hole = 0.0;
	float torn = 0.0;       // ragged meat around a blown-out hole
	for (int i = 0; i < tunnel_count; i++) {
		vec3 d = rest_pos - tunnels[i].xyz;
		vec3 ax = tunnel_dirs[i].xyz;
		float along = dot(d, ax);
		if (abs(along) > tunnel_dirs[i].w) {
			continue;
		}
		float r = tunnels[i].w;
		float off = length(d - ax * along);
		float n = noise3(rest_pos * 38.0 + float(i) * 7.3);
		float n2 = noise3(rest_pos * 120.0 + float(i) * 3.1);
		// ragged: the edge wanders, and the exit side is torn wider than the entry
		float ragged = off + (n - 0.5) * r * 0.55 + (n2 - 0.5) * r * 0.25 - max(along, 0.0) * 0.25;
		if (ragged < r) {
			discard;
		}
		torn = max(torn, 1.0 - smoothstep(r, r * 1.6, ragged));
	}
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
		float soak_amt = wound_fx[i].y;
		float seed = wound_fx[i].z;
		// the hole itself
		float dh = length(d) + (n - 0.5) * r * 0.9 + (n2 - 0.5) * r * 0.25;
		hole = max(hole, 1.0 - smoothstep(r * 0.22, r * 0.36, dh));
		// fresh, still-wet blood welling round it
		fresh = max(fresh, 1.0 - smoothstep(r * 0.3, r * 0.65, dh));
		// soaked into the cloth: a big irregular stain, heavier below (it runs
		// down and wicks), with a fairly hard edge and a darker tide line
		vec3 g = d;
		g.y *= g.y < 0.0 ? 0.5 : 1.3;
		float soak_r = r * (1.5 + 3.0 * soak_amt);
		float warp = noise3(rest_pos * 17.0 + seed) * 0.65 + noise3(rest_pos * 52.0 + seed * 1.7) * 0.35;
		float ds = length(g) + (warp - 0.5) * soak_r * 0.8;
		float s_in = 1.0 - smoothstep(soak_r * 0.8, soak_r, ds);
		blood = max(blood, s_in);
		tide = max(tide, smoothstep(soak_r * 0.62, soak_r * 0.92, ds) * s_in);
		// spray round it: fine droplets and a few bigger flecks, thinning out to
		// two and a half times the stain
		float spray_r = soak_r * 1.9;
		float near = 1.0 - smoothstep(soak_r * 0.6, spray_r, length(d));
		near = near * near * spatter_amount;
		if (near > 0.0) {
			// two scales of droplet, on coordinates turned off the grid so
			// they come out round, not blocky
			vec3 q = mat3(vec3(0.8, 0.36, -0.48), vec3(-0.6, 0.48, -0.64), vec3(0.0, 0.8, 0.6)) * rest_pos;
			float fine = noise3(q * 170.0 + seed * 3.1);
			float fleck = noise3(q * 70.0 + seed * 5.3);
			spat = max(spat, smoothstep(0.83 - 0.12 * near, 0.85 - 0.12 * near, fine));
			spat = max(spat, smoothstep(0.82 - 0.1 * near, 0.84 - 0.1 * near, fleck));
		}
		// runs: thin lanes trickling down from the stain
		float below = wounds[i].xyz.y - rest_pos.y;
		float run_len = soak_r * (1.5 + 3.5 * soak_amt) * spatter_amount;
		if (below > 0.0 && below < run_len) {
			float hd = length(d.xz);
			float lane = noise3(vec3(rest_pos.x * 60.0, rest_pos.y * 2.5, rest_pos.z * 60.0) + seed * 2.3);
			float lane_w = (1.0 - smoothstep(soak_r * 0.5, soak_r * 1.1, hd)) * (1.0 - below / run_len);
			drip = max(drip, smoothstep(0.66, 0.72, lane) * lane_w);
		}
	}
	// The look: cloth soaked dark, deep red going almost black where it is
	// heaviest, a darker tide line at the edge, the weave still showing
	// through; fresh blood brighter and wet only right round the hole;
	// spray and runs in deep red over the top.
	float luma = clamp(dot(col, vec3(0.3, 0.59, 0.11)) * 1.6, 0.25, 1.2);
	float mottle = 0.82 + 0.36 * noise3(rest_pos * 24.0);
	vec3 soaked = blood_color * mix(1.0, 0.38, soak_darkness * smoothstep(0.2, 1.0, blood)) * luma * mottle;
	soaked = mix(soaked, blood_color * 0.22, tide * 0.7);
	vec3 fresh_col = blood_color * 1.15 * (0.85 + 0.3 * noise3(rest_pos * 160.0));
	col = mix(col, soaked, blood);
	col = mix(col, blood_color * 0.75 * mottle, max(spat, drip) * (1.0 - blood * 0.5));
	col = mix(col, fresh_col, fresh * 0.85);
	col = mix(col, hole_color, hole);
	col = mix(col, meat_color * (0.55 + 0.9 * noise3(rest_pos * 210.0)), torn);
	// sheen: damp soaked cloth only a little; fresh blood, holes and meat wet
	float damp = max(blood * 0.3, max(spat, drip) * 0.35);
	float wet = max(max(fresh * 0.85, hole), torn);
	if (!FRONT_FACING) {
		col = inside_color * (0.6 + 0.8 * noise3(rest_pos * 60.0));
		wet = 1.0;
	}
	ALBEDO = col;
	ROUGHNESS = mix(mix(roughness, 0.6, damp), 0.3, wet);
	METALLIC = metallic;
	SPECULAR = mix(mix(specular_amount, 0.38, damp), 0.6, wet);
}
