class_name TerrainChunkVisual
extends Node2D

## Renders one terrain chunk from gameplay-owned textures and optional artwork.

enum ViewMode {
	FINAL,
	SOLID_MASK,
	EDGE_MASK,
	ORE_MASK,
}

@export_category("Layers")
@export var cavity_sprite: Sprite2D
@export var surface_sprite: Sprite2D
@export var edge_sprite: Sprite2D
@export var ore_sprite: Sprite2D
@export var legacy_composite_sprite: Sprite2D

var _solid_mask_texture: ImageTexture
var _domain_mask_texture: ImageTexture
var _edge_mask_texture: ImageTexture
var _ore_mask_texture: ImageTexture
var _composite_texture: ImageTexture
var _art_profile: TerrainArtProfile
var _view_mode: ViewMode = ViewMode.FINAL


## Applies chunk textures while preserving the flat prototype by default.
func configure(
	composite_texture: ImageTexture,
	solid_mask_texture: ImageTexture,
	domain_mask_texture: ImageTexture,
	edge_mask_texture: ImageTexture,
	ore_mask_texture: ImageTexture,
	art_profile: TerrainArtProfile,
	world_origin_px: Vector2,
	chunk_world_size_px: Vector2
) -> void:
	_composite_texture = composite_texture
	_solid_mask_texture = solid_mask_texture
	_domain_mask_texture = domain_mask_texture
	_edge_mask_texture = edge_mask_texture
	_ore_mask_texture = ore_mask_texture
	_art_profile = art_profile

	legacy_composite_sprite.texture = _composite_texture
	cavity_sprite.texture = _domain_mask_texture
	surface_sprite.texture = _solid_mask_texture
	edge_sprite.texture = _edge_mask_texture
	ore_sprite.texture = _ore_mask_texture

	_configure_layer_material(
		cavity_sprite,
		_art_profile.cavity_texture if _art_profile != null else null,
		_art_profile.cavity_tint if _art_profile != null else Color.WHITE,
		false,
		world_origin_px,
		chunk_world_size_px
	)
	_configure_layer_material(
		surface_sprite,
		_art_profile.get_surface_texture()
			if _art_profile != null else null,
		_art_profile.surface_tint if _art_profile != null else Color.WHITE,
		false,
		world_origin_px,
		chunk_world_size_px
	)
	_configure_layer_material(
		edge_sprite,
		_art_profile.fresh_edge_texture if _art_profile != null else null,
		_art_profile.edge_tint if _art_profile != null else Color.WHITE,
		false,
		world_origin_px,
		chunk_world_size_px
	)
	_configure_layer_material(
		ore_sprite,
		_art_profile.ore_texture if _art_profile != null else null,
		Color.WHITE,
		true,
		world_origin_px,
		chunk_world_size_px
	)
	set_view_mode(_view_mode)


## Selects the final terrain or one diagnostic mask.
func set_view_mode(view_mode: ViewMode) -> void:
	_view_mode = view_mode
	cavity_sprite.hide()
	surface_sprite.hide()
	edge_sprite.hide()
	ore_sprite.hide()
	legacy_composite_sprite.hide()

	match _view_mode:
		ViewMode.SOLID_MASK:
			legacy_composite_sprite.texture = _solid_mask_texture
			legacy_composite_sprite.modulate = Color.WHITE
			legacy_composite_sprite.show()
		ViewMode.EDGE_MASK:
			legacy_composite_sprite.texture = _edge_mask_texture
			legacy_composite_sprite.modulate = Color.WHITE
			legacy_composite_sprite.show()
		ViewMode.ORE_MASK:
			legacy_composite_sprite.texture = _ore_mask_texture
			legacy_composite_sprite.modulate = Color.WHITE
			legacy_composite_sprite.show()
		_:
			_show_final_layers()


## Uploads only masks changed by a fading terrain pixel.
func update_damage_textures(
	composite_image: Image,
	solid_mask_image: Image,
	ore_mask_image: Image
) -> void:
	_composite_texture.update(composite_image)
	_solid_mask_texture.update(solid_mask_image)
	_ore_mask_texture.update(ore_mask_image)


## Uploads a rebuilt fresh-edge mask.
func update_edge_texture(edge_mask_image: Image) -> void:
	_edge_mask_texture.update(edge_mask_image)


## Shows layered artwork only when the selected profile enables it.
func _show_final_layers() -> void:
	if _art_profile != null and _art_profile.layered_rendering_enabled:
		cavity_sprite.show()
		surface_sprite.show()
		edge_sprite.show()
		ore_sprite.show()
		return
	legacy_composite_sprite.texture = _composite_texture
	legacy_composite_sprite.modulate = Color.WHITE
	legacy_composite_sprite.show()


## Supplies continuous world coordinates and artwork to one mask material.
func _configure_layer_material(
	sprite: Sprite2D,
	art_texture: Texture2D,
	tint: Color,
	mask_from_alpha: bool,
	world_origin_px: Vector2,
	chunk_world_size_px: Vector2
) -> void:
	var material := sprite.material.duplicate() as ShaderMaterial
	sprite.material = material
	material.set_shader_parameter(&"art_texture", art_texture)
	material.set_shader_parameter(&"use_art_texture", art_texture != null)
	material.set_shader_parameter(&"mask_from_alpha", mask_from_alpha)
	material.set_shader_parameter(&"layer_tint", tint)
	material.set_shader_parameter(&"world_origin_px", world_origin_px)
	material.set_shader_parameter(&"chunk_world_size_px", chunk_world_size_px)
	if _art_profile != null:
		material.set_shader_parameter(
			&"texture_world_size_px",
			_art_profile.texture_world_size
		)
