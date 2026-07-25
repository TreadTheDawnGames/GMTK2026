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
	Color("30282c"),
	Color("242027"),
])
## Keeps ordinary impacts on the original strata; later layers are cinematic.
@export_range(1, 16, 1) var gameplay_layer_count: int = 4
## Supplies optional seamless artwork for each stratum.
@export var layer_fill_textures: Array[Texture2D] = []
## Places the miner between the foreground layer and the lower strata.
@export var layer_z_indices: PackedInt32Array = PackedInt32Array([
	2,
	0,
	-1,
	-2,
	-3,
	-4,
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
	56.0,
	64.0,
])
@export var layer_dirt_detail_colors: PackedColorArray = PackedColorArray([
	Color(0.25, 0.19, 0.15, 0.69),
	Color(0.20, 0.15, 0.11, 0.66),
	Color(0.15, 0.11, 0.09, 0.66),
	Color(0.09, 0.07, 0.07, 0.82),
	Color(0.08, 0.06, 0.07, 0.84),
	Color(0.06, 0.045, 0.055, 0.86),
])
@export var layer_dirt_variance_strengths: PackedFloat32Array = PackedFloat32Array([
	0.16,
	0.15,
	0.14,
	0.10,
	0.12,
	0.10,
])
@export var layer_rock_densities: PackedFloat32Array = PackedFloat32Array([
	0.12,
	0.22,
	0.45,
	0.14,
	0.28,
	0.22,
])
@export var layer_rock_detail_strengths: PackedFloat32Array = PackedFloat32Array([
	0.45,
	0.50,
	0.55,
	0.40,
	0.52,
	0.48,
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
	Vector2.ZERO,
	Vector2.ZERO,
])
## Shrinks each deeper silhouette to read as one fracture traveling inward.
@export var layer_impact_scales: PackedFloat32Array = PackedFloat32Array([
	1.00,
	0.95,
	0.80,
	0.70,
	0.64,
	0.58,
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
## How far out from the cavity an authored stroke may sit before it is dropped.
## The mask art outlines its hole and then adds loose scribbles standing off in
## the surrounding rock. The outline is the inked edge that matches the
## characters; the scribbles read as marks lying on top of the dirt.
@export_range(1.0, 128.0, 1.0) var fracture_rim_reach_px: float = 9.0

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
	Color("392e46"),
	Color("242027"),
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
