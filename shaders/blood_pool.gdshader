shader_type spatial;
// A pool of blood (or oil) lying on the floor mesh BloodPool built for it.
// UV2.x: when the blood reaches this point (progress units); UV2.y: how thick
// it can get here (0 at the outline, 1 at the source). COLOR.a: 1 on the
// strips down step faces. The pool is drawn up to `progress`, which the
// Blood manager raises as it spreads.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_schlick_ggx;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 thin_color : source_color = vec3(0.21, 0.014, 0.018);
uniform vec3 deep_color : source_color = vec3(0.065, 0.003, 0.006);
uniform vec3 dry_color : source_color = vec3(0.075, 0.018, 0.012);
// Oil (the Klappersoldat): a faint rainbow film over the dark surface. 0 for blood.
uniform float sheen = 0.0;
uniform float edge_irregularity : hint_range(0.0, 2.0) = 1.0;
uniform bool wet_reflections = true;
uniform float droplets : hint_range(0.0, 2.0) = 1.0;

instance uniform float progress = 0.0;
instance uniform float fade = 1.0;
instance uniform float seed = 0.0;
instance uniform float age = 0.0;      // 0 fresh .. 1 dried

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float v = UV2.x;
	float pot = UV2.y;
	bool riser = COLOR.a > 0.5;
	// noise coordinates on the surface: across the floor, or down a step face
	vec2 p = riser ? vec2(wpos.x + wpos.z, wpos.y * 1.6) : wpos.xz;
	float n1 = texture(noise_tex, p * 0.75 + vec2(seed, seed * 1.37)).r;
	float n2 = texture(noise_tex, p * 3.3 + vec2(seed * 2.1, seed)).r;
	float n3 = texture(noise_tex, p * 9.7 + vec2(seed * 0.7, seed * 3.1)).r;
	// how long the blood has been here, with a softly wandering front
	float e = progress - v + ((n1 - 0.5) * 0.2 + (n2 - 0.5) * 0.07) * edge_irregularity;
	if (riser) {
		// runs down the face: thin vertical lanes, not a sheet
		float along = wpos.x + wpos.z;
		float lane = texture(noise_tex, vec2(along * 4.0 + seed, wpos.y * 0.3)).r * 0.55
			+ texture(noise_tex, vec2(along * 13.0 + seed * 1.9, wpos.y * 0.6)).r * 0.45;
		// a few thin runs, each stopping at its own length down the face
		e -= smoothstep(0.44, 0.56, lane) * 0.7 + (1.0 - lane) * 0.15;
	}
	float drop = 0.0;
	if (e < 0.0) {
		// a few separate droplets just past the front
		drop = step(-0.09, e) * smoothstep(0.78, 0.8, n3 + e * 2.2) * step(0.01, droplets) * step(0.5, 1.0 - float(riser));
		if (drop <= 0.0) {
			discard;
		}
	}
	float cover = max(smoothstep(0.0, 0.025, e), drop);
	// thickness: deeper toward the middle and the longer it has been pooling
	float thick = clamp(e * 2.4, 0.0, 1.0) * (0.3 + 0.7 * pot) * (0.8 + 0.4 * n1);
	thick = max(thick, drop * 0.25);
	vec3 col = mix(thin_color, deep_color, smoothstep(0.0, 0.65, thick));
	// it dries from the thin edges in, going brown and dull
	float dry = age * (1.0 - 0.6 * smoothstep(0.2, 0.9, thick));
	col = mix(col, dry_color * (0.8 + 0.4 * n2), dry * 0.75);
	if (sheen > 0.0) {
		float film = n1 * 9.0 + n2 * 4.0 + dot(VIEW, NORMAL) * 4.0;
		vec3 rainbow = 0.5 + 0.5 * cos(film + vec3(0.0, 2.1, 4.2));
		col += rainbow * sheen * 0.012 * (1.0 - thick * 0.7);
	}
	ALBEDO = col;
	float r = mix(0.32, 0.09, smoothstep(0.0, 0.6, thick));
	r = mix(r, 0.6, dry);
	if (!wet_reflections) {
		r = max(r, 0.55);
	}
	ROUGHNESS = r;
	SPECULAR = 0.5;
	METALLIC = 0.0;
	// a rounded lip where thick liquid meets the floor: bend the normal with
	// the slope of the front across the surface
	float lip = 1.0 - smoothstep(0.0, 0.06, e);
	vec3 dpx = dFdx(wpos);
	vec3 dpy = dFdy(wpos);
	float dex = dFdx(e);
	float dey = dFdy(e);
	vec3 r1 = cross(dpy, wnrm);
	vec3 r2 = cross(wnrm, dpx);
	float det = dot(dpx, r1);
	vec3 grad = (r1 * dex + r2 * dey) / (abs(det) > 1e-9 ? det : 1e-9);
	vec3 nw = normalize(wnrm - grad * lip * 0.01 * (1.0 - float(riser)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// thin edges are a little see-through
	ALPHA = cover * mix(0.72, 0.97, smoothstep(0.0, 0.45, thick)) * fade;
}
