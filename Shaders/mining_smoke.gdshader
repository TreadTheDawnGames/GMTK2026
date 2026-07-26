shader_type canvas_item;
render_mode unshaded;

// How it works:
// - One MultiMesh quad per simulated lobe becomes one volume of drifting dust.
// - The noise domain is measured in world pixels recovered from MODEL_MATRIX,
//   so a wisp keeps its physical size while the lobe behind it grows, stretches
//   to fill a tunnel, or drifts. A quad-relative domain re-scaled the whole
//   field every time the lobe changed shape, which is what made a rising cloud
//   swim and shimmer instead of holding its form.
// - INSTANCE_CUSTOM carries the lobe's seed and how much life it has left.
//   INSTANCE_COLOR carries the authored dust tone and its fade. Cloud pressure
//   is one value for the whole cloud, so it arrives as a uniform.
// - A domain-warped fBm field erodes the quad's soft body into wisps that
//   churn upward, so overlapping lobes blend into one moving body of gas
//   instead of reading as the stacked hard discs this replaced. That body
//   flattens against rock the owner reports the puff is touching, so dust in a
//   shaft fills it rather than floating inside it as a ball.
// - The tone the gas is filled with is still quantised into flat bands, so the
//   dust keeps the game's drawn shading even though its silhouette is soft.
// The invariant is that every fragment stays loop-free and constant-cost: the
// browser export pays for exactly five value-noise taps per dust pixel.

varying float lobe_seed;
varying float life_ratio;
varying float wall_confinement;
varying vec2 quad_half_size;

// Size in world pixels of one cell of the base noise octave. This is the knob
// that sets how big a wisp is; because the domain is measured in world pixels,
// the answer no longer depends on how large the lobe drawing it happens to be.
uniform float feature_size = 72.0;
// Silhouette. erosion is how deep the noise can bite into the body and
// feather is how soft the resulting edge is; together they make the wisps.
uniform float erosion = 0.62;
uniform float feather = 0.34;
// How far the body reaches sideways before it starts falling off. The owner
// already sizes each quad to the rock on either side, so pushing the body out
// to the quad's edges is what makes dust conform to an opening instead of
// sitting inside it as a ball. This flattens the horizontal profile only: the
// top and bottom stay rounded, because nothing up there is holding the gas in.
// At 0.0 this is exactly the ellipse it replaced.
uniform float wall_conformity : hint_range(0.0, 1.0) = 0.6;
// World height over which the overhead light falls off. Measuring this in world
// pixels rather than across the quad keeps a puff squashed flat along a tunnel
// from compressing a whole light ramp into its short height, which turned the
// tone bands into horizontal stripes across it.
uniform float light_span = 120.0;
// World scale of the churn. detail_scale sets wisp size, warp_scale sets the
// size of the slow swirl that drags those wisps around.
uniform float detail_scale = 2.4;
uniform float warp_scale = 0.9;
uniform float warp_strength = 0.85;
// How fast the field climbs through the quad, and the extra climb a cloud
// pressurised by a fresh combo hit earns. The lobe itself already rises, so
// this only has to supply the churn inside it; running it fast enough to read
// as motion on its own is what made the dust boil.
uniform float rise_speed = 0.12;
uniform float pressure_rise_bonus = 0.28;
// Cloud-wide boil, written once per frame by MiningImpactSmoke.
uniform float cloud_pressure : hint_range(0.0, 1.0) = 0.0;
// Share of a puff's life spent coming apart, and how much deeper the field
// bites by the end of it. Dust that tears into wisps reads as dissipating gas;
// dust that only loses opacity reads as a ghost being switched off.
uniform float dissipation_portion = 0.55;
uniform float dissipation_erosion = 0.35;
// Flat tone bands, and how far the shading commits to them. Fully banded gas
// reads as cut paper, so this leans on the steps without landing hard on them.
uniform float tone_steps = 3.0;
uniform float band_blend = 0.72;
uniform float shade_gain = 0.66;
uniform float lit_gain = 1.2;

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
// cell_span is how much of the noise domain one screen pixel covers, so an
// octave whose cells have shrunk toward pixel size is faded out rather than
// sampled: below two pixels across, a cell can only alias, and that sparkle was
// most of what read as the dust shimmering. The weights are renormalised, so
// fading an octave thins the detail without also shrinking the silhouette.
float dust_fbm(vec2 point, float cell_span) {
	float second_weight = 0.31 * clamp(1.0 - cell_span * 4.26, 0.0, 1.0);
	float third_weight = 0.15 * clamp(1.0 - cell_span * 8.74, 0.0, 1.0);
	float total_weight = 0.54 + second_weight + third_weight;
	return (
		dust_noise(point) * 0.54
		+ dust_noise(point * 2.13 + vec2(7.3, 19.7)) * second_weight
		+ dust_noise(point * 4.37 + vec2(31.1, 5.9)) * third_weight
	) / total_weight;
}

// Quantises to flat bands while keeping each step one pixel wide. A bare floor
// over a moving noise field makes its band edges crawl from frame to frame,
// which reads as the whole cloud fizzing even when its silhouette is steady.
float banded(float value, float steps) {
	float scaled = value * steps;
	float step_index = floor(scaled);
	float step_width = clamp(fwidth(scaled), 0.0001, 1.0);
	float step_edge = smoothstep(
		1.0 - step_width,
		1.0,
		scaled - step_index
	);
	return (step_index + step_edge) / max(steps - 1.0, 1.0);
}

// Passes each lobe's simulation values into the shared gas field.
void vertex() {
	lobe_seed = INSTANCE_CUSTOM.r * 43.0;
	life_ratio = INSTANCE_CUSTOM.g;
	wall_confinement = INSTANCE_CUSTOM.b;
	// The owner scales a 2x2 quad by the lobe's half-extents, so the transform
	// columns are those half-extents in world pixels. Reading them here keeps
	// the noise domain tied to real size without spending custom data on it,
	// and covers aspect and absolute scale in one step.
	quad_half_size = vec2(
		length(MODEL_MATRIX[0].xy),
		length(MODEL_MATRIX[1].xy)
	);
}

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;

	// Sample in world pixels rather than in quad proportions. This is what lets
	// a lobe swell, or stretch wide to fill a tunnel, without dragging its
	// wisps along with it: the quad simply reveals more of a field whose
	// features are already the right size.
	vec2 field_uv = centered_uv * quad_half_size / max(feature_size, 1.0);
	float rise = TIME * (
		rise_speed + cloud_pressure * pressure_rise_bonus
	);
	vec2 seed_offset = vec2(lobe_seed, lobe_seed * 1.7);

	// Warp the sampling position by another noise field before reading the
	// detail. That is what turns concentric noise into curling gas rather than
	// a static cloud texture scrolling upward behind a hole. One octave is
	// enough: the extra octaves this used to carry only injected pixel-scale
	// jitter into the position the detail is read from, which sharpened the
	// aliasing the detail was already fighting.
	vec2 warp_uv = field_uv * warp_scale
		+ seed_offset
		+ vec2(0.0, -rise * 0.55);
	vec2 warp = vec2(
		dust_noise(warp_uv),
		dust_noise(warp_uv + vec2(23.7, 41.3))
	) - vec2(0.5);
	vec2 detail_uv = field_uv * detail_scale
		+ warp * warp_strength
		+ seed_offset * 1.31
		+ vec2(0.0, -rise);
	// Measured from the unwarped domain so the footprint stays smooth; the warp
	// only displaces the sample, it does not change how much field a pixel
	// covers.
	float cell_span = detail_scale * max(
		fwidth(field_uv.x),
		fwidth(field_uv.y)
	);
	float field = dust_fbm(detail_uv, cell_span);

	// Soft body, then bitten into by the field. A pressurised cloud boils
	// harder, so a heavy combo's dust tears more than a single tap's does, and
	// a puff running out of life tears hardest of all, so that it comes apart
	// into wisps on the way out instead of dimming as one solid shape.
	// Raising the horizontal term to a power holds the body out near full width
	// until it is close to the rock, then drops it, so a puff spread along a
	// tunnel presses flat against both walls while its top still billows. A
	// power of one is exactly 1.0 - length(centered_uv), so this stays on the
	// scale the erosion and feather below are tuned against.
	// Only a puff the rock is actually squeezing gets flattened. The owner
	// measures that when it scans for open space, so this reads the answer
	// rather than guessing from the quad's proportions: a shaft can be narrow
	// and tall, and a puff filling one is squeezed even though it is not wide.
	// Flattening unconfined puffs as well only sharpened their edges.
	float wall_power = 1.0
		+ clamp(wall_conformity, 0.0, 1.0)
		* 3.0
		* clamp(wall_confinement, 0.0, 1.0);
	float core = 1.0 - length(
		vec2(
			pow(abs(centered_uv.x), wall_power),
			centered_uv.y
		)
	);
	float dissipation = 1.0 - clamp(
		life_ratio / max(dissipation_portion, 0.01),
		0.0,
		1.0
	);
	float bite = erosion * mix(0.85, 1.25, clamp(cloud_pressure, 0.0, 1.0))
		+ dissipation * dissipation_erosion;
	float density = core - (1.0 - field) * bite;
	// The authored feather is in density units, so it thins to nothing in
	// screen terms once a lobe is small or far away. Holding it to at least a
	// pixel and a half keeps the edge resolved instead of crawling.
	float edge_width = max(feather, fwidth(density) * 1.5);
	float coverage = smoothstep(0.0, max(edge_width, 0.01), density);
	if (coverage <= 0.0) {
		discard;
	}

	// Light comes from above everywhere else in the scene, so it does here.
	// Measured down the world, not down the quad, so puffs of different heights
	// shade alike and a flat one is lit across a slice of the ramp rather than
	// across all of it.
	float top_light = clamp(
		0.5 - centered_uv.y * quad_half_size.y / max(light_span, 1.0),
		0.0,
		1.0
	);
	float shading = clamp(
		top_light * 0.58 + clamp(density, 0.0, 1.0) * 0.55,
		0.0,
		1.0
	);
	shading = mix(
		shading,
		banded(shading, max(tone_steps, 1.0)),
		clamp(band_blend, 0.0, 1.0)
	);

	COLOR = vec4(
		COLOR.rgb * mix(shade_gain, lit_gain, shading),
		COLOR.a * coverage
	);
}
