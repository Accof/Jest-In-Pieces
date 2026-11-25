// Blood in flight (the blood overhaul's Phase C, 25 Nov 2026): the plume's
// strings and drops, and the drawn droplets of the CPU sim.
//
// Each sprite is a quad whose Y axis is its direction of travel (the
// particles align Y to velocity; the droplet MultiMesh sets it), drawn as a
// cylindrical billboard: the Y axis stays where physics put it and the X axis
// turns to face the camera, so a streak is a streak from every side. The
// sheet's alpha is the liquid's thickness: bright red where it is thin, near
// black where it is deep, with a specular lobe and a wet rim so it reads as
// liquid under the lanterns rather than as a red cut-out.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, skip_vertex_transform, specular_schlick_ggx, diffuse_lambert_wrap;

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform int frames_h = 4;
uniform int frames_v = 4;
// (25 Nov) the marks' displayed palette (see blood_run.gdshader): plain vec4
uniform vec4 deep = vec4(0.27, 0.050, 0.055, 1.0);
uniform vec4 thin = vec4(0.50, 0.110, 0.090, 1.0);
uniform float stretch = 1.0;       // extra length along the travel axis
uniform float alpha_scale = 1.0;
uniform float rim = 0.35;

varying vec2 frame_uv;
varying float thick;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float len = max(length(axis), 1e-5);
	vec3 ay = axis / len;
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - origin);
	vec3 ax = cross(ay, to_cam);
	float axl = length(ax);
	ax = axl > 1e-4 ? ax / axl : normalize(cross(ay, vec3(0.0, 0.0, 1.0)));
	vec3 n = normalize(cross(ax, ay));
	if (dot(n, to_cam) < 0.0) { n = -n; }
	vec3 world = origin + ay * (VERTEX.y * len * stretch) + ax * (VERTEX.x * w);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// the frame: INSTANCE_CUSTOM.z is the particle's animation offset (0..1),
	// or the custom data a MultiMesh sets
	int total = frames_h * frames_v;
	int f = clamp(int(INSTANCE_CUSTOM.z * float(total)), 0, total - 1);
	vec2 cell = vec2(float(f % frames_h), float(f / frames_h));
	frame_uv = (UV + cell) / vec2(float(frames_h), float(frames_v));
}

void fragment() {
	vec4 s = texture(sheet, frame_uv);
	thick = s.a;
	float a = smoothstep(0.04, 0.25, thick) * alpha_scale;
	// in flight the blood is thin and catches the light: red, going dark only in the thickest beads
	vec3 col = mix(thin.rgb, deep.rgb, smoothstep(0.45, 1.0, thick) * 0.6);
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = col + thin.rgb * fr * rim;
	// translucent: light from behind comes through, and it never goes black in a dark corner
	BACKLIGHT = thin.rgb * 0.7;
	EMISSION = col * 0.06;
	ALPHA = a;
	METALLIC = 0.0;
	ROUGHNESS = 0.22;
	SPECULAR = 0.6;
}
