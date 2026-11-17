shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// The Drowned Trenches ground. Four muds, blended by where a point is:
//   trench floor     sludge, churned mud heaped at the wall foot
//   walls            the cut soil strata (world-Y mapped), wet at the foot
//   ground up top    churned mud near the trenches and in shell holes,
//                    firmer ground further off, in patches
// Wetness (vertex R) darkens and glosses it; puddles lie in the flat low
// places (noise and wetness), opaque muddy water, almost mirror-smooth.
// Vertex colour: R wetness, G 1 on the trench floor, B distance from the
// floor edge / 2 m, A height.

uniform sampler2D churned_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D churned_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D churned_r : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sludge_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sludge_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sludge_r : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_r : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D firm_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D firm_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D firm_r : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

uniform float mud_tile = 2.2;        // metres per tile, churned / sludge / firm
uniform float wall_tile = 2.0;
uniform float brightness = 1.15;     // the textures are authored dark
uniform vec3 water_col : source_color = vec3(0.3, 0.27, 0.235);
uniform float puddles = 0.55;
uniform bool debug_grey = false;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}

vec3 unpack(vec3 t) {
	return t * 2.0 - 1.0;
}

// a tangent-space normal sampled flat (XZ) to world
vec3 top_n(sampler2D t, vec2 uv) {
	vec3 n = unpack(texture(t, uv).rgb);
	return normalize(vec3(n.x, n.z, n.y));
}

void fragment() {
	vec3 n = normalize(wnrm);
	float wet = vcol.r;
	float on_floor = vcol.g;
	float sd = vcol.b * 2.0;
	vec4 nz = texture(noise_tex, wpos.xz * 0.025);
	vec4 nz2 = texture(noise_tex, wpos.xz * 0.11 + 0.37);
	vec2 uv = wpos.xz / mud_tile;
	// --- flat ground: sludge in the trench, churned near it, firm in patches further off
	vec3 ca = texture(churned_a, uv).rgb;
	vec3 sa = texture(sludge_a, uv * 0.9 + 0.13).rgb;
	vec3 fa = texture(firm_a, uv * 0.8 + 0.71).rgb;
	float cr = texture(churned_r, uv).r;
	float sr = texture(sludge_r, uv * 0.9 + 0.13).r;
	float fr = texture(firm_r, uv * 0.8 + 0.71).r;
	vec3 cn = top_n(churned_n, uv);
	vec3 sn = top_n(sludge_n, uv * 0.9 + 0.13);
	vec3 fn = top_n(firm_n, uv * 0.8 + 0.71);
	// churned near the trenches (thrown-up spoil, traffic), firm further off
	float firm = smoothstep(2.5, 7.0, sd + (nz.r - 0.5) * 6.0) * (1.0 - on_floor);
	// on the floor: sludge, with churned mud heaped against the walls
	float sludge = on_floor * (1.0 - smoothstep(0.55, 0.85, nz2.g + 0.25 * (1.0 - wet)));
	vec3 alb = mix(ca, fa, firm);
	float rough = mix(cr, fr, firm);
	vec3 tn = normalize(mix(cn, fn, firm));
	alb = mix(alb, sa, sludge);
	rough = mix(rough, sr, sludge);
	tn = normalize(mix(tn, sn, sludge));
	// --- walls: the soil strata, mapped on X or Z by which way the wall faces
	float wall = smoothstep(0.35, 0.65, 1.0 - n.y);
	vec3 an = abs(n);
	float wx = an.x / max(an.x + an.z, 0.001);
	vec2 uvx = vec2(wpos.z, -wpos.y) / wall_tile;
	vec2 uvz = vec2(wpos.x, -wpos.y) / wall_tile;
	vec3 wa = mix(texture(wall_a, uvz).rgb, texture(wall_a, uvx).rgb, wx);
	float wr = mix(texture(wall_r, uvz).r, texture(wall_r, uvx).r, wx);
	vec3 wnx = unpack(texture(wall_n, uvx).rgb);
	vec3 wnz = unpack(texture(wall_n, uvz).rgb);
	// tangent-space to world for the two wall projections
	vec3 wn_x = normalize(vec3(sign(n.x) * 1.0, -wnx.y, wnx.x * sign(n.x)));
	vec3 wn_z = normalize(vec3(wnz.x, -wnz.y, sign(n.z) * 1.0));
	vec3 wn = normalize(mix(normalize(mix(wn_z, wn_x, wx)), n, 0.45));
	// the foot of the wall is wetter and darker, the top a little drier
	float foot = 1.0 - smoothstep(0.0, 0.8, sd);
	wa *= mix(1.0, 0.6, foot * 0.8);
	alb = mix(alb, wa, wall);
	rough = mix(rough, wr, wall);
	vec3 wn_world = normalize(mix(normalize(n + (tn - vec3(0.0, 1.0, 0.0)) * 1.0), wn, wall));
	// --- wetness: everything soaked, darker and glossier the wetter
	alb *= brightness * mix(1.0, 0.8, wet);
	rough = max(mix(rough, rough * 0.6, wet), 0.24);
	// --- puddles: flat, low, wet places
	float flat_ = smoothstep(0.92, 0.985, n.y);
	float pm = smoothstep(0.62, 0.7, nz2.b * 0.55 + nz.g * 0.5 + wet * 0.35 * puddles) * flat_;
	pm *= mix(0.6, 1.0, on_floor);
	vec3 wcol = water_col * mix(0.85, 1.15, nz.b);
	alb = mix(alb, wcol, pm * 0.9);
	rough = mix(rough, 0.13, pm);
	wn_world = normalize(mix(wn_world, n, pm));
	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn_world, 0.0)).xyz);
}
