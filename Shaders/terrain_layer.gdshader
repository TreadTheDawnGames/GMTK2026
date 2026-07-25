shader_type canvas_item;

// How it works:
// - TEXTURE supplies one streamed chunk's opaque/cleared terrain mask.
// - Optional authored fill art and the layer tint establish the base color.
// - World-space value noise adds continuous broad and fine dirt variation.
// - One bounded rock candidate per grid cell adds rounded, rotated inclusions.
// - Shared world-space bedding fades in as strata become deeper.
// - The mask luminance carries fracture strokes while alpha carries cutouts.
// - The terrain mask affects only alpha; fracture art affects only shaded RGB.
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
// Multiplied into the rock under an authored crack stroke. A warm value keeps
// fractures inside the terrain palette; pure black would read as line art.
uniform vec4 fracture_shade_color : source_color = vec4(0.34, 0.25, 0.21, 1.0);

uniform float dirt_variance_strength = 0.15;
// Number of flat shading bands the dirt variation is quantised into. Zero
// leaves the original continuous gradient.
uniform float dirt_shade_steps = 4.0;
uniform float rock_density = 0.23;
uniform float rock_detail_strength = 0.55;
uniform float stratum_depth = 0.0;

// Cut-edge shading. Every stratum's mask is beveled against its own opening so
// the rims read as one connected rock face receding backward, instead of flat
// stacked cutouts. Reach is authored in world pixels and converted through
// chunk_world_size, so it is independent of mask resolution.
// Snaps the filtered mask back to a crisp cut edge instead of a soft ramp.
uniform bool sharpen_mask_edges = true;

uniform bool use_layer_edge_shading = true;
uniform float edge_shade_world_pixels = 6.0;
uniform float edge_shade_strength = 0.45;
uniform float edge_light_strength = 0.3;

// Surface dressing. Grass and the packed crust belong to the foreground
// stratum itself rather than to an overlay, so digging removes them for free:
// the grass is the terrain, and the terrain is what breaks first.
// The renderer enables this for layer zero only.
uniform bool use_surface_grass = false;
uniform float surface_world_y = 304.0;
// How far either side of the original ground line grass can grow at all.
uniform float surface_band_world_px = 36.0;
uniform float grass_height_world_px = 13.0;
// Drawn grass sheet. Each cell along the ground samples a random horizontal
// window of it, so the scattered tufts and the gaps between them come straight
// from the art instead of being generated.
// Horizontal atlas of clumps cut from the drawn sheet, every one bottom-aligned
// in its cell. That alignment is what guarantees nothing floats: v = 1 is the
// cell's bottom edge, and the strip maps v = 1 onto the ground line.
uniform sampler2D grass_texture : source_color, filter_linear;
uniform bool use_grass_texture = false;
uniform int grass_clump_count = 6;
// One atlas cell's width over its height, so clumps keep their drawn shape.
uniform float grass_cell_aspect = 0.461;
uniform float grass_cell_world_px = 16.0;
// How far below the ground line the mask is probed to decide grass survives.
uniform float grass_support_probe_px = 4.0;
// Packed earth on the exposed top of the surface, in place of the old overlay.
uniform float crust_depth_world_px = 10.0;
uniform vec4 crust_color : source_color = vec4(0.46, 0.42, 0.36, 1.0);
uniform float crust_strength = 0.5;

// Darkens a solid pixel that sits near its own layer's cut edge and lights the
// upward-facing lip, using four mask taps to find which way the edge faces.
// Depth deepens the contact shadow, so rims further back sit further back.
vec3 apply_edge_shading(vec3 surface_color, vec4 neighbor_alpha) {
	// How much cleared space surrounds this pixel. Interior rock reads 0.
	float openness = 1.0 - dot(neighbor_alpha, vec4(0.25));

	// Contact shadow into the rock, strengthened on deeper strata.
	float contact_shadow = openness
		* edge_shade_strength
		* mix(1.0, 1.45, clamp(stratum_depth, 0.0, 1.0));
	surface_color *= 1.0 - clamp(contact_shadow, 0.0, 0.9);

	// Open above and solid below means this is a top-facing lip catching light.
	float upward_lip = clamp(
		neighbor_alpha.y - neighbor_alpha.x,
		0.0,
		1.0
	);
	return surface_color * (1.0 + upward_lip * edge_light_strength);
}

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

// Grass helpers. Godot will not let a user function take the built-in TEXTURE
// sampler, so the terrain-mask tap stays in fragment(); the grass sheet is its
// own uniform and can be sampled here.

// How much grass this row may grow at all, fading out away from the ground line.
float surface_grass_band(vec2 world_position) {
	return 1.0 - smoothstep(
		surface_band_world_px,
		surface_band_world_px * 1.6,
		abs(world_position.y - surface_world_y)
	);
}

// Samples one drawn clump for a point in the strip above the ground line.
// Each cell along the ground picks its own clump and jitters it inside the
// cell, so the spacing never reads as a ruled grid. Returns a transparent
// sample outside the clump, which is what leaves the gaps between tufts.
vec4 sample_surface_grass(vec2 world_position) {
	float cell_width = max(grass_cell_world_px, 1.0);
	float cell = floor(world_position.x / cell_width);
	float local_x = fract(world_position.x / cell_width) * cell_width;

	float strip_height = max(grass_height_world_px, 1.0);
	float clump_width = strip_height * max(grass_cell_aspect, 0.01);
	float slack = max(cell_width - clump_width, 0.0);
	float clump_left = slack * dirt_hash(vec2(cell, 11.0));
	float clump_u = (local_x - clump_left) / clump_width;
	if (clump_u < 0.0 || clump_u > 1.0) {
		return vec4(0.0);
	}

	// v = 1 is the atlas cell's bottom edge, which is the clump's base, and it
	// maps exactly onto surface_world_y. A blade can never start mid-air.
	float strip_v = (
		world_position.y - (surface_world_y - strip_height)
	) / strip_height;
	if (strip_v < 0.0 || strip_v > 1.0) {
		return vec4(0.0);
	}

	float clump_count = float(max(grass_clump_count, 1));
	float clump_index = min(
		floor(dirt_hash(vec2(cell, 3.0)) * clump_count),
		clump_count - 1.0
	);
	return texture(
		grass_texture,
		vec2((clump_index + clump_u) / clump_count, strip_v)
	);
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

	// Everything else in the game is drawn as flat fills with hard shading
	// steps, so the dirt is quantised to a few bands rather than left as a
	// continuous ramp, which read as airbrush behind the inked characters.
	// Zero steps keeps the original smooth gradient.
	if (dirt_shade_steps >= 1.0) {
		variance = floor(
			variance * dirt_shade_steps + 0.5
		) / dirt_shade_steps;
	}
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

	// Two angular harmonics chip the ellipse into a stone instead of a printed
	// dot, which is what a perfect circle reads as beside inked character art.
	// The largest possible result is 0.23 * 1.25, still inside the 0.35 the
	// center bounds above reserve, so a rock still cannot cross its own cell.
	float rock_bearing = atan(rotated_rock_delta.y, rotated_rock_delta.x);
	rock_size *= 1.0
		+ 0.16 * sin(rock_bearing * 3.0 + rock_seed * 21.4)
		+ 0.09 * sin(rock_bearing * 5.0 - rock_seed * 37.1);

	// Screen-space derivatives antialias rock edges. The minimum softness keeps
	// them stable when derivatives become tiny in browser/Compatibility builds.
	float rock_softness = max(
		fwidth(rock_distance),
		0.004
	);

	// smoothstep draws the rounded rock; step performs the density probability
	// test without a dynamic branch. Density 0 draws none and 1 draws every cell.
	float rock_present = step(1.0 - rock_density, rock_seed);
	float rock_detail = (
		1.0
		- smoothstep(
			rock_size,
			rock_size + rock_softness,
			rock_distance
		)
	) * rock_present;

	// The characters are drawn as flat fills inside a darker outline, so an
	// inclusion carries its own edge band rather than fading off evenly.
	float rock_outline_width = rock_size * 0.22;
	float rock_outline = rock_detail * smoothstep(
		rock_size - rock_outline_width - rock_softness,
		rock_size - rock_outline_width,
		rock_distance
	);

	// Bedding uses only world Y and the shared broad noise. Every layer therefore
	// follows the same gently warped sediment line instead of restarting it.
	// The warp has to be worth more than a fraction of the period or the band
	// arrives as a ruled horizontal line across the back wall rather than a
	// sediment seam following the ground.
	float sediment_phase = abs(
		fract(
			world_position.y / BEDDING_PERIOD
				+ broad_noise * 0.65
		) - 0.5
	);
	float sediment_line = smoothstep(0.45, 0.5, sediment_phase);

	// Surface and subsoil stay dirt-led. Bedding begins past the halfway depth
	// point and reaches its authored maximum only on the deepest back wall,
	// where those seams are the main thing telling the player they are looking
	// at a wall standing behind the tunnel rather than into empty dark.
	float bedding_strength = (
		smoothstep(0.35, 1.0, stratum_depth) * 0.75
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
	vec3 detailed_surface = mix(
		textured_surface,
		dirt_detail_color.rgb,
		detail_mix
	);

	// The inclusion's own outline goes on last so it stays readable no matter
	// how far the fill above it was capped.
	return mix(
		detailed_surface,
		dirt_detail_color.rgb * 0.4,
		clamp(rock_outline * rock_detail_strength * 0.8, 0.0, 1.0)
	);
}

// Composes optional art, tint, procedural strata detail, and the damage mask.
void fragment() {
	// Sprite TEXTURE packs fracture darkness in luminance and terrain solidity
	// in alpha, so both values share one streamed texture and one upload.
	vec4 packed_mask = texture(TEXTURE, UV);
	float mask_alpha = packed_mask.a;
	float fracture_value = packed_mask.r;
	vec4 artwork = vec4(1.0);

	// The mask is authored below world resolution and drawn with linear
	// filtering, so every cut arrives as a wide soft ramp. Re-thresholding it
	// against its own screen-space gradient collapses that ramp back to a
	// single antialiased pixel: the organic silhouette survives, the blur does
	// not. Neighbour taps below intentionally keep reading the raw ramp,
	// because the bevel wants the gradual falloff this removes here.
	if (sharpen_mask_edges) {
		float alpha_softness = max(fwidth(mask_alpha), 0.0001);
		mask_alpha = smoothstep(
			0.5 - alpha_softness,
			0.5 + alpha_softness,
			mask_alpha
		);
	}

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
	// Bevel this stratum against its own opening before the cracks go on, so
	// the rim shading reads as form and the strokes still sit on top of it.
	if (use_layer_edge_shading && mask_alpha > 0.0) {
		vec2 edge_step = vec2(max(edge_shade_world_pixels, 0.5))
			/ max(chunk_world_size, vec2(1.0));
		vec4 neighbor_alpha = vec4(
			texture(TEXTURE, UV - vec2(0.0, edge_step.y)).a,
			texture(TEXTURE, UV + vec2(0.0, edge_step.y)).a,
			texture(TEXTURE, UV - vec2(edge_step.x, 0.0)).a,
			texture(TEXTURE, UV + vec2(edge_step.x, 0.0)).a
		);
		surface_color = apply_edge_shading(
			surface_color,
			neighbor_alpha
		);
	}

	// A stroke tints the rock toward its own deep-earth tone instead of printing
	// neutral black over it, so a crack reads as this same material in shadow
	// rather than as ink sitting on top of the painting.
	surface_color = mix(
		surface_color,
		surface_color * fracture_shade_color.rgb,
		1.0 - fracture_value
	);

	// Only alpha is cut by the streamed mask. Optional artwork alpha and layer
	// tint alpha are preserved, while RGB remains the fully shaded dirt color.
	float final_alpha = artwork.a * layer_tint.a * mask_alpha;

	// Surface dressing, foreground stratum only. Grass grows out of this
	// layer's own top edge and the crust sits in its own top pixels, so a mined
	// opening takes both away with it without any extra bookkeeping.
	if (use_surface_grass) {
		if (mask_alpha < 0.5 && use_grass_texture) {
			float grass_band = surface_grass_band(world_position);
			if (grass_band > 0.0) {
				// Grass only survives where the ground just under the line is
				// still intact, so a mined opening takes it with the dirt.
				float support_alpha = texture(
					TEXTURE,
					UV + vec2(
						0.0,
						(surface_world_y + grass_support_probe_px
							- world_position.y)
							/ max(chunk_world_size.y, 1.0)
					)
				).a;
				vec4 blade = sample_surface_grass(world_position);
				float grass = blade.a * grass_band * step(0.5, support_alpha);
				if (grass > 0.0) {
					surface_color = blade.rgb;
					final_alpha = grass;
				}
			}
		} else {
			// Packed earth on the exposed top of the original ground line.
			float depth_below_surface = world_position.y - surface_world_y;
			float crust = step(-1.0, depth_below_surface) * (
				1.0 - smoothstep(
					0.0,
					max(crust_depth_world_px, 1.0),
					depth_below_surface
				)
			);
			surface_color = mix(
				surface_color,
				crust_color.rgb,
				clamp(crust * crust_strength, 0.0, 1.0)
			);
		}
	}

	COLOR = vec4(surface_color, final_alpha);
}
