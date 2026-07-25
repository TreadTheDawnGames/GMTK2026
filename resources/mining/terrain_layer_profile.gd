@tool
class_name TerrainLayerProfile
extends Resource

## Configures terrain strata, impact masks, and future authored textures.
## @tool so the editor terrain preview can call these accessors: a non-tool
## resource loads as a placeholder inside a tool script and throws on any
## method call.

@export_category("Layers")
## Lists strata from the foreground surface to the deepest visible dirt.
@export var layer_tints: PackedColorArray = PackedColorArray([
	Color("eec39a"),
	Color("d9a066"),
	Color("df7126"),
	Color("8f563b"),
])
## Every authored stratum belongs to normal gameplay and encounter tunnels.
@export_range(1, 16, 1) var gameplay_layer_count: int = 4
## Supplies optional seamless artwork for each stratum.
@export var layer_fill_textures: Array[Texture2D] = []
## Places the miner between the foreground layer and the lower strata.
@export var layer_z_indices: PackedInt32Array = PackedInt32Array([
	2,
	0,
	-1,
	-2,
])
## Sets mask detail independently from gameplay-cell and screen size.
@export_range(1, 8, 1) var mask_pixels_per_cell: int = 4
@export var fill_texture_world_size: Vector2 = Vector2(256.0, 256.0)

@export_category("Strata Dirt Texture")
## Adds flat dirt variance and sparse rocks without changing terrain logic.
@export var layer_dirt_texture_enabled: bool = true
## Moves from broad surface variation through tighter compacted strata.
@export var layer_dirt_detail_scales_px: PackedFloat32Array = PackedFloat32Array([
	64.0,
	48.0,
	32.0,
	72.0,
])
@export var layer_dirt_detail_colors: PackedColorArray = PackedColorArray([
	Color(0.25, 0.19, 0.15, 0.69),
	Color(0.20, 0.15, 0.11, 0.66),
	Color(0.15, 0.11, 0.09, 0.66),
	Color(0.09, 0.07, 0.07, 0.82),
])
@export var layer_dirt_variance_strengths: PackedFloat32Array = PackedFloat32Array([
	0.16,
	0.15,
	0.14,
	0.10,
])
## Probability that one scatter cell holds a rock inside a cluster, before the
## depth ramp. Deeper strata carry more, so an exposed rim shows the ground
## getting stonier the further back it goes.
@export var layer_rock_densities: PackedFloat32Array = PackedFloat32Array([
	0.13,
	0.26,
	0.44,
	0.58,
])
@export var layer_rock_detail_strengths: PackedFloat32Array = PackedFloat32Array([
	0.45,
	0.50,
	0.55,
	0.40,
])

@export_category("Drawn Rocks")
## Horizontal atlas of hand-drawn rocks, one per square cell, each centered
## inside transparent padding so the shader can sample a cell without reaching
## its neighbor. Clearing this leaves the strata as dirt and bedding only.
@export var rock_texture: Texture2D
@export_range(1, 64, 1) var rock_atlas_count: int = 13
## World period of the field that decides where clusters sit, and how much of the
## terrain those clusters cover. The bare dirt between drifts is what makes a
## pile read as a pile, so coverage near 1.0 loses the clustering entirely.
@export_range(32.0, 512.0, 1.0) var rock_cluster_world_px: float = 176.0
@export_range(0.0, 1.0, 0.01) var rock_cluster_coverage: float = 0.5
## Presence multiplier for a scatter cell outside every cluster, which is what
## leaves the occasional loner in otherwise clean dirt.
@export_range(0.0, 1.0, 0.01) var rock_loner_scale: float = 0.15
## Rock presence also climbs with distance below the original ground line, so
## topsoil stays readable and the deep run becomes visibly stonier. The ramp
## reaches its full gain this far below the surface.
@export_range(64.0, 20_000.0, 10.0) var rock_depth_ramp_world_px: float = 2600.0
@export_range(1.0, 6.0, 0.1) var rock_depth_ramp_gain: float = 2.4
## Prints each near rock's own displaced silhouette underneath it, so a cluster
## sits on the dirt instead of on top of it. This is the shader's fourth and last
## atlas read per pixel; turn it off to buy that sample back on the web build.
@export var rock_shadows_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var rock_shadow_strength: float = 0.45
## Stone body tone per stratum, before the drawn fill value and the overhead
## light shade it. Surface rocks stay in the tan palette and bedrock goes dark.
@export var layer_rock_body_colors: PackedColorArray = PackedColorArray([
	Color(0.60, 0.55, 0.48),
	Color(0.47, 0.42, 0.37),
	Color(0.35, 0.31, 0.28),
	Color(0.24, 0.22, 0.21),
])
## Ink tone per stratum for the drawn outline, matching the darker line the
## characters are drawn inside.
@export var layer_rock_outline_colors: PackedColorArray = PackedColorArray([
	Color(0.13, 0.10, 0.08),
	Color(0.10, 0.08, 0.07),
	Color(0.07, 0.06, 0.05),
	Color(0.05, 0.04, 0.04),
])

## Flat shading bands the dirt variation is quantised into, matching the hard
## steps the characters are drawn with. Zero keeps a continuous gradient.
@export_range(0.0, 12.0, 1.0) var dirt_shade_steps: float = 4.0
## Snaps the filtered mask back to a crisp cut edge. The mask is authored below
## world resolution, so without this every opening arrives soft-edged.
@export var sharpen_mask_edges: bool = true

@export_category("Strata Edge Depth")
## Bevels each stratum against its own opening so the exposed rims read as one
## connected rock face going backward rather than flat stacked cutouts.
@export var layer_edge_shading_enabled: bool = true
## How far the contact shadow reaches into the rock, in world pixels.
@export_range(0.0, 32.0, 0.5) var edge_shade_world_pixels: float = 6.0
## Darkening at a cut edge. Deeper strata scale past this automatically.
@export_range(0.0, 1.0, 0.01) var edge_shade_strength: float = 0.45
## Brightening on the upward-facing lip, matching light from above.
@export_range(0.0, 1.0, 0.01) var edge_light_strength: float = 0.30

@export_category("Surface Dressing")
## Grows grass and packed crust out of the foreground stratum itself, so a mined
## opening removes them with the ground rather than leaving them floating.
@export var surface_grass_enabled: bool = true
## How far either side of the original ground line grass can grow at all.
@export_range(0.0, 256.0, 1.0) var surface_band_world_px: float = 36.0
@export_range(0.0, 64.0, 1.0) var grass_height_world_px: float = 20.0
## Horizontal atlas of drawn clumps, each bottom-aligned in its own cell. That
## alignment is what keeps blades rooted: the strip maps the cell's bottom edge
## onto the ground line, so a clump can never start mid-air.
@export var grass_texture: Texture2D
@export_range(1, 32, 1) var grass_clump_count: int = 6
## One atlas cell's width over its height, so clumps keep their drawn shape.
@export_range(0.05, 4.0, 0.001) var grass_cell_aspect: float = 0.4583
## Spacing between tufts along the ground.
@export_range(2.0, 128.0, 1.0) var grass_cell_world_px: float = 11.0
## How far below the ground line the mask is probed to decide grass survives.
@export_range(1.0, 32.0, 1.0) var grass_support_probe_px: float = 4.0
## Packed earth depth on the exposed top of the surface.
@export_range(0.0, 64.0, 1.0) var crust_depth_world_px: float = 10.0
@export var crust_color: Color = Color(0.46, 0.42, 0.36)
@export_range(0.0, 1.0, 0.01) var crust_strength: float = 0.5

@export_category("Impact Shape")
## Lists organic cutout masks from the foreground layer to the deepest layer.
@export var small_hole_masks: Array[Texture2D] = []
@export var big_hole_masks: Array[Texture2D] = []
## Adds visible bands between progressively smaller layer openings.
@export_range(0, 64, 1) var rim_width: int = 16
## Defaults every stratum to the common impact origin.
@export var layer_impact_offsets: PackedVector2Array = PackedVector2Array([
	Vector2.ZERO,
	Vector2.ZERO,
	Vector2.ZERO,
	Vector2.ZERO,
])
## Shrinks each deeper silhouette to read as one fracture traveling inward.
@export var layer_impact_scales: PackedFloat32Array = PackedFloat32Array([
	1.00,
	0.95,
	0.80,
	0.70,
])
## Keeps the deepest stratum as a solid back wall behind mined openings.
@export var keep_back_layer_solid: bool = true
## Ensures the deepest art opening fully covers logical terrain damage.
@export_range(0, 32, 1) var core_hole_padding: int = 4
## Selects large masks and permits the deepest brown backdrop to appear.
@export_range(8, 512, 1) var big_hole_minimum_size: int = 80
@export_range(0.05, 0.95, 0.05) var transparent_alpha_threshold: float = 0.5
## Selects only the genuinely dark strokes from the mask artwork.
@export_range(0.01, 1.0, 0.01) var fracture_line_luminance_threshold: float = 0.38
## Darkens the layer tint beneath authored strokes without pasting gray pixels.
@export_range(0.0, 1.0, 0.01) var fracture_line_strength: float = 0.78
## Multiplies the rock beneath a stroke rather than pasting neutral pixels over
## it, so an inked edge still carries the stratum's own hue.
@export var fracture_shade_color: Color = Color(0.14, 0.11, 0.10)
## How many strata in front carry the authored strokes at all. One inked rim
## reads as a broken edge; four stacked copies read as concentric worms.
@export_range(0, 8, 1) var fracture_line_layer_depth: int = 1
## Multiplies stroke strength again for each stratum behind the first.
@export_range(0.0, 1.0, 0.05) var fracture_line_depth_falloff: float = 0.4
## How far out from the cavity an authored stroke may sit before it is dropped,
## measured in the authored mask's own pixels, not world or mask-chunk pixels.
## The hole art inks its rim and then throws crack spurs out into the
## surrounding rock; both belong to the drawing. This exists only to drop
## strokes that have wandered far enough out to read as marks lying on the dirt
## rather than as part of the break, so it has to clear the authored spurs. At
## the delivered 512px masks the spurs reach about 70px.
@export_range(1.0, 256.0, 1.0) var fracture_rim_reach_px: float = 96.0
## Restores the authored stroke at screen resolution. The mask stores strokes at
## mask_pixels_per_cell, so without this a drawn line arrives as a soft grey
## ramp however boldly it was inked. See the shader block for the method.
@export var fracture_line_sharpen: bool = true
## Multiplies recovered stroke coverage before it is re-thresholded, which is
## what pulls a stroke that the per-hit downscale left partial back to full ink.
@export_range(1.0, 4.0, 0.05) var fracture_line_gain: float = 1.6
## Stroke weight in world pixels. Authored in world space so a stroke keeps the
## same drawn weight whether it was stamped into a small hole or a large one.
@export_range(0.0, 8.0, 0.25) var fracture_line_weight_world_px: float = 0.5

@export_category("Encounter Chambers")
## Lowers layer one so layer two forms the visible chamber standing surface.
@export_range(0.0, 64.0, 1.0) var chamber_layer_two_floor_reveal_px: float = 20.0

@export_category("Debris and Dust")
## Uses a lighter earth value so dust separates from the dark tunnel back wall.
@export var impact_smoke_color: Color = Color(0.52, 0.40, 0.30)
@export var debris_colors: PackedColorArray = PackedColorArray([
	Color("eec39a"),
	Color("d9a066"),
	Color("df7126"),
	Color("8f563b"),
])


## Returns the number of visible terrain strata.
func get_layer_count() -> int:
	return layer_tints.size()


## Returns the original layer count available to ordinary gameplay impacts.
func get_gameplay_layer_count() -> int:
	return clampi(gameplay_layer_count, 1, get_layer_count())


## Returns one layer's optional authored fill texture.
func get_fill_texture(layer_index: int) -> Texture2D:
	if (
		layer_index < 0
		or layer_index >= layer_fill_textures.size()
	):
		return null
	return layer_fill_textures[layer_index]


## Returns one stratum's drawn-rock body tone.
func get_rock_body_color(layer_index: int) -> Color:
	if (
		layer_index < 0
		or layer_index >= layer_rock_body_colors.size()
	):
		return Color(0.44, 0.37, 0.31)
	return layer_rock_body_colors[layer_index]


## Returns one stratum's drawn-rock outline tone.
func get_rock_outline_color(layer_index: int) -> Color:
	if (
		layer_index < 0
		or layer_index >= layer_rock_outline_colors.size()
	):
		return Color(0.10, 0.08, 0.07)
	return layer_rock_outline_colors[layer_index]


## Returns one layer's draw order relative to the miner.
func get_layer_z_index(layer_index: int) -> int:
	if (
		layer_index < 0
		or layer_index >= layer_z_indices.size()
	):
		return -layer_index
	return layer_z_indices[layer_index]


## Returns the organic opening used by one terrain layer.
func get_hole_mask(
	layer_index: int,
	use_big_hole: bool
) -> Texture2D:
	var masks := (
		big_hole_masks
		if use_big_hole
		else small_hole_masks
	)
	if masks.is_empty():
		return null
	return masks[clampi(layer_index, 0, masks.size() - 1)]


## Returns one stratum's offset from the impact center.
func get_layer_impact_offset(layer_index: int) -> Vector2:
	if (
		layer_index < 0
		or layer_index >= layer_impact_offsets.size()
	):
		return Vector2.ZERO
	return layer_impact_offsets[layer_index]


## Returns how strongly one stratum prints the authored crack strokes. Strata
## behind the authored depth draw none, so a single hit leaves one fracture
## rather than one repeated per layer.
func get_fracture_line_layer_scale(layer_index: int) -> float:
	if layer_index < 0 or layer_index >= fracture_line_layer_depth:
		return 0.0
	return pow(fracture_line_depth_falloff, float(layer_index))


## Returns one stratum's authored opening scale.
func get_layer_impact_scale(layer_index: int) -> float:
	if (
		layer_index < 0
		or layer_index >= layer_impact_scales.size()
	):
		return 1.0
	return layer_impact_scales[layer_index]


## Returns a dirt color for one debris piece.
func get_debris_color(color_index: int) -> Color:
	if debris_colors.is_empty():
		return Color.WHITE
	return debris_colors[posmod(color_index, debris_colors.size())]
