shader_type canvas_item;
render_mode unshaded;

varying float lobe_seed;
varying float lobe_phase;
varying float cloud_pressure;


// Passes each smoke support's motion values into the shared soft shape.
void vertex() {
	lobe_seed = INSTANCE_CUSTOM.r * 6.283185;
	lobe_phase = INSTANCE_CUSTOM.g;
	cloud_pressure = INSTANCE_CUSTOM.b;
}


// Softens and disturbs each support so overlapping quads read as one cloud.
void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float drift = TIME * 0.35 + lobe_phase;
	float horizontal_wobble = sin(
		centered_uv.y * 5.0 + lobe_seed + drift
	) * 0.09;
	float fine_wobble = sin(
		centered_uv.y * 11.0 - lobe_seed * 0.7 - drift * 0.6
	) * 0.035;
	centered_uv.x += (
		horizontal_wobble + fine_wobble
	) * (1.0 - abs(centered_uv.y));

	float edge_noise = sin(
		atan(centered_uv.y, centered_uv.x) * 7.0
			+ lobe_seed
			+ drift
	) * mix(0.03, 0.09, cloud_pressure);
	float distance_from_center = length(centered_uv);
	float density = 1.0 - smoothstep(
		0.9 + edge_noise,
		1.02 + edge_noise,
		distance_from_center
	);
	COLOR.a *= density;
}
