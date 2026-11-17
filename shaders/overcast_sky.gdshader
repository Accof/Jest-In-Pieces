shader_type sky;
// A continuous overcast: a heavy grey ceiling with layered cloud forms,
// darker bellies and paler seams, lighter toward a hazy horizon. No sun disc.
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 zenith : source_color = vec3(0.44, 0.465, 0.5);
uniform vec3 horizon : source_color = vec3(0.68, 0.685, 0.69);
uniform vec3 belly : source_color = vec3(0.33, 0.34, 0.37);
uniform vec3 ground : source_color = vec3(0.3, 0.285, 0.265);
uniform float energy = 1.0;
uniform float drift = 0.004;

void sky() {
	vec3 d = EYEDIR;
	if (d.y < 0.0) {
		COLOR = mix(horizon, ground, smoothstep(0.0, 0.25, -d.y)) * energy;
	} else {
		vec2 p = d.xz / (d.y + 0.12);
		float t = AT_CUBEMAP_PASS ? 0.0 : TIME * drift;
		float a = texture(noise_tex, p * 0.09 + vec2(t, t * 0.3)).r;
		float b = texture(noise_tex, p * 0.23 + vec2(-t * 1.7, t)).g;
		float c = texture(noise_tex, p * 0.6 + vec2(t * 2.3, -t)).b;
		float cloud = a * 0.6 + b * 0.3 + c * 0.1;
		vec3 col = mix(zenith, belly, smoothstep(0.42, 0.75, cloud));
		col = mix(col, horizon * 1.05, smoothstep(0.62, 0.8, 1.0 - cloud) * 0.35);   // paler seams
		col = mix(horizon, col, smoothstep(0.0, 0.35, d.y));                          // haze toward the horizon
		COLOR = col * energy;
	}
}
