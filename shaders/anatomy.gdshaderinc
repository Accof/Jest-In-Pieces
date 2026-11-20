// Exposed anatomy (ClownAnatomy): bone, cartilage, organs. Included by
// anatomy.gdshader (organs: front faces) and anatomy_bone.gdshader (bone:
// both faces, so a skull broken open shows its inside).
//
// The meshes have no UVs: the surface textures (art/anatomy/tex, seamless)
// are projected from three directions in the mesh's own space, so they stay
// on it as the body moves. Bump from the height channel; roughness from its
// second channel, wetter and bloodier round the hole.
//
// Only ever drawn round a blown-out hole in the body (the same wounds the
// body shader cuts its holes with, in the body's rest space): what is not
// near a hole is not drawn at all, so nothing shows through intact skin or
// cloth whatever the body's shape. Bone (`breaks`) is broken away under the
// hole itself, with a ragged edge.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D hr_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float tex_scale = 16.0;          // texture repeats a metre
uniform float bump = 1.0;
uniform float rough_mul = 1.0;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;
uniform mat4 to_rest;                    // this mesh's points -> the body's rest space
uniform int wound_count = 0;
uniform vec4 wounds[16];                 // xyz rest-space position, w radius
uniform vec4 wound_fx[16];               // w: blown-out hole radius (0: an ordinary wound)
uniform float reveal = 2.4;              // drawn within this many hole radii of a hole...
uniform float reveal_min = 0.08;         // ...and never less than this (m)
uniform bool breaks = false;             // bone: broken away under the hole
uniform bool show_all = false;           // drawn whole: a piece that sticks out of a stump or a break
uniform float break_k = 0.95;            // how much of the hole's radius the bone is gone in
uniform vec3 blood_color : source_color = vec3(0.24, 0.008, 0.012);
uniform float blood_amount = 0.35;       // a film of blood over everything inside

varying vec3 obj_pos;
varying vec3 obj_nrm;
varying vec3 rest_pos;

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
	rest_pos = (to_rest * vec4(VERTEX, 1.0)).xyz;
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

void fragment() {
	// near a hole? how near its middle? (and, for bone, inside the break?)
	bool seen = false;
	float close = 0.0;           // 1 at a hole's middle, 0 at its reach
	float edge = 0.0;            // the broken rim of bone
	for (int i = 0; i < wound_count; i++) {
		float hole = wound_fx[i].w;
		if (hole <= 0.0) {
			continue;
		}
		float d = distance(rest_pos, wounds[i].xyz);
		float reach = max(hole * reveal, reveal_min);
		if (d < reach) {
			seen = true;
			close = max(close, 1.0 - d / reach);
		}
		if (breaks) {
			float jag = 0.7 + 0.45 * noise3(rest_pos * 55.0 + wound_fx[i].z) + 0.2 * noise3(rest_pos * 160.0);
			float r = hole * break_k * jag;
			if (d < r) {
				discard;
			}
			edge = max(edge, 1.0 - smoothstep(r, r + 0.012, d));
		}
	}
	if (!seen && !show_all) {
		discard;
	}
	vec3 n = normalize(abs(obj_nrm) + 1e-4);
	vec3 w = pow(n, vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = obj_pos * tex_scale;
	vec3 alb = tri(albedo_tex, p, w).rgb * tint;
	vec4 hr = tri(hr_tex, p, w);
	// bump from the height channel, in view space
	float h = hr.r;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	// (the height channel spans about 1.5 mm of relief at bump 1)
	NORMAL = normalize(abs(det) * NORMAL - bump * 0.0015 * grad);
	// blood: a film everywhere, heavier and fresher toward the hole and on a broken edge
	float film = blood_amount * (0.55 + 0.45 * noise3(rest_pos * 40.0));
	float soak = clamp(film + close * close * 0.6 + edge * 0.8, 0.0, 1.0);
	alb = mix(alb, blood_color * (0.8 + 0.4 * noise3(rest_pos * 90.0)), soak * 0.85);
	// the inside face of broken bone: darker (marrow, blood)
	if (!FRONT_FACING) {
		alb *= 0.55;
		NORMAL = -NORMAL;
	}
	ALBEDO = alb;
	ROUGHNESS = clamp(hr.g * rough_mul - soak * 0.3, 0.08, 1.0);
	SPECULAR = specular_amount;
}
