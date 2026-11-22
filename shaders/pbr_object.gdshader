shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// A scanned PBR set (albedo, OpenGL normal map, packed AO/roughness/height)
// on the trench's props: boards, posts, duckboards, sandbags, iron sheets.
//
// Mapped in object space, triplanar, in metres: each instance's own scale is
// taken out of the position first, so a 1.5 m board and a 0.2 m slat get the
// same texture density and nothing stretches along a long board. With
// `grain` on, the texture's v (down the image: the grain of the wood) runs
// along each piece's longest side, so boards are grained along their length
// and posts up their height. Without it v runs down (rust streaks fall).
// Each instance picks its own part of the texture (and may turn it over), so
// neighbouring boards and bags do not repeat.
//
// Normal maps: OpenGL convention. Red leans toward +u, green toward the top
// of the image (-v); z is rebuilt from red and green because the import
// compresses normal maps to two channels.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ard_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;   // R AO, G roughness, B height
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float tile = 1.0;                     // metres per texture repeat
uniform bool grain = false;                   // v along the longest side (wood)
uniform vec3 tint : source_color = vec3(1.0);
uniform float darken = 1.0;
uniform float saturation = 1.0;
uniform float normal_strength = 1.0;
uniform float rough_min = 0.35;               // never glossier than this (wet, not varnished)
uniform float rough_scale = 1.0;
uniform float wet = 0.4;                      // 0 dry .. 1 soaked: darker, a little slicker
uniform float grime = 0.4;                    // mud smeared over it, in patches
uniform vec3 grime_col : source_color = vec3(0.16, 0.12, 0.09);
uniform float metal_from_albedo = 0.0;        // >0: bare (grey, unrusted) patches read as metal
uniform float ao_strength = 1.0;
// Mud thrown up and soaked in low down (within about half a metre of the
// ground: boots, rain splash, men brushing past): 0 none .. 1 heavy. Needs the
// ground's height (sky_tex G), so only in the trenches.
uniform float splash = 0.0;
// Darker, slicker wet edges and ends (water runs off and soaks in there).
uniform float wet_edges = 0.0;
// Under a roof (a dugout's beams, sheets and props): the sky is shut out,
// whatever the ground's visibility says at that spot.
uniform float under_cover = 0.0;
// the trench floor's baked sky visibility (TrenchMaze.sky_texture: R vis, G ground height)
uniform sampler2D sky_tex : filter_linear, repeat_disable;
uniform bool sky_on = false;
uniform vec2 sky_origin = vec2(0.0);
uniform vec2 sky_size = vec2(1.0);
uniform float sky_floor = 0.2;
uniform float sky_occlusion = 0.8;   // how much of the darkening down in the trench is taken (as the ground's)
uniform bool vary = true;                     // each instance its own part of the texture (off for tests)
uniform int debug_view = 0;                   // 1: show the shading normal (world, 0.5 + n/2)

varying vec3 opos;      // object position in metres (scale taken out)
varying vec3 onrm;      // object-space normal
varying vec3 osize;     // the instance's scale (its size, for boxes)
varying vec3 wpos;
varying float seed;

void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	osize = s;
	opos = VERTEX * s;
	onrm = NORMAL;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 o = MODEL_MATRIX[3].xyz;
	seed = fract(sin(dot(o, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// This projection's (u, v) axes in object space: `a` is the axis it looks
// along (0 x, 1 y, 2 z).
void axes(int a, out vec3 U, out vec3 V) {
	vec3 X = vec3(1.0, 0.0, 0.0);
	vec3 Y = vec3(0.0, 1.0, 0.0);
	vec3 Z = vec3(0.0, 0.0, 1.0);
	if (a == 0) { U = Z; V = -Y; }        // v down the face
	else if (a == 1) { U = X; V = Z; }
	else { U = X; V = -Y; }
	if (grain) {
		// the grain (v) along the longer of the two sides in this plane
		vec3 p = a == 0 ? vec3(0.0, osize.y, osize.z) : (a == 1 ? vec3(osize.x, 0.0, osize.z) : vec3(osize.x, osize.y, 0.0));
		vec3 longest = p.x >= max(p.y, p.z) ? X : (p.y >= p.z ? Y : Z);
		vec3 other = a == 0 ? (longest == Y ? Z : Y) : (a == 1 ? (longest == X ? Z : X) : (longest == X ? Y : X));
		V = longest;
		U = other;
	}
}

void fragment() {
	vec3 n = normalize(onrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 off = vary ? vec2(seed, fract(seed * 7.13)) * 7.0 : vec2(0.0);   // this instance's part of the texture
	float flip = (vary && seed > 0.5) ? -1.0 : 1.0;                        // and which way up
	vec3 alb = vec3(0.0);
	vec4 ard = vec4(0.0);
	vec3 nb = vec3(0.0);
	for (int a = 0; a < 3; a++) {
		float wa = a == 0 ? w.x : (a == 1 ? w.y : w.z);
		if (wa < 0.01) {
			continue;
		}
		vec3 U;
		vec3 V;
		axes(a, U, V);
		U *= flip;
		V *= flip;
		vec2 uv = vec2(dot(opos, U), dot(opos, V)) / tile + off;
		alb += texture(albedo_tex, uv).rgb * wa;
		ard += texture(ard_tex, uv) * wa;
		vec2 xy = texture(normal_tex, uv).rg * 2.0 - 1.0;
		// red toward +u, green toward the top of the image (-v)
		vec3 lean = (xy.x * U - xy.y * V) * normal_strength;
		nb += (n + lean) * wa;
	}
	vec3 obj_n = normalize(nb);
	// to world: the rotation only (positions were measured with scale taken out)
	mat3 R = mat3(normalize(MODEL_MATRIX[0].xyz), normalize(MODEL_MATRIX[1].xyz), normalize(MODEL_MATRIX[2].xyz));
	vec3 wn = normalize(R * obj_n);
	// colour: the scan, tinted and darkened toward the trench's filth
	alb *= tint;
	float lum = dot(alb, vec3(0.299, 0.587, 0.114));
	alb = mix(vec3(lum), alb, saturation) * darken;
	// mud smeared on in patches, thicker low down
	float nz = texture(noise_tex, wpos.xz * 0.35 + wpos.y * 0.2 + seed).g;
	float smear = smoothstep(0.55, 0.75, nz + grime * 0.35) * grime;
	alb = mix(alb, grime_col, smear * 0.8);
	alb *= mix(1.0, 0.72, wet);
	alb *= mix(1.0, ard.r, 0.3 * ao_strength);
	float rough = ard.g * rough_scale;
	rough = mix(rough, rough * 0.8, wet);
	rough = mix(rough, 0.9, smear * 0.5);
	// soaked, darker edges: the second-nearest face of the piece (the nearest
	// is the one this is on) within a few centimetres
	if (wet_edges > 0.0) {
		vec3 dist = osize * 0.5 - abs(opos);
		float a = min(dist.x, min(dist.y, dist.z));
		float b = max(dist.x, max(dist.y, dist.z));
		float c2 = dist.x + dist.y + dist.z - a - b;
		float edge = (1.0 - smoothstep(0.004, 0.035, c2)) * wet_edges;
		alb *= mix(1.0, 0.7, edge);
		rough = mix(rough, rough * 0.6, edge);
	}
	// mud splashed up from the ground and soaked in, low down: thickest at the
	// foot, in splashes above that; wet, with a dull sheen
	if (splash > 0.0 && sky_on) {
		vec2 gs = texture(sky_tex, (wpos.xz - sky_origin) / sky_size).rg;
		float above = wpos.y - gs.g;
		float low = 1.0 - smoothstep(0.02, 0.55, above);
		float sp = texture(noise_tex, wpos.xz * 1.7 + vec2(wpos.y * 2.3, seed)).b;
		float mud = clamp(low * splash * smoothstep(0.3, 0.6, sp + low * 0.45), 0.0, 1.0);
		alb = mix(alb, grime_col * 0.75, mud * 0.85);
		rough = mix(rough, 0.42, mud);
	}
	float metal = 0.0;
	if (metal_from_albedo > 0.0) {
		// bare metal where the scan is grey rather than rust-brown
		float sat = (max(alb.r, max(alb.g, alb.b)) - min(alb.r, min(alb.g, alb.b))) / max(max(alb.r, max(alb.g, alb.b)), 0.001);
		metal = metal_from_albedo * smoothstep(0.35, 0.15, sat) * (1.0 - smear);
	}
	// down in the trench the sky is mostly hidden: the ground's visibility
	// below, opening out to all of it at the top of the cut
	float vis = 1.0;
	if (sky_on) {
		vec2 g = texture(sky_tex, (wpos.xz - sky_origin) / sky_size).rg;
		float up = clamp((wpos.y - g.g) / max(-g.g + 0.2, 0.3), 0.0, 1.0);
		vis = mix(max(g.r, sky_floor), 1.0, up);
		vis = mix(1.0, vis, sky_occlusion);
	}
	vis = mix(vis, sky_floor * 0.6, under_cover);
	ALBEDO = alb;
	ROUGHNESS = clamp(max(rough, rough_min), 0.0, 1.0);
	METALLIC = metal;
	SPECULAR = 0.4;
	AO = mix(1.0, ard.r, ao_strength) * vis;
	AO_LIGHT_AFFECT = 0.1;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	if (debug_view == 1) {
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		METALLIC = 0.0;
		AO = 1.0;
		EMISSION = wn * 0.5 + 0.5;
	}
}
