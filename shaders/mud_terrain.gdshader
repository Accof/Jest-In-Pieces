shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// The Drowned Trenches ground. Four muds, blended by where a point is:
//   trench floor     Poly Haven brown_mud_03 (a scanned PBR set: albedo,
//                    GL normal, AO/roughness/height packed), with parallax
//                    occlusion from the height map, wet glossy hollows
//                    holding water, rough crumbs on top, darkened and
//                    saturated toward wet Flanders mud
//   walls            Poly Haven brown_mud (the wall set), projected on X or
//                    Z by which way the wall faces, v down the wall; two
//                    samples at different scales blended by noise so a long
//                    wall does not repeat; wetter and darker at the foot
//   ground up top    the same brown mud (exposed, thrown-up earth) near the
//                    trenches, the procedural firm ground further off
//   rocks            Poly Haven rocks_ground_08 on the eroded rim where the
//                    wall breaks over, in slumped and damaged stretches
//                    (vertex A), in patches of ground, and at the foot of
//                    bare walls; blended by its height map so stones stand
//                    proud of the mud rather than fading in
// Wetness (vertex R) darkens and glosses it; puddles lie in the flat low
// places (noise and wetness), opaque muddy water.
// Vertex colour: R wetness, G 1 on the trench floor, B distance from the
// floor edge / 2 m, A damage (slumped, broken-down, cratered: rubble).

// walls and exposed earth (art/trench/pbr/brown_mud_wall)
uniform sampler2D wall_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_ard : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;    // R AO, G roughness, B height
// rocks (art/trench/pbr/rocks_ground_08)
uniform sampler2D rocks_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocks_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocks_ard : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// firmer ground further off (procedural, art/trench/ground_firm)
uniform sampler2D firm_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D firm_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D firm_r : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// the trench floor (art/trench/polyhaven)
uniform sampler2D floor_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_ard : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;   // R AO, G roughness, B height
uniform bool floor_scan = true;             // false: the brown wall mud on the floor too (for comparison)
uniform float floor_tile = 2.4;             // metres per tile (the boot prints come out boot-sized)
uniform float floor_depth = 0.045;          // parallax: the deepest hollow below the crests (m)
uniform float floor_parallax_range = 14.0;  // parallax fades out by this distance (m)
uniform float floor_normal_strength = 1.15;
uniform vec3 floor_tint : source_color = vec3(0.82, 0.76, 0.7);   // darker, browner than the scan
uniform float floor_darkness = 0.62;   // (was 0.4: the floor read as black from eye height)
uniform float floor_saturation = 1.2;
uniform float floor_water = 0.36;           // height below which hollows hold water, where wet enough
uniform vec3 floor_water_col : source_color = vec3(0.13, 0.12, 0.11);

uniform float mud_tile = 2.2;        // metres per tile, firm ground
uniform float wall_tile = 2.5;       // metres per tile, the brown mud on walls and up top
uniform float rock_tile = 2.0;       // metres per tile, rocks
uniform vec3 wall_tint : source_color = vec3(0.8, 0.77, 0.74);   // toward charcoal
uniform float wall_darkness = 0.58;   // the walls dark, wet earth
uniform float earth_darkness = 0.66;  // the thrown-up earth up top a little lighter
uniform float rock_darkness = 0.7;
uniform float rocks = 1.0;           // how much rock shows (rims, damage, patches)
uniform float wall_normal_strength = 0.6;   // how hard the wall relief bends the light
uniform float brightness = 1.15;     // the textures are authored dark
uniform vec3 water_col : source_color = vec3(0.3, 0.27, 0.235);
uniform float puddles = 0.55;
uniform bool debug_grey = false;
uniform int debug_view = 0;               // 1: show the shading normal (world, 0.5 + n/2) instead of the surface

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;
varying float skyv;
varying float pud;      // shallow standing water baked per vertex (TrenchMaze.puddle)
uniform float puddle_amount = 1.0;
uniform vec3 puddle_col : source_color = vec3(0.075, 0.068, 0.058);   // dark muddy water
// how dry the open ground away from the trenches is: rougher, a little lighter, in patches
uniform float dry_ground = 0.6;
uniform float sky_occlusion = 0.8;   // how much the baked sky visibility (UV2.x) takes from the ambient light
uniform float sky_floor = 0.2;       // never darker than this: deep, not crushed (was 0.12)

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
	skyv = UV2.x;
	pud = UV2.y;
}

// A tangent-space normal from a normal map: x and y from red and green, z
// rebuilt (the maps are imported compressed to two channels, so blue reads
// as 0). The maps are OpenGL-style, like everything Godot uses: red leans
// toward +u, green toward the TOP of the image, i.e. toward -v (v runs down
// the image).
vec3 tangent_n(sampler2D t, vec2 uv) {
	vec2 xy = texture(t, uv).rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// ...sampled flat on the ground (u along +X, v along +Z) to world: green
// leans toward -Z.
vec3 top_n(sampler2D t, vec2 uv) {
	vec3 n = tangent_n(t, uv);
	return normalize(vec3(n.x, n.z, -n.y));
}

// Parallax occlusion: march the view ray down into the height map (B of
// floor_ard, 1 = crest) and return where it first goes under the surface.
// World-top projection: u runs along +X, v along +Z, the surface faces +Y.
vec2 floor_parallax(vec2 uv, vec3 to_eye, float steps, float amount) {
	vec2 gx = dFdx(uv);
	vec2 gy = dFdy(uv);
	float layer = 1.0 / steps;
	vec2 shift = -to_eye.xz / max(to_eye.y, 0.3) * (floor_depth / floor_tile) * amount;
	vec2 duv = shift * layer;
	vec2 p = uv;
	float ray = 0.0;
	float under = 1.0 - textureGrad(floor_ard, p, gx, gy).b;
	for (int i = 0; i < 24; i++) {
		if (float(i) >= steps || ray >= under) {
			break;
		}
		p += duv;
		ray += layer;
		under = 1.0 - textureGrad(floor_ard, p, gx, gy).b;
	}
	// between the last step above the surface and the first below it
	vec2 prev = p - duv;
	float before = (1.0 - textureGrad(floor_ard, prev, gx, gy).b) - (ray - layer);
	float after = under - ray;
	float t = after / min(after - before, -0.0001);
	return mix(p, prev, clamp(t, 0.0, 1.0));
}

void fragment() {
	vec3 n = normalize(wnrm);
	float wet = vcol.r;
	float on_floor = vcol.g;
	float sd = vcol.b * 2.0;
	vec4 nz = texture(noise_tex, wpos.xz * 0.025);
	vec4 nz2 = texture(noise_tex, wpos.xz * 0.11 + 0.37);
	float damage = vcol.a;
	// --- flat ground: the brown mud (exposed earth) near the trenches, firm further off
	vec2 uv = wpos.xz / mud_tile;
	vec2 euv = wpos.xz / wall_tile;
	vec2 euv2 = euv * 0.71 + vec2(0.43, 0.17);              // a second, larger sample to break the repeat
	float pick = smoothstep(0.35, 0.65, nz.b);
	vec3 ea = mix(texture(wall_a, euv).rgb, texture(wall_a, euv2).rgb, pick);
	vec4 eard = mix(texture(wall_ard, euv), texture(wall_ard, euv2), pick);
	vec3 en = normalize(mix(top_n(wall_n, euv), top_n(wall_n, euv2), pick));
	ea *= wall_tint * earth_darkness;
	vec3 fa = texture(firm_a, uv * 0.8 + 0.71).rgb;
	float fr = texture(firm_r, uv * 0.8 + 0.71).r;
	vec3 fn = top_n(firm_n, uv * 0.8 + 0.71);
	float firm = smoothstep(2.5, 7.0, sd + (nz.r - 0.5) * 6.0) * (1.0 - on_floor);
	vec3 alb = mix(ea, fa, firm);
	float rough = mix(eard.g, fr, firm);
	vec3 tn = normalize(mix(en, fn, firm));
	float ao = mix(eard.r, 1.0, firm);
	// rocks up top: on the rim where the wall breaks over, where damaged, and in patches
	vec2 ruv = wpos.xz / rock_tile + vec2(0.21, 0.63);
	vec4 rard = texture(rocks_ard, ruv);
	float rim = smoothstep(0.05, 0.3, sd) * (1.0 - smoothstep(0.8, 1.5, sd + (nz2.r - 0.5)));
	float want = max(max(rim * smoothstep(0.35, 0.65, nz2.r + 0.15), damage), smoothstep(0.7, 0.8, nz.g) * 0.85) * rocks * (1.0 - on_floor);
	// height blend: the stones show where they stand above the mud
	float rk = smoothstep(0.0, 0.25, want * 1.25 - (1.0 - rard.b) * 0.55);
	alb = mix(alb, texture(rocks_a, ruv).rgb * rock_darkness, rk);
	rough = mix(rough, rard.g, rk);
	tn = normalize(mix(tn, top_n(rocks_n, ruv), rk));
	ao = mix(ao, rard.r, rk);
	// --- walls: the brown mud, mapped on X or Z by which way the wall faces
	float wall = smoothstep(0.35, 0.65, 1.0 - n.y);
	vec3 an = abs(n);
	float wx = an.x / max(an.x + an.z, 0.001);
	vec2 uvx = vec2(wpos.z, -wpos.y) / wall_tile;
	vec2 uvz = vec2(wpos.x, -wpos.y) / wall_tile;
	vec2 uvx2 = uvx * 0.71 + vec2(0.29, 0.57);
	vec2 uvz2 = uvz * 0.71 + vec2(0.29, 0.57);
	float wpick = smoothstep(0.35, 0.65, texture(noise_tex, vec2(wpos.x + wpos.z, wpos.y) * 0.05).b);
	vec3 wa = mix(mix(texture(wall_a, uvz).rgb, texture(wall_a, uvx).rgb, wx), mix(texture(wall_a, uvz2).rgb, texture(wall_a, uvx2).rgb, wx), wpick);
	vec4 ward = mix(mix(texture(wall_ard, uvz), texture(wall_ard, uvx), wx), mix(texture(wall_ard, uvz2), texture(wall_ard, uvx2), wx), wpick);
	vec3 wnx = mix(tangent_n(wall_n, uvx), tangent_n(wall_n, uvx2), wpick);
	vec3 wnz = mix(tangent_n(wall_n, uvz), tangent_n(wall_n, uvz2), wpick);
	// tangent-space to world for the two wall projections. On a wall facing
	// X, u runs along +Z and v down the wall (-Y), so red leans toward +Z and
	// green (toward the top of the image) toward +Y, whichever way the wall
	// faces; on a wall facing Z, u runs along +X. The lean is added to the
	// wall's own normal, so the slope of the cut is kept.
	vec3 lean_x = vec3(0.0, wnx.y, wnx.x);
	vec3 lean_z = vec3(wnz.x, wnz.y, 0.0);
	// rocks in the wall: where it has slumped or been broken down, and some at the foot
	float foot = 1.0 - smoothstep(0.0, 0.8, sd);
	vec2 rux = vec2(wpos.z, -wpos.y) / rock_tile;
	vec2 ruz = vec2(wpos.x, -wpos.y) / rock_tile;
	vec4 wrard = mix(texture(rocks_ard, ruz), texture(rocks_ard, rux), wx);
	float wwant = max(damage, foot * smoothstep(0.5, 0.75, nz2.g) * 0.7) * rocks;
	float wrk = smoothstep(0.0, 0.25, wwant * 1.25 - (1.0 - wrard.b) * 0.55);
	if (wrk > 0.001) {
		vec3 ra = mix(texture(rocks_a, ruz).rgb, texture(rocks_a, rux).rgb, wx) * rock_darkness;
		wa = mix(wa * wall_tint * wall_darkness, ra, wrk);
		vec3 rnx = tangent_n(rocks_n, rux);
		vec3 rnz = tangent_n(rocks_n, ruz);
		lean_x = mix(lean_x, vec3(0.0, rnx.y, rnx.x), wrk);
		lean_z = mix(lean_z, vec3(rnz.x, rnz.y, 0.0), wrk);
		ward = mix(ward, wrard, wrk);
	} else {
		wa *= wall_tint * wall_darkness;
	}
	vec3 wn = normalize(n + mix(lean_z, lean_x, wx) * wall_normal_strength);
	// the foot of the wall is wetter and darker, the top a little drier
	wa *= mix(1.0, 0.62, foot * 0.8);
	alb = mix(alb, wa, wall);
	rough = mix(rough, mix(ward.g, ward.g * 0.75, foot), wall);
	ao = mix(ao, ward.r, wall);
	vec3 wn_world = normalize(mix(normalize(n + (tn - vec3(0.0, 1.0, 0.0)) * 1.0), wn, wall));
	// --- wetness: everything soaked, darker and glossier the wetter
	alb *= brightness * mix(1.0, 0.8, wet);
	rough = max(mix(rough, rough * 0.6, wet), 0.24);
	// --- the trench floor: the scanned mud, given depth by parallax
	float fw = floor_scan ? on_floor * (1.0 - wall) : 0.0;
	vec3 f_alb = vec3(0.0);
	float f_rough = 1.0;
	vec3 f_n = n;
	float f_ao = 1.0;
	if (fw > 0.001) {
		vec3 to_eye = CAMERA_POSITION_WORLD - wpos;
		float dist = length(to_eye);
		to_eye /= max(dist, 0.001);
		vec2 fuv = wpos.xz / floor_tile + vec2(0.37, 0.11);
		float near = 1.0 - smoothstep(floor_parallax_range * 0.5, floor_parallax_range, dist);
		if (near > 0.0) {
			fuv = floor_parallax(fuv, to_eye, mix(6.0, 20.0, near), near);
		}
		vec4 ard = texture(floor_ard, fuv);
		float h = ard.b;
		f_ao = ard.r;
		// albedo: the scan, darker, warmer and more saturated (soaked clay mud),
		// with a slow variation across the floor so the tiling does not show
		vec3 a = texture(floor_a, fuv).rgb * floor_tint;
		float lum = dot(a, vec3(0.299, 0.587, 0.114));
		a = mix(vec3(lum), a, floor_saturation) * floor_darkness;
		a *= mix(0.78, 1.18, nz.r) * mix(0.9, 1.08, nz2.g);
		a *= mix(1.0, f_ao, 0.35);
		// wet: the low parts of the mud darker (water soaking down into them)
		float soak = smoothstep(0.7, 0.3, h) * (0.4 + 0.6 * wet);
		a *= mix(1.0, 0.6, soak);
		// roughness: the scan's own (rough crumbs, slicker smears), and a film of
		// water on everything below the crests: wet sheen, not a mirror
		float r = ard.g * 1.05 + 0.18;
		float film = soak * (0.55 + 0.45 * smoothstep(0.3, 0.7, nz2.r));
		r = mix(r, 0.16 + ard.g * 0.25, film);
		// normal: OpenGL convention (green = toward the top of the image, which
		// is -Z in this world-top projection); z rebuilt in case it was
		// compressed to two channels
		vec2 nxy = texture(floor_n, fuv).rg * 2.0 - 1.0;
		vec3 tn_f = vec3(nxy, sqrt(max(1.0 - dot(nxy, nxy), 0.0)));
		vec3 fn_world = normalize(vec3(tn_f.x, tn_f.z, -tn_f.y));
		vec3 bent = normalize(n + (fn_world - vec3(0.0, 1.0, 0.0)) * floor_normal_strength);
		// standing water in the deepest hollows, in patches
		float pool = smoothstep(floor_water + 0.05, floor_water - 0.03, h) * smoothstep(0.35, 0.6, nz2.b * 0.6 + nz.g * 0.4 + wet * 0.25);
		a = mix(a, floor_water_col * mix(0.85, 1.1, nz.b), pool * 0.85);
		r = mix(r, 0.1, pool);
		bent = normalize(mix(bent, n, pool * 0.9));
		f_alb = a;
		f_rough = r;
		f_n = bent;
	}
	// --- puddles: flat, low, wet places
	float flat_ = smoothstep(0.92, 0.985, n.y);
	float pm = smoothstep(0.62, 0.7, nz2.b * 0.55 + nz.g * 0.5 + wet * 0.35 * puddles) * flat_;
	pm *= mix(0.6, 1.0, on_floor) * (1.0 - fw);       // the floor has its own pools
	vec3 wcol = water_col * mix(0.85, 1.15, nz.b);
	alb = mix(alb, wcol, pm * 0.9);
	rough = mix(rough, 0.13, pm);
	wn_world = normalize(mix(wn_world, n, pm));
	alb = mix(alb, f_alb, fw);
	rough = mix(rough, f_rough, fw);
	wn_world = normalize(mix(wn_world, f_n, fw));
	// --- drier ground up top, away from the trenches: matte, a little lighter, in patches
	float dry = smoothstep(1.2, 3.5, sd) * smoothstep(0.35, 0.7, nz.r) * dry_ground * (1.0 - on_floor);
	alb *= mix(1.0, 1.12, dry);
	rough = mix(rough, max(rough, 0.93), dry);
	// --- shallow puddles in the floor's low places: dark muddy water, a soaked
	// rim round it; an irregular edge; flat, with the faintest stir
	float pv = pud * puddle_amount;
	if (pv > 0.01) {
		float edge_n = (nz2.b - 0.5) * 0.4 + (nz.a - 0.5) * 0.25;
		float water = smoothstep(0.3, 0.55, pv + edge_n);
		float rim = smoothstep(0.05, 0.3, pv + edge_n) * (1.0 - water);
		alb = mix(alb, alb * 0.62, rim);
		rough = mix(rough, rough * 0.5, rim);
		vec3 pc = puddle_col * mix(0.85, 1.15, nz.b);
		alb = mix(alb, pc, water * 0.94);
		rough = mix(rough, 0.035, water);
		vec2 st = wpos.xz * 3.0 + vec2(TIME * 0.05, TIME * 0.03);
		vec3 stir = vec3(texture(noise_tex, st * 0.11).r - 0.5, 0.0, texture(noise_tex, st * 0.11 + 0.5).g - 0.5) * 0.06;
		wn_world = normalize(mix(wn_world, normalize(n + stir), water));
	}
	AO = mix(ao, f_ao, fw) * mix(1.0, max(skyv, sky_floor), sky_occlusion);
	AO_LIGHT_AFFECT = 0.15;
	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn_world, 0.0)).xyz);
	if (debug_view == 1) {
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		AO = 1.0;
		EMISSION = wn_world * 0.5 + 0.5;
	}
	if (debug_view == 3) {                 // the albedo as it is, unlit (parallax tests)
		EMISSION = alb;
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	}
}
