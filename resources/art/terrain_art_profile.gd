class_name TerrainArtProfile
extends Resource

## Holds the artwork and rendering settings for one terrain material.

@export_category("Rendering Mode")
## Keeps the current flat terrain until an authored profile is ready.
@export var layered_rendering_enabled: bool = false

@export_category("Main Materials")
## Provides authored surface variants sampled in continuous world space.
@export var surface_textures: Array[Texture2D] = []
## Selects one surface variant for every chunk using this profile.
@export_range(0, 32, 1) var surface_variant_index: int = 0
@export var cavity_texture: Texture2D
@export var fresh_edge_texture: Texture2D

@export_category("Details")
## Reserves the authored rubble sheet for future break-detail placement.
@export var rubble_atlas: Texture2D
## Reserves authored dust variants for future impact-detail placement.
@export var dust_textures: Array[Texture2D] = []
## Replaces placeholder ore colors while preserving generated ore masks.
@export var ore_texture: Texture2D

@export_category("Rendering")
@export var texture_world_size: Vector2 = Vector2(512.0, 512.0)
@export_range(1, 12, 1) var edge_width_cells: int = 2
@export var surface_tint: Color = Color.WHITE
@export var cavity_tint: Color = Color(0.075, 0.095, 0.13, 1.0)
@export var edge_tint: Color = Color.WHITE


## Selects the authored non-empty surface variant for this profile.
func get_surface_texture() -> Texture2D:
	var available_textures: Array[Texture2D] = []
	for texture in surface_textures:
		if texture != null:
			available_textures.append(texture)
	if available_textures.is_empty():
		return null
	return available_textures[
		clampi(surface_variant_index, 0, available_textures.size() - 1)
	]
