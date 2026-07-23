class_name TerrainLayerProfile
extends Resource

## Configures terrain strata, impact masks, and future authored textures.

@export_category("Layers")
## Lists strata from the foreground surface to the deepest visible dirt.
@export var layer_tints: PackedColorArray = PackedColorArray([
	Color("eec39a"),
	Color("d9a066"),
	Color("df7126"),
	Color("8f563b"),
])
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

@export_category("Impact Shape")
## Lists organic cutout masks from the foreground layer to the deepest layer.
@export var small_hole_masks: Array[Texture2D] = []
@export var big_hole_masks: Array[Texture2D] = []
## Adds visible bands between progressively smaller layer openings.
@export_range(0, 64, 1) var rim_width: int = 16
## Offsets each stratum so impact rings do not share one silhouette.
@export var layer_impact_offsets: PackedVector2Array = PackedVector2Array([
	Vector2(-14.0, -6.0),
	Vector2(11.0, 5.0),
	Vector2(-7.0, 10.0),
	Vector2(4.0, -3.0),
])
## Keeps the deepest stratum as a solid back wall behind mined openings.
@export var keep_back_layer_solid: bool = true
## Ensures the deepest art opening fully covers logical terrain damage.
@export_range(0, 32, 1) var core_hole_padding: int = 4
## Selects large masks and permits the deepest brown backdrop to appear.
@export_range(8, 512, 1) var big_hole_minimum_size: int = 80
@export_range(0.05, 0.95, 0.05) var transparent_alpha_threshold: float = 0.5

@export_category("Debris")
@export var debris_colors: PackedColorArray = PackedColorArray([
	Color("eec39a"),
	Color("d9a066"),
	Color("df7126"),
	Color("8f563b"),
])


## Returns the number of visible terrain strata.
func get_layer_count() -> int:
	return layer_tints.size()


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


## Returns a dirt color for one debris piece.
func get_debris_color(color_index: int) -> Color:
	if debris_colors.is_empty():
		return Color.WHITE
	return debris_colors[posmod(color_index, debris_colors.size())]
