shader_type canvas_item;

// How it works:
// - TEXTURE supplies one streamed chunk's opaque/cleared terrain mask.
// - Optional authored fill art and the layer tint establish the base color.
// - World-space value noise adds continuous broad and fine dirt variation.
// - One bounded rock candidate per grid cell adds rounded, rotated inclusions.
// - Shared world-space bedding fades in as strata become deeper.
// - The mask affects output alpha only; this shader never changes terrain logic.
// - All work is loop-free and constant per fragment for GL Compatibility/web.

// Optional seamless artwork. When disabled, the layer starts from white so its
// authored tint becomes the complete base color.
uniform sampler2D fill_texture : source_color, repeat_enable;
uniform bool use_fill_texture = false;
uniform vec4 layer_tint : source_color = vec4(1.0);

// The renderer supplies the chunk's terrain-space rectangle. Reconstructing a
// world position prevents patterns from restarting at every streamed chunk.
uniform vec2 world_origin = vec2(0.0);
uniform vec2 chunk_world_size = vec2(1024.0, 512.0);

// World-space period of optional fill art, independent of the mask resolution.
uniform vec2 fill_texture_world_size = vec2(256.0);

// Per-stratum procedural controls authored by TerrainLayerProfile.
// dirt_detail_scale controls fine dirt and rock spacing, while the broad dirt
// and bedding periods below remain shared so exposed layer rims still align.
uniform bool use_strata_texture = false;
uniform float dirt_detail_scale = 52.0;

// RGB is the darker dirt/rock detail color. Alpha is intentionally used as
// detail blend strength; final transparency still comes from the terrain mask.
uniform vec4 dirt_detail_color : source_color = vec4(0.36, 0.22, 0.15, 0.69);

// Expected authored ranges:
// - dirt_variance_strength: surface brightness variation, normally 0.0-0.2.
// - rock_density: probability that the current grid cell contains a rock.
// - rock_detail_strength: blend strength of present rocks.
// - stratum_depth: normalized layer index, where 0 is surface and 1 is deepest.
uniform float dirt_variance_strength = 0.15;
uniform float rock_density = 0.23;
uniform float rock_detail_strength = 0.55;
uniform float stratum_depth = 0.0;

// Shared world scales keep dirt and bedding aligned across cutaway rims.
// The two ratios derive smaller detail grids from each layer's authored scale.
const float BROAD_DIRT_SCALE = 64.0;
const float BEDDING_PERIOD = 90.0;
const float ROCK_GRID_SCALE = 0.58;
const float FINE_DIRT_SCALE = 0.28;

// Returns a repeatable pseudo-random value for a 2D cell without sampling a
// noise texture. Different constant offsets at call sites decorrelate the
// generated center, size, aspect, and presence values.
float dirt_hash(vec2 point) {
	vec3 point_hash = fract(vec3(point.xyx) * 0.1031);
	point_hash += dot(point_hash, point_hash.yzx + 33.33);
	return fract((point_hash.x + point_hash.y) * point_hash.z);
}

// Builds smooth 2D value noise from the four corners surrounding point.
// The cubic Hermite weight removes hard grid seams before bilinear blending.
float dirt_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend_weight = fract(point);
	blend_weight = blend_weight * blend_weight * (
		vec2(3.0) - 2.0 * blend_weight
	);

	// Interpolate both horizontal corner pairs, then combine them vertically.
	float top_noise = mix(
		dirt_hash(cell),
		dirt_hash(cell + vec2(1.0, 0.0)),
		blend_weight.x
	);
	float bottom_noise = mix(
		dirt_hash(cell + vec2(0.0, 1.0)),
		dirt_hash(cell + vec2(1.0, 1.0)),
		blend_weight.x
	);
	return mix(top_noise, bottom_noise, blend_weight.y);
}

// Applies all presentation-only geological detail to one already-tinted pixel.
// This remains separate from fragment() so mask composition stays easy to audit.
vec3 apply_strata_texture(vec3 surface_color, vec2 world_position) {
	// Protect every downstream division from an accidentally authored zero.
	float safe_detail_scale = max(dirt_detail_scale, 1.0);

	// Broad noise uses one shared world period so color variation crosses layer
	// rims continuously. Fine noise uses the per-layer scale so deeper strata
	// can become tighter and denser without breaking that larger continuity.
	float broad_noise = dirt_noise(world_position / BROAD_DIRT_SCALE);
	float fine_noise = dirt_noise(
		world_position / (safe_detail_scale * FINE_DIRT_SCALE)
			+ vec2(17.4, 4.8)
	);

	// Center both noise signals around zero. Broad shapes dominate; fine noise
	// breaks up otherwise-smooth patches at a deliberately lower contribution.
	float variance = (
		(broad_noise - 0.5) * 1.35
		+ (fine_noise - 0.5) * 0.45
	);
	vec3 textured_surface = surface_color * (
		1.0 + variance * dirt_variance_strength
	);

	// Divide terrain into a sparse detail grid. Exactly one possible rock is
	// evaluated per cell, avoiding the expensive neighbor search of Voronoi.
	vec2 rock_grid_position = world_position / (
		safe_detail_scale * ROCK_GRID_SCALE
	);
	vec2 rock_cell = floor(rock_grid_position);
	vec2 rock_local_position = fract(rock_grid_position);

	// The primary seed decides both whether a rock exists and its orientation.
	float rock_seed = dirt_hash(rock_cell + vec2(29.1, 53.7));

	// Keep centers within the middle 30% of a cell. Combined with the maximum
	// radius below, this prevents rocks from clipping against cell boundaries,
	// so no neighboring cells need to be evaluated.
	vec2 rock_center = mix(
		vec2(0.35),
		vec2(0.65),
		vec2(
			dirt_hash(rock_cell + vec2(7.3, 19.1)),
			dirt_hash(rock_cell + vec2(43.7, 3.9))
		)
	);
	vec2 rock_delta = rock_local_position - rock_center;

	// Rotate every rock independently. The ellipse aspect varies from nearly
	// circular to visibly oval, making the rotation useful without angular art.
	float rock_angle = rock_seed * 6.2831853;
	float angle_cosine = cos(rock_angle);
	float angle_sine = sin(rock_angle);
	vec2 rotated_rock_delta = vec2(
		angle_cosine * rock_delta.x - angle_sine * rock_delta.y,
		angle_sine * rock_delta.x + angle_cosine * rock_delta.y
	);
	float rock_aspect = mix(
		0.62,
		1.0,
		dirt_hash(rock_cell + vec2(11.7, 71.3))
	);
	rotated_rock_delta.x /= rock_aspect;

	// Elliptical distance creates the rounded silhouette. Radius remains small
	// enough to stay inside the center bounds described above.
	float rock_distance = length(rotated_rock_delta);
	float rock_size = mix(
		0.10,
		0.23,
		dirt_hash(rock_cell + vec2(5.2, 61.4))
	);

	// Screen-space derivatives antialias rock edges. The minimum softness keeps
	// them stable when derivatives become tiny in browser/Compatibility builds.
	float rock_softness = max(
		fwidth(rock_distance),
		0.004
	);

	// smoothstep draws the rounded rock; step performs the density probability
	// test without a dynamic branch. Density 0 draws none and 1 draws every cell.
	float rock_detail = (
		1.0
		- smoothstep(
			rock_size,
			rock_size + rock_softness,
			rock_distance
		)
	) * step(1.0 - rock_density, rock_seed);

	// Bedding uses only world Y and the shared broad noise. Every layer therefore
	// follows the same gently warped sediment line instead of restarting it.
	float sediment_phase = abs(
		fract(
			world_position.y / BEDDING_PERIOD
				+ broad_noise * 0.22
		) - 0.5
	);
	float sediment_line = smoothstep(0.45, 0.5, sediment_phase);

	// Surface and subsoil stay dirt-led. Bedding begins past the halfway depth
	// point and reaches its authored maximum only on the deepest back wall.
	float bedding_strength = (
		smoothstep(0.5, 1.0, stratum_depth) * 0.22
	);

	// Rock and bedding contributions share the darker detail color. Its alpha
	// controls their authored strength, and the cap preserves some base tint so
	// neighboring strata do not collapse into one indistinguishable dark mass.
	float detail_mix = clamp(
		rock_detail
			* rock_detail_strength
			* dirt_detail_color.a
			+ sediment_line
				* bedding_strength
				* dirt_detail_color.a,
		0.0,
		0.85
	);
	return mix(
		textured_surface,
		dirt_detail_color.rgb,
		detail_mix
	);
}

// Composes optional art, tint, procedural strata detail, and the damage mask.
void fragment() {
	// Sprite TEXTURE is the renderer-generated terrain mask: opaque pixels are
	// solid presentation and transparent pixels are mined openings.
	float mask_alpha = texture(TEXTURE, UV).a;
	vec4 artwork = vec4(1.0);

	// Convert chunk-local UVs back into continuous terrain coordinates before
	// sampling either authored art or procedural detail.
	vec2 world_position = world_origin + UV * chunk_world_size;

	// Repeat optional fill art in world space. The safety clamp prevents invalid
	// profile sizes from dividing texture coordinates by zero.
	if (use_fill_texture) {
		vec2 safe_texture_size = max(
			fill_texture_world_size,
			vec2(1.0)
		);
		artwork = texture(fill_texture, world_position / safe_texture_size);
	}

	// Tint first so procedural variation always works from the layer's authored
	// palette, regardless of whether fill artwork is assigned.
	vec3 surface_color = artwork.rgb * layer_tint.rgb;
	if (use_strata_texture) {
		surface_color = apply_strata_texture(
			surface_color,
			world_position
		);
	}

	// Only alpha is cut by the streamed mask. Optional artwork alpha and layer
	// tint alpha are preserved, while RGB remains the fully shaded dirt color.
	COLOR = vec4(
		surface_color,
		artwork.a * layer_tint.a * mask_alpha
	);
}
