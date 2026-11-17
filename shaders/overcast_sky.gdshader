shader_type sky;
// The storm sky over the Drowned Trenches: heavy, layered cloud that is
// brighter than anything below it. Dark blue-grey masses roll over paler
// grey openings, with a soft warm-grey light low toward the sun (behind the
// cloud) and the burning horizon. The clouds drift slowly. No sun disc, no
// rain, no lightning.
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 mass : source_color = vec3(0.17, 0.2, 0.245);       // the dark cloud bellies
uniform vec3 body : source_color = vec3(0.4, 0.43, 0.47);        // ordinary cloud
uniform vec3 opening : source_color = vec3(0.83, 0.82, 0.79);    // the paler gaps, lit from above
uniform vec3 warm : source_color = vec3(0.86, 0.72, 0.58);       // warm grey low toward the light
uniform vec3 horizon : source_color = vec3(0.55, 0.57, 0.6);     // the haze line
uniform vec3 ground : source_color = vec3(0.12, 0.12, 0.125);
uniform vec3 light_dir = vec3(-0.45, 0.32, -0.83);              // where the light is, behind the cloud
uniform float energy = 1.2;
uniform float drift = 0.006;
uniform float coverage = 0.5;                                   // more = fewer openings

float fbm(vec2 p, float t) {
	float a = texture(noise_tex, p * 0.011 + vec2(t, t * 0.4)).r;
	float b = texture(noise_tex, p * 0.029 + vec2(-t * 1.6, t * 0.7) + a * 0.15).g;
	float c = texture(noise_tex, p * 0.083 + vec2(t * 2.4, -t) + b * 0.2).g;
	float e = texture(noise_tex, p * 0.21 + vec2(t * 3.0, t)).b;
	return a * 0.5 + b * 0.28 + c * 0.15 + e * 0.07;
}

void sky() {
	vec3 d = EYEDIR;
	if (d.y < 0.0) {
		COLOR = mix(horizon * 0.8, ground, smoothstep(0.0, 0.2, -d.y)) * energy;
	} else {
		float t = AT_CUBEMAP_PASS ? 0.0 : TIME * drift;
		vec2 p = d.xz / (d.y + 0.3) * 6.0;   // flatter near the horizon: no streaks
		// warp the cloud field so it billows rather than tiles
		vec2 w = vec2(texture(noise_tex, p * 0.008 + 0.31).r, texture(noise_tex, p * 0.008 + 0.77).g) - 0.5;
		float dens = fbm(p + w * 30.0, t);
		// heavier overhead, breaking up toward the horizon
		dens += (smoothstep(0.1, 0.8, d.y) - 0.4) * 0.12;
		float thick = smoothstep(coverage - 0.2, coverage + 0.22, dens);
		// light through the cloud: openings bright, thick masses dark
		float toward = max(dot(normalize(d), normalize(light_dir)), 0.0);
		vec3 lit = mix(opening, warm, smoothstep(0.55, 0.95, toward) * 0.6);
		vec3 col = mix(lit, body, smoothstep(0.0, 0.45, thick));
		col = mix(col, mass, smoothstep(0.45, 1.0, thick));
		// silver edges where the openings meet the masses, toward the light
		col += opening * 0.25 * smoothstep(0.25, 0.45, thick) * (1.0 - smoothstep(0.45, 0.7, thick)) * toward;
		// a glow low over the horizon toward the light and the fires
		float low = 1.0 - smoothstep(0.0, 0.25, d.y);
		col = mix(col, mix(horizon, warm, toward * 0.7), low * 0.75);
		COLOR = col * energy;
	}
}
