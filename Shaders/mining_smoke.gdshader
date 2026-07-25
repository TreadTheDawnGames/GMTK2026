shader_type canvas_item;
render_mode unshaded;

// How it works:
// - One MultiMesh quad per simulated lobe becomes one volume of drifting dust.
// - INSTANCE_CUSTOM carries the lobe's seed, churn phase, cloud pressure and
//   quad aspect. INSTANCE_COLOR carries the authored dust tone and its fade.
// - A domain-warped fBm field erodes the quad's soft ellipse into wisps that
//   churn upward, so overlapping lobes blend into one moving body of gas
//   instead of reading as the stacked hard discs this replaced.
// - The tone the gas is filled with is still quantised into flat bands, so the
//   dust keeps the game's drawn shading even though its silhouette is soft.
// The invariant is that every fragment stays loop-free and constant-cost: the
// browser export pays for exactly nine value-noise taps per dust pixel.

varying float lobe_seed;
varying float lobe_phase;
varying float cloud_pressure;
varying float quad_aspect;

// Silhouette. erosion is how deep the noise can bite into the ellipse and
// feather is how soft the resulting edge is; together they make the wisps.
uniform float erosion = 0.34;
uniform float feather = 0.34;
// World scale of the churn. detail_scale sets wisp size, warp_scale sets the
// size of the slow swirl that drags those wisps around.
uniform float detail_scale = 1.9;
uniform float warp_scale = 0.9;
uniform float warp_strength = 0.7;
// How fast the field climbs through the quad, and the extra climb a cloud
// pressurised by a fresh combo hit earns.
uniform float rise_speed = 0.34;
uniform float pressure_rise_bonus = 0.7;
// Flat tone bands, and how far the shading commits to them. Fully banded gas
// reads as cut paper, so this leans on the steps without landing hard on them.
uniform float tone_steps = 3.0;
uniform float band_blend = 0.72;
uniform float shade_gain = 0.74;
uniform float lit_gain = 1.03;

// Repeatable pseudo-random value for one noise cell, matching the hash the
// terrain shader uses so dust and dirt share a grain.
float dust_hash(vec2 point) {
	vec3 point_hash = fract(vec3(point.xyx) * 0.1031);
	point_hash += dot(point_hash, point_hash.yzx + 33.33);
	return fract((point_hash.x + point_hash.y) * point_hash.z);
}

// Smooth 2D value noise from the four corners surrounding point.
float dust_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = fract(point);
	blend = blend * blend * (vec2(3.0) - 2.0 * blend);
	float top = mix(
		dust_hash(cell),
		dust_hash(cell + vec2(1.0, 0.0)),
		blend.x
	);
	float bottom = mix(
		dust_hash(cell + vec2(0.0, 1.0)),
		dust_hash(cell + vec2(1.0, 1.0)),
		blend.x
	);
	return mix(top, bottom, blend.y);
}

// Three octaves of that noise. The falling weights are what give the gas both
// a large rolling body and the small torn edges on top of it.
float dust_fbm(vec2 point) {
	return dust_noise(point) * 0.54
		+ dust_noise(point * 2.13 + vec2(7.3, 19.7)) * 0.31
		+ dust_noise(point * 4.37 + vec2(31.1, 5.9)) * 0.15;
}

// Passes each lobe's simulation values into the shared gas field.
void vertex() {
	lobe_seed = INSTANCE_CUSTOM.r * 43.0;
	lobe_phase = INSTANCE_CUSTOM.g;
	cloud_pressure = INSTANCE_CUSTOM.b;
	// The owner packs width-over-height into 0..8 before dividing by eight, so
	// this recovers the real aspect of a lobe stretched to fill a tunnel
	// without ever handing the noise an unbounded value.
	quad_aspect = max(INSTANCE_CUSTOM.a * 8.0, 0.05);
}

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;

	// Sample the field in the quad's screen proportions. Without this a lobe
	// stretched wide to fill a tunnel smears its wisps into horizontal streaks.
	vec2 field_uv = vec2(centered_uv.x * quad_aspect, centered_uv.y);
	float rise = TIME * (
		rise_speed + cloud_pressure * pressure_rise_bonus
	) + lobe_phase;
	vec2 seed_offset = vec2(lobe_seed, lobe_seed * 1.7);

	// Warp the sampling position by another noise field before reading the
	// detail. That is what turns concentric noise into curling gas rather than
	// a static cloud texture scrolling upward behind a hole.
	vec2 warp_uv = field_uv * warp_scale
		+ seed_offset
		+ vec2(0.0, -rise * 0.55);
	// One octave is enough here: the swirl is deliberately low frequency, and
	// the detail read below is where the small structure comes from. Running
	// the full fBm on both warp axes cost nearly half this shader's noise taps
	// and changed nothing visible, which the web budget will not pay for.
	vec2 warp = vec2(
		dust_noise(warp_uv),
		dust_noise(warp_uv + vec2(23.7, 41.3))
	) - vec2(0.5);
	vec2 detail_uv = field_uv * detail_scale
		+ warp * warp_strength
		+ seed_offset * 1.31
		+ vec2(0.0, -rise);
	float field = dust_fbm(detail_uv);

	// Drag the density peak off the quad's centre with the swirl that is already
	// warping the detail. A clean radial falloff is what made the dust read as
	// concentric rings inside a lens; an off-centre one reads as a body of gas.
	vec2 drifted_uv = centered_uv + warp * 0.45;
	// Soft ellipse, then bitten into by the field. A pressurised cloud boils
	// harder, so a heavy combo's dust tears more than a single tap's does.
	// Reach slightly past the quad before the erosion trims it back, so the
	// dust fills the tunnel it was thrown into instead of floating in the
	// middle of it with a clear gap against both walls.
	float core = 1.12 - length(drifted_uv);
	float bite = erosion * mix(0.85, 1.25, clamp(cloud_pressure, 0.0, 1.0));
	// Bite the outside far harder than the middle. Eroding evenly hollows the
	// lobe out until the cloud is a handful of specks; concentrating it on the
	// rim leaves a solid body of dust wearing a torn edge, which is what makes
	// neighbouring lobes fuse into one volume instead of beading up.
	float edge_weight = smoothstep(0.1, 0.95, length(centered_uv));
	float density = core - (1.0 - field) * bite * mix(0.25, 1.15, edge_weight);
	float coverage = smoothstep(0.0, max(feather, 0.01), density);
	if (coverage <= 0.0) {
		discard;
	}

	// Light comes from above everywhere else in the scene, so it does here.
	// Tone follows the noise field rather than the radial density, because
	// shading by density paints the same concentric rings back on.
	float top_light = 0.5 - centered_uv.y * 0.5;
	float shading = clamp(top_light * 0.45 + field * 0.58, 0.0, 1.0);
	float safe_steps = max(tone_steps, 1.0);
	float banded_shading = floor(shading * safe_steps)
		/ max(safe_steps - 1.0, 1.0);
	shading = mix(shading, banded_shading, clamp(band_blend, 0.0, 1.0));

	COLOR = vec4(
		COLOR.rgb * mix(shade_gain, lit_gain, shading),
		COLOR.a * coverage
	);
}
