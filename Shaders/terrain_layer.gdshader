shader_type canvas_item;

#include "res://Shaders/ground_plane_light.gdshaderinc"

// How it works:
// - mask_tile_0..2 supply one continuous three-tile terrain mask.
// - Optional authored fill art and the layer tint establish the base color.
// - World-space value noise adds continuous broad and fine dirt variation.
// - Shared world-space bedding fades in as strata become deeper.
// - Three scatter passes place drawn rocks from one atlas, far to near, gated by
//   a shared cluster field so stones arrive in piles instead of a sprinkle.
// - One rare atlas pass embeds deterministic crystals in the foreground only.
// - The mask luminance carries fracture strokes while alpha carries cutouts.
// - Both are stored below world resolution, so both are re-thresholded here
//   against their own screen gradient: the cut stays a crisp edge and the
//   authored stroke stays a drawn line instead of a filtered smudge.
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
// The renderer splits the authoritative CPU mask into three 128-cell columns.
// Sixteen pixels/cell remains below WebGL's 4096 texture dimension and leaves a
// sampler spare. One-pixel neighbor gutters keep all boundary probes seamless.
uniform sampler2D mask_tile_0 : filter_linear;
uniform sampler2D mask_tile_1 : filter_linear;
uniform sampler2D mask_tile_2 : filter_linear;
// A successful predicted impact binds its small exact patch here while the
// authoritative full-width tile uploads behind it. Five target candidates are
// prepared offscreen, but only the winning patch is ever sampled by a layer.
uniform sampler2D impact_patch_texture : filter_linear;
uniform bool use_impact_patch = false;
uniform vec4 impact_patch_uv_rect = vec4(0.0);
// Mining reveals the finished mask through a short top-down compression front.
// During that bounded window the already-streamed mask is the source and the
// prepared patch is the destination. Preserving real prior pixels avoids the
// rectangular "solid white stamp" that repainted older holes and fracture ink.
// Settled terrain pays no extra branch and the final 16 px silhouette is exact.
uniform vec4 impact_crush_uv_rect = vec4(0.0);
// X is shader-uptime start, Y is duration; zero duration disables the branch.
// Packing them halves material updates compared with separate start/use values.
uniform vec2 impact_crush_timing = vec2(0.0);

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
// - rock_density: probability that one scatter cell contains a rock at all.
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

// Drawn rock scatter. rock_texture is a horizontal atlas of hand-drawn rocks,
// one per square cell, each centered inside transparent padding so a cell can be
// sampled without reaching its neighbor. The art is grayscale: its inked outline
// becomes rock_outline_color and its gray body picks a tone around
// rock_body_color, so a rock still belongs to this stratum's palette.
// Mip sampling keeps the atlas' black ink continuous when the far and mid
// passes minify it heavily, especially on the dense fourth stratum. This does
// not soften the terrain mask or add a texture read.
uniform sampler2D rock_texture : source_color, filter_linear_mipmap;
uniform bool use_rock_texture = false;
uniform int rock_atlas_count = 13;
uniform vec4 rock_body_color : source_color = vec4(0.44, 0.37, 0.31, 1.0);
uniform vec4 rock_outline_color : source_color = vec4(0.10, 0.08, 0.07, 1.0);

// World period of the field that decides where clusters sit, and the fraction of
// terrain those clusters cover. Coverage 1.0 scatters rocks everywhere and loses
// the clustering; the bare dirt between drifts is what makes a pile read as one.
uniform float rock_cluster_world_px = 176.0;
uniform float rock_cluster_coverage = 0.5;
// Presence multiplier for a cell outside every cluster, so bare dirt still
// carries the occasional loner instead of being perfectly clean.
uniform float rock_loner_scale = 0.22;
// Rock presence ramps linearly across the entire run. A bottom multiplier of
// 2.0 therefore produces 1.5x density at the halfway depth.
uniform float rock_run_world_px = 800000.0;
uniform float rock_bottom_density_multiplier = 2.0;
// Seats the near rocks on the dirt by printing their own displaced silhouette
// underneath them. This is the fourth and last atlas read; leave it off if a
// web build ever needs the sample back.
uniform bool use_rock_shadows = true;
uniform float rock_shadow_strength = 0.45;

// Rare foreground crystals. This pass is disabled on every buried stratum, so
// only layer zero pays its one atlas read. The shared terrain mask later clips
// each crystal with the intact rock, requiring no persistent spawn records.
uniform sampler2D foreground_gem_texture : source_color, filter_linear;
uniform bool use_foreground_gems = false;
uniform int foreground_gem_atlas_count = 5;
uniform float foreground_gem_cell_aspect = 0.5667;
uniform float foreground_gem_density = 0.008;
uniform float foreground_gem_cell_world_px = 96.0;
uniform float foreground_gem_minimum_height = 24.0;
uniform float foreground_gem_maximum_height = 42.0;

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
// A continuous ink band derived from the actual solid/open boundary. It uses
// the bevel's existing mask taps, so browser masks keep one solid authored
// outline without another texture sample or dependence on downscaled crack ink.
uniform float cut_outline_strength = 1.0;

// Authored crack strokes. The renderer prints them into the mask's luminance,
// but the mask is stored well below world resolution, so a stroke the artist
// inked several pixels thick arrives about one mask pixel wide and is then
// magnified with linear filtering into a grey smudge. These restore the drawn
// line at screen resolution: widen it by a world-space weight so it does not
// thin out as a hole is stamped larger, then re-threshold it against its own
// screen gradient the same way sharpen_mask_edges does for the cut itself.
// fracture_line_ink is this stratum's darkest authored stroke value, so zero
// disables the whole block for the strata that print no strokes at all.
uniform bool sharpen_fracture_lines = true;
uniform float fracture_line_ink = 0.0;
uniform float fracture_line_gain = 1.6;
uniform float fracture_line_weight_world_px = 0.5;

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
// The blades are drawn in flat daylight green. At the surface they stand
// against the same low sun as every other prop, so they take a cool shade and a
// warm tip light here, or the grass line reads as a sticker across the horizon.
uniform vec4 grass_shade_color : source_color = vec4(0.44, 0.46, 0.58, 1.0);
uniform float grass_shade_strength = 0.42;
uniform vec4 grass_tip_light_color : source_color = vec4(1.0, 0.80, 0.44, 1.0);
uniform float grass_tip_light_strength = 0.60;

// Trodden floor. The packed, walked-on ground at the top of a cutscene room's
// floor, falling off into the ordinary rock underneath it.
//
// This is the crust block above generalised: the crust is pinned to
// surface_world_y, the one ground line the whole run shares, and a cutscene room
// has its own floor hundreds of rows down. Everything here is keyed to a world y
// the caller supplies instead, so any room in the cutscene system can dress its
// own floor by pushing these five values and turning the flag on.
//
// Foreground stratum only, the same rule the crust follows: it is the layer the
// cast stand on, and a mined opening has to take the dressing away with the
// ground it removed.
uniform bool use_trodden_floor = false;
uniform float trodden_floor_world_y = 0.0;
// Held only until the first post-cutscene mining contact. While true the
// foreground closes filtered floor-edge pinholes so the buried stratum cannot
// peek above the 2.5D plane; once false, real damage-mask alpha deforms it.
uniform bool trodden_floor_seals_mask = false;
// How deep the packed band reaches before it starts giving way, and how far it
// then takes to fade out. Two numbers rather than one because a band that ends
// where it stops fading reads as a painted stripe.
uniform float trodden_depth_world_px = 10.0;
uniform float trodden_falloff_world_px = 26.0;
uniform vec4 trodden_color : source_color = vec4(0.30, 0.24, 0.19, 1.0);
uniform float trodden_strength = 0.55;
// How far the lower edge of the band wanders, in world pixels. Zero rules a
// straight line across the room, which is the one thing that would give it away
// as a shader rather than as ground.
uniform float trodden_edge_wander_world_px = 2.0;
// Grain within the band, so the walked surface is not a flat wash of colour.
uniform float trodden_grain_strength = 0.10;
uniform float trodden_grain_world_px = 26.0;
// How much the walked band clears the scattered rock off itself.
//
// This is what makes the treatment read as ground rather than as a tint. The
// strata pass scatters drawn rocks across every stratum at one strength; a
// surface people have been walking on does not keep its loose stones, so the
// ramp is handed to that pass and thins them out in step with it. At 1.0 the
// band is swept bare and the stones resume exactly where the transition fades,
// which is what puts a visible edge on the walking area without drawing a line.
uniform float trodden_rock_clearing = 0.85;
// The cafe's rendered ground-to-matte span is about 130 output pixels. Its
// authored 1.45 zoom and the viewport stretch turn that into about 67 world
// pixels, so extending the packed plane by 30px makes its full 66px depth meet
// the matte instead of exposing a bright vertical cave wall between them. The
// first 40px remain rough ground; the existing 26px falloff is its uneven edge.
// During the authored return to 1.0 zoom the same world depth reaches black
// slightly before the matte. That is intentional: the handback cannot reopen a
// lower-stratum seam while the surface is visually receding from the camera.
uniform float trodden_ground_extension_world_px = 84.0;
// The last part of the extended floor loses value into the exact matte colour.
// It does not brighten the shelf or add detail work: the already-computed grain
// only wanders the fade edge so it cannot read as another horizontal stripe.
uniform float trodden_matte_fade_world_px = 32.0;
uniform vec4 trodden_matte_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Unlike ordinary underground rock, an authored room floor has a visible top
// plane. It uses the surface shelf's lighting model with cave-local dimensions:
// a narrow warm plane, a longer dark turn into the front face, and a tight seam.
// Reusing the daylight dimensions made nearly fifty pixels of cave wall bright
// tan, which separated by value but read as a slab rather than as depth.
uniform float trodden_shelf_depth_world_px = 72.0;
uniform float trodden_shelf_plateau : hint_range(0.0, 1.0) = 0.35;
uniform vec4 trodden_shelf_light_color : source_color = vec4(
	0.52,
	0.40,
	0.30,
	1.0
);
uniform float trodden_shelf_light_strength = 0.16;
uniform float trodden_face_shade_depth_world_px = 148.0;
uniform float trodden_face_shade_strength = 0.52;
uniform float trodden_contact_depth_world_px = 4.0;
uniform float trodden_contact_strength = 0.55;

// Packed earth on the exposed top of the surface, in place of the old overlay.
uniform float crust_depth_world_px = 10.0;
uniform vec4 crust_color : source_color = vec4(0.46, 0.42, 0.36, 1.0);
uniform float crust_strength = 0.5;

// The ground the miner is standing on, between the grass and the cut face. It
// is the only horizontal plane in a side-on shot, so it is the one band facing
// the sky: lighting it warm and letting it fall away into the face below is
// what stops the surface reading as a wall he is standing in front of.
uniform float ground_shelf_depth_world_px = 44.0;
// Fraction of that depth the plane holds full light before it rolls off. A
// plane needs a far edge to read as a plane, so this deliberately does not
// fade from the ground line: it stays lit, then turns down.
uniform float ground_shelf_plateau : hint_range(0.0, 1.0) = 0.5;
uniform vec4 ground_shelf_light_color : source_color = vec4(
	1.0,
	0.78,
	0.52,
	1.0
);
uniform float ground_shelf_light_strength = 0.34;
// Shadow the shelf's far edge drops onto the cut face below it. This is the
// band that actually turns the corner; without it the light just fades out.
uniform float ground_face_shade_depth_world_px = 34.0;
uniform float ground_face_shade_strength = 0.24;
// Shade where the grass mat sits on the earth. Without it the blades look
// printed on the dirt instead of growing out of it.
uniform float ground_contact_depth_world_px = 6.0;
uniform float ground_contact_strength = 0.42;

// The same ground stack, moved down onto a cutscene room's own floor.
//
// The block above is pinned to surface_world_y, the one ground line the whole
// run shares, so every room below it drew its floor as flat rock and the shot
// lost the depth the surface gets for free. These key the identical masks to a
// floor line the caller supplies, reusing the tunables above rather than
// introducing a second ground look to keep in step with the first.
//
// Foreground stratum only, the same rule the crust and the trodden floor follow.
uniform bool use_cutscene_floor_plane = false;
uniform float cutscene_floor_world_y = 0.0;
// Bounce the lit floor throws up onto rock standing on it. A wall that runs
// continuously out of the floor otherwise meets it as a hard seam at exactly
// the place the 2.5D read has to hold; this is the transition band above that
// junction. Zero disables the branch, which is what keeps the surface path
// byte-identical to what it drew before this existed.
uniform float ground_wall_rise_world_px = 52.0;
uniform vec4 ground_wall_rise_color : source_color = vec4(
	0.86,
	0.64,
	0.42,
	1.0
);
uniform float ground_wall_rise_strength : hint_range(0.0, 1.0) = 0.22;

vec4 sample_streamed_terrain_mask(vec2 safe_uv) {
	vec2 tile_size = vec2(textureSize(mask_tile_0, 0));
	float tile_content_width = max(tile_size.x - 2.0, 1.0);
	float full_mask_width = tile_content_width * 3.0;
	float tile_index = min(floor(safe_uv.x * 3.0), 2.0);
	float tile_sample_x = safe_uv.x * full_mask_width
		- tile_index * tile_content_width
		+ 1.0;
	vec2 tile_uv = vec2(tile_sample_x / tile_size.x, safe_uv.y);
	if (tile_index < 1.0) {
		return texture(mask_tile_0, tile_uv);
	}
	if (tile_index < 2.0) {
		return texture(mask_tile_1, tile_uv);
	}
	return texture(mask_tile_2, tile_uv);
}

vec4 sample_terrain_mask(vec2 chunk_uv) {
	vec2 safe_uv = clamp(chunk_uv, vec2(0.0), vec2(1.0));
	vec4 mask_sample;
	bool sampled_patch = false;
	if (use_impact_patch) {
		vec2 patch_position = impact_patch_uv_rect.xy;
		vec2 patch_size = max(
			impact_patch_uv_rect.zw,
			vec2(0.000001)
		);
		vec2 patch_uv = (safe_uv - patch_position) / patch_size;
		vec2 patch_inside_low = step(vec2(0.0), patch_uv);
		vec2 patch_inside_high = step(patch_uv, vec2(1.0));
		float inside_patch = patch_inside_low.x * patch_inside_low.y
			* patch_inside_high.x * patch_inside_high.y;
		if (inside_patch > 0.5) {
			mask_sample = texture(
				impact_patch_texture,
				clamp(patch_uv, vec2(0.0), vec2(1.0))
			);
			sampled_patch = true;
		}
	}
	if (!sampled_patch) {
		mask_sample = sample_streamed_terrain_mask(safe_uv);
	}

	if (impact_crush_timing.y > 0.0) {
		vec2 crush_position = impact_crush_uv_rect.xy;
		vec2 crush_size = max(
			impact_crush_uv_rect.zw,
			vec2(0.000001)
		);
		vec2 crush_uv = (safe_uv - crush_position) / crush_size;
		vec2 crush_inside_low = step(vec2(0.0), crush_uv);
		vec2 crush_inside_high = step(crush_uv, vec2(1.0));
		float inside_crush = crush_inside_low.x * crush_inside_low.y
			* crush_inside_high.x * crush_inside_high.y;
		if (inside_crush > 0.5) {
			// TIME and Time.get_ticks_usec() share engine uptime. Modulo handles
			// Godot's default one-hour shader TIME rollover during a transition.
			float elapsed = mod(
				TIME - impact_crush_timing.x + 3600.0,
				3600.0
			);
			float crush_progress = clamp(
				elapsed / max(impact_crush_timing.y, 0.0001),
				0.0,
				1.0
			);
			float eased_progress = 1.0
				- pow(1.0 - crush_progress, 3.0);
			// The opening begins at the hammer-side top center and drives down
			// through the dirt. A derivative-soft front prevents the transition
			// from introducing a second pixel staircase around the final mask.
			vec2 crush_offset = vec2(
				(crush_uv.x - 0.5) * 0.95,
				(crush_uv.y - 0.04) * 0.58
			);
			float crush_distance = length(crush_offset);
			// Two cheap continuous folds keep the moving edge from reading as
			// a perfect digital ellipse. They run only inside the tiny active
			// patch and need no texture, allocation, or settled-frame work.
			crush_distance += sin(
				crush_uv.x * 27.0 + crush_uv.y * 11.0
			) * 0.018;
			crush_distance += sin(
				crush_uv.x * 9.0 - crush_uv.y * 23.0
			) * 0.012;
			float crush_front = mix(-0.04, 0.80, eased_progress);
			float crush_softness = max(fwidth(crush_distance), 0.001);
			float crush_reveal = smoothstep(
				crush_distance - crush_softness,
				crush_distance + crush_softness,
				crush_front
			);
			// The base tiles still contain the exact pre-hit mask while the
			// prepared patch is held. Blend only changed pixels from that mask
			// so the patch rectangle itself can never become visible.
			vec4 previous_mask_sample = mask_sample;
			if (sampled_patch) {
				previous_mask_sample = sample_streamed_terrain_mask(safe_uv);
			}
			mask_sample = mix(
				previous_mask_sample,
				mask_sample,
				crush_reveal
			);
		}
	}
	return mask_sample;
}

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

// The three scatter passes, near to far. Each owns a scaled and rotated copy of
// the layer's rock grid: the size ladder is what makes a cluster a pile of mixed
// stones, and the angles keep any two passes from sharing axes, which is what
// stops three overlaid grids from reading as a lattice.
const float ROCK_NEAR_CELL_SCALE = 1.0;
const float ROCK_MID_CELL_SCALE = 0.6;
const float ROCK_FAR_CELL_SCALE = 0.36;
const float ROCK_NEAR_GRID_ANGLE = 0.17;
const float ROCK_MID_GRID_ANGLE = 0.83;
const float ROCK_FAR_GRID_ANGLE = -0.55;
// Smaller stones are more numerous, so the far pass runs a higher share of its
// cells than the near pass does.
const float ROCK_NEAR_PRESENCE = 0.85;
const float ROCK_MID_PRESENCE = 1.0;
const float ROCK_FAR_PRESENCE = 1.15;
// Footprint half-size as a share of the pass cell, before the cluster bonus.
// The roll is biased toward the minimum, because a scatter of mostly small
// stones with the occasional larger one reads as ground rather than as a
// pattern, and a smaller rock also has more room to wander inside its cell.
const float ROCK_SIZE_MINIMUM = 0.15;
const float ROCK_SIZE_MAXIMUM = 0.33;
const float ROCK_SIZE_BIAS = 1.7;
// How much contrast a pass gives up into the dirt it is bedded in. The near pass
// keeps all of it; the far pass recedes far enough to sit behind the others.
const float ROCK_MID_DEPTH_FADE = 0.3;
const float ROCK_FAR_DEPTH_FADE = 0.58;

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

// Rock helpers.

// Broad field deciding where rock clusters exist at all: two octaves of the
// shared value noise, thresholded so high ground is inside a drift and
// everything under the threshold is bare dirt. Every scatter pass asks this in
// world space, which is why all three fire in the same patches and a cluster
// comes out as one pile rather than three unrelated sprinkles.
float rock_cluster_weight(vec2 world_position) {
	float cluster_period = max(rock_cluster_world_px, 16.0);
	float cluster_field = mix(
		dirt_noise(world_position / cluster_period + vec2(51.7, 8.3)),
		dirt_noise(
			world_position / (cluster_period * 0.42) + vec2(3.1, 67.9)
		),
		0.35
	);
	float cluster_threshold = 1.0 - clamp(rock_cluster_coverage, 0.0, 1.0);
	return smoothstep(
		cluster_threshold - 0.10,
		cluster_threshold + 0.18,
		cluster_field
	);
}

// Places and recolors one drawn rock for the cell this point falls in.
//
// A pass evaluates exactly one candidate in the cell containing world_position,
// so the cost is a single atlas read and no neighbor search. The invariant that
// buys that: a candidate's rotated footprint always stays inside its own cell
// (jitter + half_size * sqrt(2) <= 0.5), so no neighboring cell can own a rock
// that would reach this pixel, and no rock is ever cut off at a cell edge.
//
// Returns the shaded rock in rgb and its coverage in alpha. Calling it with
// world_position shifted returns the same silhouette displaced, which is how the
// contact shadow is drawn without a second code path.
vec4 sample_drawn_rock(
	vec2 world_position,
	vec3 dirt_surface,
	float cell_world_px,
	float grid_angle,
	float pass_seed,
	float presence_scale,
	float depth_fade
) {
	float safe_cell_px = max(cell_world_px, 2.0);
	vec2 pass_offset = vec2(pass_seed * 7.31, pass_seed * 3.17);
	float grid_cosine = cos(grid_angle);
	float grid_sine = sin(grid_angle);
	vec2 pass_position = vec2(
		grid_cosine * world_position.x - grid_sine * world_position.y,
		grid_sine * world_position.x + grid_cosine * world_position.y
	) / safe_cell_px + pass_offset;

	// Slide every row of the grid sideways by its own random amount. Cells stay
	// unit squares, so the containment invariant above is untouched, but columns
	// no longer line up between rows and the leftover lattice stops reading as
	// one. Only the rows move: shifting both axes would need the row index the
	// shift itself changes.
	float row_shift = dirt_hash(
		vec2(floor(pass_position.y), 3.3 + pass_seed)
	);
	vec2 grid_position = pass_position + vec2(row_shift, 0.0);
	vec2 rock_cell = floor(grid_position);
	vec2 cell_local = fract(grid_position);

	// Ask the cluster field at the cell's center rather than at this fragment,
	// so every pixel of one rock agrees about whether that rock exists. Asking
	// per fragment would let a cluster edge slice a stone in half.
	vec2 center_in_grid = (
		rock_cell + vec2(0.5) - pass_offset - vec2(row_shift, 0.0)
	) * safe_cell_px;
	vec2 cell_center_world = vec2(
		grid_cosine * center_in_grid.x + grid_sine * center_in_grid.y,
		grid_cosine * center_in_grid.y - grid_sine * center_in_grid.x
	);
	float cluster = rock_cluster_weight(cell_center_world);

	vec2 cell_seed = rock_cell + vec2(pass_seed);
	// Depth is measured from the cell center as well, for the same reason.
	float depth_gain = mix(
		1.0,
		max(rock_bottom_density_multiplier, 0.0),
		clamp(
			(cell_center_world.y - surface_world_y)
				/ max(rock_run_world_px, 1.0),
			0.0,
			1.0
		)
	);
	float presence_probability = clamp(
		rock_density
			* presence_scale
			* depth_gain
			* mix(rock_loner_scale, 1.0, cluster),
		0.0,
		1.0
	);
	// step performs the probability test without a dynamic branch.
	float rock_present = step(
		1.0 - presence_probability,
		dirt_hash(cell_seed + vec2(29.1, 53.7))
	);

	// Cluster cores also run larger, so a drift reads as heavier ground than the
	// loners scattered across bare dirt between drifts.
	float half_size = mix(
		ROCK_SIZE_MINIMUM,
		ROCK_SIZE_MAXIMUM,
		pow(dirt_hash(cell_seed + vec2(5.2, 61.4)), ROCK_SIZE_BIAS)
	) * mix(0.78, 1.0, cluster);

	// Free rotation. The drawn fills are flat, so a rock has no up and turning it
	// only varies the silhouette.
	float rock_angle = dirt_hash(cell_seed + vec2(11.7, 71.3)) * 6.2831853;
	float rock_cosine = cos(rock_angle);
	float rock_sine = sin(rock_angle);

	// Jitter is whatever room the rotated footprint leaves inside the cell. Using
	// this angle's real bound rather than the worst-case diagonal is what gives
	// most rocks somewhere to go: a small, nearly axis-aligned stone can wander
	// almost a third of a cell, and the grid it came from disappears with it.
	float rotated_bound = abs(rock_cosine) + abs(rock_sine);
	float jitter_reach = max(0.5 - half_size * rotated_bound, 0.0);
	vec2 rock_center = vec2(0.5) + jitter_reach * (
		vec2(
			dirt_hash(cell_seed + vec2(7.3, 19.1)),
			dirt_hash(cell_seed + vec2(43.7, 3.9))
		) * 2.0 - 1.0
	);
	vec2 rock_delta = cell_local - rock_center;
	vec2 rotated_delta = vec2(
		rock_cosine * rock_delta.x + rock_sine * rock_delta.y,
		rock_cosine * rock_delta.y - rock_sine * rock_delta.x
	);
	vec2 rock_uv = rotated_delta / (half_size * 2.0) + vec2(0.5);

	// Outside its own footprint this cell contributes nothing. Multiplied in
	// rather than branched on, so the atlas read keeps its screen derivatives.
	vec2 inside_low = step(vec2(0.0), rock_uv);
	vec2 inside_high = step(rock_uv, vec2(1.0));
	float footprint = (
		inside_low.x * inside_low.y * inside_high.x * inside_high.y
	);

	float atlas_count = float(max(rock_atlas_count, 1));
	float atlas_index = min(
		floor(dirt_hash(cell_seed + vec2(83.3, 17.9)) * atlas_count),
		atlas_count - 1.0
	);
	// Mirroring doubles the apparent variety without another drawn rock.
	float mirrored_u = mix(
		rock_uv.x,
		1.0 - rock_uv.x,
		step(0.5, dirt_hash(cell_seed + vec2(37.1, 92.7)))
	);
	vec4 art = texture(
		rock_texture,
		vec2(
			(atlas_index + clamp(mirrored_u, 0.0, 1.0)) / atlas_count,
			clamp(rock_uv.y, 0.0, 1.0)
		)
	);

	// The atlas is minified on screen, so the drawn silhouette arrives as a soft
	// ramp. Re-thresholding it against its own gradient keeps the inked edge as
	// crisp as the character art beside it, exactly as the terrain mask does.
	float alpha_softness = max(fwidth(art.a), 0.0001);
	float silhouette = smoothstep(
		0.5 - alpha_softness,
		0.5 + alpha_softness,
		art.a
	);

	// The art is grayscale: 0 is the inked outline and the mid grays are body
	// fills, which run from about 0.24 to 0.76 across the sheet.
	float art_value = max(max(art.r, art.g), art.b);
	float body = smoothstep(0.06, 0.18, art_value);
	// Keep the light and dark drawn fills apart instead of flattening the sheet
	// into one tone, then lift the top of the rock because light comes from above
	// everywhere else in the scene.
	float body_shade = mix(
		0.8,
		1.2,
		smoothstep(0.24, 0.76, art_value)
	) * mix(1.1, 0.86, clamp(rock_uv.y, 0.0, 1.0));
	vec3 stone = mix(
		rock_outline_color.rgb,
		rock_body_color.rgb * body_shade,
		body
	);
	return vec4(
		mix(stone, dirt_surface * 0.94, depth_fade),
		silhouette * footprint * rock_present
	);
}

// Samples the one deterministic crystal candidate owned by this scatter cell.
// The candidate's rotated bounding circle stays inside its cell, so no neighbor
// search is needed and a crystal cannot be clipped by a procedural grid edge.
vec4 sample_foreground_gem(vec2 world_position) {
	float cell_world_px = max(foreground_gem_cell_world_px, 1.0);
	vec2 grid_position = world_position / cell_world_px + vec2(19.7, 73.1);
	vec2 gem_cell = floor(grid_position);
	vec2 cell_local = fract(grid_position);
	vec2 gem_seed = gem_cell + vec2(41.3, 7.9);
	float gem_present = step(
		1.0 - clamp(foreground_gem_density, 0.0, 1.0),
		dirt_hash(gem_seed)
	);

	float minimum_height = min(
		foreground_gem_minimum_height,
		foreground_gem_maximum_height
	);
	float maximum_height = max(
		foreground_gem_minimum_height,
		foreground_gem_maximum_height
	);
	float height_fraction = mix(
		minimum_height,
		maximum_height,
		dirt_hash(gem_seed + vec2(13.1, 61.7))
	) / cell_world_px;
	float aspect = max(foreground_gem_cell_aspect, 0.01);
	float gem_angle = dirt_hash(gem_seed + vec2(29.3, 17.5)) * 6.2831853;
	float gem_cosine = cos(gem_angle);
	float gem_sine = sin(gem_angle);
	float bounding_radius = height_fraction
		* 0.5
		* sqrt(1.0 + aspect * aspect);
	float jitter_reach = max(0.5 - bounding_radius, 0.0);
	vec2 gem_center = vec2(0.5) + jitter_reach * (
		vec2(
			dirt_hash(gem_seed + vec2(5.7, 47.9)),
			dirt_hash(gem_seed + vec2(83.1, 3.7))
		) * 2.0 - 1.0
	);
	vec2 gem_delta = cell_local - gem_center;
	vec2 rotated_delta = vec2(
		gem_cosine * gem_delta.x + gem_sine * gem_delta.y,
		gem_cosine * gem_delta.y - gem_sine * gem_delta.x
	);
	vec2 gem_uv = rotated_delta / vec2(
		height_fraction * aspect,
		height_fraction
	) + vec2(0.5);
	vec2 inside_low = step(vec2(0.0), gem_uv);
	vec2 inside_high = step(gem_uv, vec2(1.0));
	float footprint = (
		inside_low.x * inside_low.y * inside_high.x * inside_high.y
	);

	float atlas_count = float(max(foreground_gem_atlas_count, 1));
	float atlas_index = min(
		floor(
			dirt_hash(gem_seed + vec2(71.9, 23.3))
				* atlas_count
		),
		atlas_count - 1.0
	);
	float mirrored_u = mix(
		gem_uv.x,
		1.0 - gem_uv.x,
		step(0.5, dirt_hash(gem_seed + vec2(37.7, 89.1)))
	);
	vec4 art = texture(
		foreground_gem_texture,
		vec2(
			(atlas_index + clamp(mirrored_u, 0.0, 1.0))
				/ atlas_count,
			clamp(gem_uv.y, 0.0, 1.0)
		)
	);
	float alpha_softness = max(fwidth(art.a), 0.0001);
	float silhouette = smoothstep(
		0.5 - alpha_softness,
		0.5 + alpha_softness,
		art.a
	);
	return vec4(art.rgb, silhouette * footprint * gem_present);
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
vec3 apply_strata_texture(
	vec3 surface_color,
	vec2 world_position,
	float trodden_ramp
) {
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

	// Bedding uses the darker detail color. Its alpha controls the authored
	// strength, and the cap preserves some base tint so neighboring strata do not
	// collapse into one indistinguishable dark mass.
	float detail_mix = clamp(
		sediment_line * bedding_strength * dirt_detail_color.a,
		0.0,
		0.85
	);
	vec3 dirt_only_surface = mix(
		textured_surface,
		dirt_detail_color.rgb,
		detail_mix
	);
	if (!use_rock_texture) {
		return dirt_only_surface;
	}

	// Drawn rock clusters, composited far to near over the finished dirt. The
	// depth order is the point: overlapping stones in one pile occlude each other
	// consistently, and each pass behind the last gives up contrast into the dirt,
	// so a cluster gains a front and a back instead of reading as a flat sprinkle.
	// Every pass is bedded against dirt_only_surface, not against the rocks
	// already drawn, so recession is measured from the ground the pile sits in.
	float near_cell_px = safe_detail_scale * ROCK_GRID_SCALE;
	// Loose stone is swept off the walked band in step with the ramp, so the
	// scatter thins toward the top edge and resumes as the transition fades.
	float rock_strength = clamp(rock_detail_strength, 0.0, 1.0) * (
		1.0 - clamp(trodden_ramp * trodden_rock_clearing, 0.0, 1.0)
	);
	vec3 clustered_surface = dirt_only_surface;

	vec4 far_rock = sample_drawn_rock(
		world_position,
		dirt_only_surface,
		near_cell_px * ROCK_FAR_CELL_SCALE,
		ROCK_FAR_GRID_ANGLE,
		2.0,
		ROCK_FAR_PRESENCE,
		ROCK_FAR_DEPTH_FADE
	);
	clustered_surface = mix(
		clustered_surface,
		far_rock.rgb,
		far_rock.a * rock_strength
	);

	vec4 mid_rock = sample_drawn_rock(
		world_position,
		dirt_only_surface,
		near_cell_px * ROCK_MID_CELL_SCALE,
		ROCK_MID_GRID_ANGLE,
		1.0,
		ROCK_MID_PRESENCE,
		ROCK_MID_DEPTH_FADE
	);
	clustered_surface = mix(
		clustered_surface,
		mid_rock.rgb,
		mid_rock.a * rock_strength
	);

	// The near pass casts before it draws. Sampling the same pass a short way up
	// and left returns its own silhouette displaced down and right, which is the
	// shadow that seats a pile on the dirt instead of leaving it printed on top.
	if (use_rock_shadows) {
		vec4 near_shadow = sample_drawn_rock(
			world_position - vec2(0.06, 0.12) * near_cell_px,
			dirt_only_surface,
			near_cell_px,
			ROCK_NEAR_GRID_ANGLE,
			0.0,
			ROCK_NEAR_PRESENCE,
			0.0
		);
		clustered_surface *= 1.0 - clamp(
			near_shadow.a * rock_shadow_strength * rock_strength,
			0.0,
			0.85
		);
	}

	vec4 near_rock = sample_drawn_rock(
		world_position,
		dirt_only_surface,
		near_cell_px,
		ROCK_NEAR_GRID_ANGLE,
		0.0,
		ROCK_NEAR_PRESENCE,
		0.0
	);
	vec3 detailed_surface = mix(
		clustered_surface,
		near_rock.rgb,
		near_rock.a * rock_strength
	);
	return detailed_surface;
}

// Composes optional art, tint, procedural strata detail, and the damage mask.
void fragment() {
	// Sprite TEXTURE packs fracture darkness in luminance and terrain solidity
	// in alpha, so both values share one streamed texture and one upload.
	vec4 packed_mask = sample_terrain_mask(UV);
	float mask_alpha = packed_mask.a;
	float fracture_value = packed_mask.r;
	vec4 artwork = vec4(1.0);
	// Buried strata use progressively darker, higher-contrast contour colors,
	// so their otherwise one-pixel threshold exposes screen-pixel stair steps.
	// Widen only that derivative AA band; this adds no texture reads and leaves
	// the foreground's authored sharp edge and the 16 px mask density unchanged.
	float cut_aa_half_width = mix(
		0.5,
		0.85,
		smoothstep(0.65, 1.0, clamp(stratum_depth, 0.0, 1.0))
	);

	// The mask is authored below world resolution and drawn with linear
	// filtering, so every cut arrives as a wide soft ramp. Re-thresholding it
	// against its own screen-space gradient collapses that ramp back to a
	// single antialiased pixel: the organic silhouette survives, the blur does
	// not. Neighbour taps below intentionally keep reading the raw ramp,
	// because the bevel wants the gradual falloff this removes here.
	if (sharpen_mask_edges) {
		float alpha_softness = max(fwidth(mask_alpha), 0.0001);
		mask_alpha = smoothstep(
			0.5 - alpha_softness * cut_aa_half_width,
			0.5 + alpha_softness * cut_aa_half_width,
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
	// The trodden ramp is resolved BEFORE the strata pass, because the rock
	// scatter needs it too - the band is only convincing if the stones answer to
	// it as well as the colour does.
	float trodden_ramp = 0.0;
	float trodden_grain = 0.5;
	if (use_trodden_floor) {
		float trodden_below = world_position.y - trodden_floor_world_y;
		float trodden_wobble = (
			dirt_noise(vec2(world_position.x / 53.0, 0.0)) - 0.5
		) * 2.0 * trodden_edge_wander_world_px;
		float trodden_hold_depth = max(
			trodden_depth_world_px + trodden_ground_extension_world_px,
			0.0
		);
		float trodden_end_depth = max(
			trodden_hold_depth + trodden_falloff_world_px,
			1.0
		);
		trodden_ramp = smoothstep(-2.0, 2.0, trodden_below) * (
			1.0 - smoothstep(
				trodden_hold_depth,
				trodden_end_depth,
				trodden_below - trodden_wobble
			)
		);
		trodden_grain = dirt_noise(
			world_position / max(trodden_grain_world_px, 1.0)
		);
	}

	vec3 surface_color = artwork.rgb * layer_tint.rgb;
	if (use_strata_texture) {
		surface_color = apply_strata_texture(
			surface_color,
			world_position,
			trodden_ramp
		);
	}
	// Keep the terrain beneath a gem so fracture ink can reveal that terrain
	// instead of flattening every line into a new opaque color.
	vec3 terrain_surface = surface_color;
	float foreground_gem_coverage = 0.0;
	if (use_foreground_gems) {
		vec4 foreground_gem = sample_foreground_gem(world_position);
		foreground_gem_coverage = foreground_gem.a;
		surface_color = mix(
			surface_color,
			foreground_gem.rgb,
			foreground_gem_coverage
		);
	}
	// Bevel and ink this stratum from one shared set of boundary samples. The
	// continuous outline is independent of the optional authored crack spurs,
	// which can remain irregular without leaving gaps around the actual hole.
	if (
		(use_layer_edge_shading || cut_outline_strength > 0.0)
		&& mask_alpha > 0.0
	) {
		vec2 edge_step = vec2(max(edge_shade_world_pixels, 0.5))
			/ max(chunk_world_size, vec2(1.0));
		vec4 neighbor_alpha = vec4(
			sample_terrain_mask(UV - vec2(0.0, edge_step.y)).a,
			sample_terrain_mask(UV + vec2(0.0, edge_step.y)).a,
			sample_terrain_mask(UV - vec2(edge_step.x, 0.0)).a,
			sample_terrain_mask(UV + vec2(edge_step.x, 0.0)).a
		);
		if (use_layer_edge_shading) {
			surface_color = apply_edge_shading(
				surface_color,
				neighbor_alpha
			);
		}
		// Keep the black contour at the same 0.5 mask boundary, but antialias
		// that threshold over one screen pixel. A binary step here was the
		// remaining source of stair-stepped ink even with a dense terrain mask.
		vec4 neighbor_softness = max(
			fwidth(neighbor_alpha),
			vec4(0.0001)
		);
		vec4 solid_neighbor = smoothstep(
			vec4(0.5) - neighbor_softness * cut_aa_half_width,
			vec4(0.5) + neighbor_softness * cut_aa_half_width,
			neighbor_alpha
		);
		float nearest_solid_neighbor = min(
			min(solid_neighbor.x, solid_neighbor.y),
			min(solid_neighbor.z, solid_neighbor.w)
		);
		// Four cardinal taps find the open side cheaply, but using their
		// minimum directly measures Manhattan distance and stair-steps
		// diagonal ink. Recover direction from the raw filtered values instead
		// of the thresholded coverage: thresholding quantizes shallow curves
		// into horizontal/diagonal steps. The existing final projected tap then
		// keeps a constant world-space line weight without raising the streamed
		// mask density or adding any texture reads.
		vec2 open_direction = vec2(
			neighbor_alpha.z - neighbor_alpha.w,
			neighbor_alpha.x - neighbor_alpha.y
		);
		float open_direction_length = length(open_direction);
		float projected_solid_neighbor = nearest_solid_neighbor;
		if (open_direction_length > 0.0001) {
			float projected_alpha = sample_terrain_mask(
				UV + open_direction / open_direction_length * edge_step
			).a;
			float projected_softness = max(
				fwidth(projected_alpha),
				0.0001
			);
			projected_solid_neighbor = smoothstep(
				0.5 - projected_softness * cut_aa_half_width,
				0.5 + projected_softness * cut_aa_half_width,
				projected_alpha
			);
		}
		float cut_outline = (
			1.0 - projected_solid_neighbor
		) * mask_alpha;
		surface_color = mix(
			surface_color,
			rock_outline_color.rgb,
			clamp(cut_outline * cut_outline_strength, 0.0, 1.0)
		);
	}

	// Recover the drawn stroke before it shades anything. Neighbour taps are
	// gated on their own solidity: a cleared mask pixel carries luminance zero,
	// which would otherwise read as maximum ink and ring every opening in the
	// chunk with a line no artist drew.
	if (sharpen_fracture_lines && fracture_line_ink > 0.0) {
		float ink = 1.0 - fracture_value;
		if (fracture_line_weight_world_px > 0.0) {
			vec2 ink_step = vec2(fracture_line_weight_world_px)
				/ max(chunk_world_size, vec2(1.0));
			vec4 ink_left = sample_terrain_mask(
				UV - vec2(ink_step.x, 0.0)
			);
			vec4 ink_right = sample_terrain_mask(
				UV + vec2(ink_step.x, 0.0)
			);
			vec4 ink_up = sample_terrain_mask(
				UV - vec2(0.0, ink_step.y)
			);
			vec4 ink_down = sample_terrain_mask(
				UV + vec2(0.0, ink_step.y)
			);
			ink = max(ink, (1.0 - ink_left.r) * step(0.5, ink_left.a));
			ink = max(ink, (1.0 - ink_right.r) * step(0.5, ink_right.a));
			ink = max(ink, (1.0 - ink_up.r) * step(0.5, ink_up.a));
			ink = max(ink, (1.0 - ink_down.r) * step(0.5, ink_down.a));
		}
		ink = clamp(ink / fracture_line_ink, 0.0, 1.0);
		float ink_softness = max(fwidth(ink), 0.0001);
		float ink_threshold = 0.5 / max(fracture_line_gain, 0.0001);
		ink = smoothstep(
			ink_threshold - ink_softness * 0.5,
			ink_threshold + ink_softness * 0.5,
			ink
		);
		fracture_value = 1.0 - ink * fracture_line_ink;
	}

	// Preserve the original multiplicative fracture rendering everywhere. Only
	// where a gem intersects ink does the shader substitute the dirt beneath it
	// and normalize the authored line strength to fully occlude the crystal.
	float fracture_mix = 1.0 - fracture_value;
	float gem_fracture_mix = fracture_mix;
	if (fracture_line_ink > 0.0) {
		gem_fracture_mix = clamp(
			fracture_mix / fracture_line_ink,
			0.0,
			1.0
		);
	}
	vec3 fracture_surface = mix(
		surface_color * fracture_shade_color.rgb,
		terrain_surface * fracture_shade_color.rgb,
		foreground_gem_coverage
	);
	surface_color = mix(
		surface_color,
		fracture_surface,
		mix(
			fracture_mix,
			gem_fracture_mix,
			foreground_gem_coverage
		)
	);

	// Only alpha is cut by the streamed mask. Optional artwork alpha and layer
	// tint alpha are preserved, while RGB remains the fully shaded dirt color.
	float final_alpha = artwork.a * layer_tint.a * mask_alpha;
	if (use_trodden_floor && trodden_floor_seals_mask) {
		// An encounter floor is already complete before control reaches it.
		// Seal the foreground from one world pixel above its authored support
		// line downward while the cinematic owns it, so filtered chamber-mask
		// alpha can never expose the lower stratum above the 2.5D plane. This is
		// a presentation-only mismatch of at most one world pixel; collision
		// remains on the logical floor and F3 still renders that truth directly.
		float floor_backdrop_occlusion = step(
			-1.0,
			world_position.y - trodden_floor_world_y
		);
		final_alpha = max(final_alpha, floor_backdrop_occlusion);
	}

	// The colour half of the trodden floor. The ramp itself was resolved above,
	// before the strata pass, so the rock scatter could thin out in step with it.
	if (trodden_ramp > 0.0) {
		// Grain is a whisper. It exists so a long flat floor is not one clean
		// gradient, not to texture the rock - the strata pass already did that,
		// and it has just been told to leave this band alone.
		vec3 packed_color = trodden_color.rgb * (
			1.0 + (trodden_grain - 0.5) * trodden_grain_strength
		);
		surface_color = mix(
			surface_color,
			packed_color,
			clamp(trodden_ramp * trodden_strength, 0.0, 1.0)
		);
	}
	if (use_trodden_floor) {
		surface_color = apply_ground_plane(
			surface_color,
			world_position.y,
			trodden_floor_world_y,
			trodden_shelf_depth_world_px,
			trodden_shelf_plateau,
			trodden_shelf_light_color.rgb,
			trodden_shelf_light_strength,
			trodden_face_shade_depth_world_px,
			trodden_face_shade_strength,
			1.0,
			vec3(0.0),
			0.0,
			trodden_contact_depth_world_px,
			trodden_contact_strength,
			0.0,
			vec3(0.0),
			0.0
		);
		float depth_below_floor = (
			world_position.y - trodden_floor_world_y
		);
		float trodden_end_depth = max(
			trodden_depth_world_px
				+ trodden_ground_extension_world_px
				+ trodden_falloff_world_px,
			1.0
		);
		float matte_fade_depth = clamp(
			trodden_matte_fade_world_px,
			1.0,
			trodden_end_depth
		);
		float matte_wander = (trodden_grain - 0.5)
			* 2.0
			* trodden_edge_wander_world_px;
		float matte_taper = smoothstep(
			trodden_end_depth - matte_fade_depth,
			trodden_end_depth,
			depth_below_floor - matte_wander
		);
		surface_color = mix(
			surface_color,
			trodden_matte_color.rgb,
			matte_taper
		);
	}

	// Surface dressing, foreground stratum only. Grass grows out of this
	// layer's own top edge and the crust sits in its own top pixels, so a mined
	// opening takes both away with it without any extra bookkeeping.
	if (use_surface_grass) {
		if (mask_alpha < 0.5 && use_grass_texture) {
			float grass_band = surface_grass_band(world_position);
			if (grass_band > 0.0) {
				// Grass only survives where the ground just under the line is
				// still intact, so a mined opening takes it with the dirt.
				float support_alpha = sample_terrain_mask(
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
					// Height inside the blade strip: 1 at the tip, 0 at the
					// mat. The sun is at the horizon, so only what stands clear
					// of the mat catches any of it.
					float blade_height = clamp(
						(surface_world_y - world_position.y)
							/ max(grass_height_world_px, 1.0),
						0.0,
						1.0
					);
					surface_color = blade.rgb * mix(
						vec3(1.0),
						grass_shade_color.rgb * 2.0,
						clamp(grass_shade_strength, 0.0, 1.0)
					);
					surface_color += grass_tip_light_color.rgb
						* pow(blade_height, 2.2)
						* max(grass_tip_light_strength, 0.0);
					final_alpha = grass;
				}
			}
		} else {
			// The top of the ground: lit shelf, the shadow off its far edge,
			// the packed lip on it, then the grass's contact shade over all of
			// it. Read together they give the dirt a top face, a far edge, and
			// a cut face below. The stack lives in ground_plane_light so the
			// cutscene floor below can be the same ground rather than a second
			// one drifting out of step with this.
			//
			// Rise strength is zero here: the world surface has open sky above
			// it, not a wall standing on it, and passing zero keeps this path
			// exactly the pixels it drew before the stack moved out of line.
			surface_color = apply_ground_plane(
				surface_color,
				world_position.y,
				surface_world_y,
				ground_shelf_depth_world_px,
				ground_shelf_plateau,
				ground_shelf_light_color.rgb,
				ground_shelf_light_strength,
				ground_face_shade_depth_world_px,
				ground_face_shade_strength,
				crust_depth_world_px,
				crust_color.rgb,
				crust_strength,
				ground_contact_depth_world_px,
				ground_contact_strength,
				0.0,
				vec3(0.0),
				0.0
			);
		}

	}

	// The same ground again, on the room's own floor. A cutscene stands its
	// cast hundreds of rows below the surface, where none of the above reaches,
	// so without this the floor they stand on is flat rock and the shot loses
	// the depth the surface gets for free.
	//
	// Outside the surface-grass branch deliberately. That flag is about grass,
	// and a room 2,500 rows down has none: nesting this under it would tie a
	// cutscene floor to whether the stratum above it grows anything.
	//
	// Here the rise is on. A room has rock standing on its floor, and the band
	// above that junction is what stops the wall and the floor meeting as a
	// seam.
	if (use_cutscene_floor_plane) {
		surface_color = apply_ground_plane(
			surface_color,
			world_position.y,
			cutscene_floor_world_y,
			ground_shelf_depth_world_px,
			ground_shelf_plateau,
			ground_shelf_light_color.rgb,
			ground_shelf_light_strength,
			ground_face_shade_depth_world_px,
			ground_face_shade_strength,
			crust_depth_world_px,
			crust_color.rgb,
			crust_strength,
			ground_contact_depth_world_px,
			ground_contact_strength,
			ground_wall_rise_world_px,
			ground_wall_rise_color.rgb,
			ground_wall_rise_strength
		);
	}

	COLOR = vec4(surface_color, final_alpha);
}
