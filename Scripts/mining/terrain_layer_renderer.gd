class_name TerrainLayerRenderer
extends Node2D

## Streams layered terrain art and reveals organic openings at mining impacts.

class TerrainChunkVisual:
	var root: Node2D
	var mask_images: Array[Image] = []
	var mask_textures: Array[ImageTexture] = []


class HoleMaskData:
	var erase_mask: Image
	var transparent_bounds: Rect2i


class ImpactStamp:
	var center: Vector2
	var core_radius: float
	var use_big_hole: bool
	var flip_x: bool
	var flip_y: bool
	var offset_rotation: float


const LAYER_SHADER: Shader = preload(
	"res://Shaders/terrain_layer.gdshader"
)
const SOLID_MASK_COLOR := Color.WHITE
const EMPTY_MASK_COLOR := Color.TRANSPARENT

@export_category("References")
@export var terrain_manager: TerrainManager
@export var profile: TerrainLayerProfile

var _active_chunks: Dictionary[int, TerrainChunkVisual] = {}
var _impact_stamps_by_chunk: Dictionary = {}
var _small_mask_data: Array[HoleMaskData] = []
var _big_mask_data: Array[HoleMaskData] = []
var _current_view_y: float
var _loaded_first_chunk: int = -1
var _loaded_last_chunk: int = -1


## Connects terrain events and loads the initial visible strata.
func _ready() -> void:
	if terrain_manager == null or profile == null:
		push_error(
			"TerrainLayerRenderer requires terrain_manager and profile."
		)
		return
	_connect_once(
		terrain_manager.terrain_damaged,
		_on_terrain_damaged
	)
	_connect_once(
		terrain_manager.view_y_changed,
		_on_view_y_changed
	)
	_prepare_hole_masks()
	_on_view_y_changed(terrain_manager.get_view_y())


## Saves and applies one organic opening for newly destroyed terrain.
func _on_terrain_damaged(
	destroyed_cells: Array[Vector2i],
	horizontal_direction: int
) -> void:
	if destroyed_cells.is_empty():
		return
	var stamp := _create_impact_stamp(
		destroyed_cells,
		horizontal_direction
	)
	var affected_chunk_indices := _register_impact_stamp(stamp)
	for chunk_index in affected_chunk_indices:
		if not _active_chunks.has(chunk_index):
			continue
		var chunk := _active_chunks[chunk_index]
		_apply_impact_stamp(chunk, chunk_index, stamp)
		_upload_chunk_masks(chunk)


## Repositions streamed terrain around the current mining face.
func _on_view_y_changed(view_y: float) -> void:
	_current_view_y = view_y
	_refresh_active_chunks()
	_position_active_chunks()


## Loads visible chunks plus the configured below-view margin.
func _refresh_active_chunks() -> void:
	var config := terrain_manager.config
	var viewport_height := get_viewport_rect().size.y
	var cell_size := float(config.terrain_cell_world_size)
	var top_world_y := (
		_current_view_y
		- config.mining_face_screen_y / cell_size
	)
	var bottom_world_y := (
		_current_view_y
		+ (viewport_height - config.mining_face_screen_y) / cell_size
	)
	var first_chunk := maxi(
		floori(top_world_y / float(config.chunk_height_cells)),
		0
	)
	var last_visible_chunk := maxi(
		floori(
			(bottom_world_y - 0.001)
			/ float(config.chunk_height_cells)
		),
		first_chunk
	)
	var last_chunk := mini(
		last_visible_chunk + config.preload_chunks_below,
		_world_row_to_chunk(config.get_bottom_surface_row())
	)
	if (
		first_chunk == _loaded_first_chunk
		and last_chunk == _loaded_last_chunk
	):
		return

	var chunks_to_unload: Array[int] = []
	for chunk_index: int in _active_chunks:
		if chunk_index < first_chunk or chunk_index > last_chunk:
			chunks_to_unload.append(chunk_index)
	for chunk_index in chunks_to_unload:
		_unload_chunk(chunk_index)

	for chunk_index in range(first_chunk, last_chunk + 1):
		if not _active_chunks.has(chunk_index):
			_load_chunk(chunk_index)

	_loaded_first_chunk = first_chunk
	_loaded_last_chunk = last_chunk


## Creates every visual stratum for one terrain chunk.
func _load_chunk(chunk_index: int) -> void:
	var layer_count := profile.get_layer_count()
	if layer_count <= 0:
		return

	var chunk := TerrainChunkVisual.new()
	chunk.root = Node2D.new()
	chunk.root.name = "LayeredTerrainChunk_%d" % chunk_index
	add_child(chunk.root)

	var base_mask := _build_chunk_base_mask(chunk_index)
	var chunk_world_size := _get_chunk_world_size()
	var world_origin := Vector2(
		0.0,
		float(chunk_index) * chunk_world_size.y
	)
	for layer_index in range(layer_count):
		var mask_image := base_mask.duplicate()
		var mask_texture := ImageTexture.create_from_image(mask_image)
		var sprite := Sprite2D.new()
		sprite.name = "TerrainLayer_%d" % layer_index
		sprite.centered = false
		sprite.texture = mask_texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.scale = Vector2.ONE * (
			float(terrain_manager.config.terrain_cell_world_size)
			/ float(profile.mask_pixels_per_cell)
		)
		sprite.z_index = profile.get_layer_z_index(layer_index)
		sprite.material = _create_layer_material(
			layer_index,
			world_origin,
			chunk_world_size
		)
		chunk.root.add_child(sprite)
		chunk.mask_images.append(mask_image)
		chunk.mask_textures.append(mask_texture)

	var saved_stamps: Array = _impact_stamps_by_chunk.get(
		chunk_index,
		[]
	)
	for saved_stamp: ImpactStamp in saved_stamps:
		_apply_impact_stamp(chunk, chunk_index, saved_stamp)
	_upload_chunk_masks(chunk)
	_active_chunks[chunk_index] = chunk


## Removes rendered chunk nodes while retaining their impact records.
func _unload_chunk(chunk_index: int) -> void:
	var chunk := _active_chunks[chunk_index]
	chunk.root.queue_free()
	_active_chunks.erase(chunk_index)


## Builds undamaged strata before replaying saved circular impacts.
func _build_chunk_base_mask(chunk_index: int) -> Image:
	var config := terrain_manager.config
	var mask_cell_size := profile.mask_pixels_per_cell
	var mask_size := _get_chunk_mask_size()
	var image := Image.create(
		mask_size.x,
		mask_size.y,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(EMPTY_MASK_COLOR)
	var chunk_start_row := chunk_index * config.chunk_height_cells
	for local_row in range(config.chunk_height_cells):
		var world_row := chunk_start_row + local_row
		for cell_x in range(config.terrain_width_cells):
			if not terrain_manager.is_ground_cell(
				Vector2i(cell_x, world_row)
			):
				continue
			image.fill_rect(
				Rect2i(
					cell_x * mask_cell_size,
					local_row * mask_cell_size,
					mask_cell_size,
					mask_cell_size
				),
				SOLID_MASK_COLOR
			)
	return image


## Keeps every loaded chunk aligned as the view follows the player.
func _position_active_chunks() -> void:
	var config := terrain_manager.config
	var cell_size := float(config.terrain_cell_world_size)
	var terrain_left := (
		config.terrain_screen_center_x
		- float(config.terrain_width_cells) * cell_size * 0.5
	)
	for chunk_index: int in _active_chunks:
		var chunk := _active_chunks[chunk_index]
		var chunk_start_row := (
			float(chunk_index) * float(config.chunk_height_cells)
		)
		chunk.root.position = Vector2(
			terrain_left,
			config.mining_face_screen_y
			+ (chunk_start_row - _current_view_y) * cell_size
		)


## Converts one hit's actual damage bounds into a persistent art stamp.
func _create_impact_stamp(
	destroyed_cells: Array[Vector2i],
	horizontal_direction: int
) -> ImpactStamp:
	var minimum_cell := destroyed_cells[0]
	var maximum_cell := destroyed_cells[0]
	for cell in destroyed_cells:
		minimum_cell.x = mini(minimum_cell.x, cell.x)
		minimum_cell.y = mini(minimum_cell.y, cell.y)
		maximum_cell.x = maxi(maximum_cell.x, cell.x)
		maximum_cell.y = maxi(maximum_cell.y, cell.y)

	var cell_size := terrain_manager.config.terrain_cell_world_size
	var stamp := ImpactStamp.new()
	var damage_rect := Rect2(
		Vector2(minimum_cell * cell_size),
		Vector2(
			(maximum_cell - minimum_cell + Vector2i.ONE)
			* cell_size
		)
	)
	stamp.center = damage_rect.get_center()
	stamp.core_radius = (
		maxf(damage_rect.size.x, damage_rect.size.y) * 0.5
	)
	stamp.use_big_hole = (
		stamp.core_radius * 2.0
		>= float(profile.big_hole_minimum_size)
	)
	var variation_hash := (
		minimum_cell.x * 73_856_093
		^ minimum_cell.y * 19_349_663
		^ destroyed_cells.size() * 83_492_791
	)
	stamp.flip_x = (
		horizontal_direction < 0
		or (horizontal_direction == 0 and variation_hash % 2 == 0)
	)
	stamp.flip_y = variation_hash % 3 == 0
	stamp.offset_rotation = (
		float(posmod(variation_hash, 4))
		* PI * 0.5
	)
	return stamp


## Stores a stamp beside every chunk its organic edge can touch.
func _register_impact_stamp(stamp: ImpactStamp) -> Array[int]:
	var affected_chunks: Array[int] = []
	var broad_rect := _get_stamp_broad_rect(stamp)
	var chunk_height := _get_chunk_world_size().y
	var first_chunk := maxi(
		floori(broad_rect.position.y / chunk_height),
		0
	)
	var last_chunk := maxi(
		floori(
			(broad_rect.end.y - 0.001)
			/ chunk_height
		),
		first_chunk
	)
	for chunk_index in range(first_chunk, last_chunk + 1):
		var stamps: Array = _impact_stamps_by_chunk.get(
			chunk_index,
			[]
		)
		stamps.append(stamp)
		_impact_stamps_by_chunk[chunk_index] = stamps
		affected_chunks.append(chunk_index)
	return affected_chunks


## Punches offset circular holes so every stratum has a distinct rim.
func _apply_impact_stamp(
	chunk: TerrainChunkVisual,
	chunk_index: int,
	stamp: ImpactStamp
) -> void:
	var layer_count := profile.get_layer_count()
	for layer_index in range(layer_count):
		if (
			profile.keep_back_layer_solid
			and layer_index == layer_count - 1
		):
			continue
		var mask_data := _get_hole_mask_data(
			layer_index,
			stamp.use_big_hole
		)
		if mask_data == null:
			continue
		var layers_below := layer_count - layer_index - 1
		var opening_growth := (
			profile.core_hole_padding
			+ profile.rim_width * layers_below
		)
		var opening_radius := (
			stamp.core_radius + float(opening_growth)
		)
		var layer_offset := (
			profile.get_layer_impact_offset(layer_index)
			.rotated(stamp.offset_rotation)
		)
		if stamp.flip_x:
			layer_offset.x *= -1.0
		if stamp.flip_y:
			layer_offset.y *= -1.0
		var opening_center := stamp.center + layer_offset
		var opening_rect := Rect2(
			opening_center - Vector2.ONE * opening_radius,
			Vector2.ONE * opening_radius * 2.0
		)
		_punch_hole(
			chunk.mask_images[layer_index],
			chunk_index,
			opening_rect,
			mask_data,
			stamp.flip_x,
			stamp.flip_y
		)


## Clears the transparent part of one authored mask from a chunk layer.
func _punch_hole(
	destination: Image,
	chunk_index: int,
	opening_world_rect: Rect2,
	mask_data: HoleMaskData,
	flip_x: bool,
	flip_y: bool
) -> void:
	var source_size := Vector2(mask_data.erase_mask.get_size())
	var source_bounds := Rect2(mask_data.transparent_bounds)
	if source_bounds.size.x <= 0.0 or source_bounds.size.y <= 0.0:
		return

	var full_stamp_size := Vector2(
		opening_world_rect.size.x
		* source_size.x / source_bounds.size.x,
		opening_world_rect.size.y
		* source_size.y / source_bounds.size.y
	)
	var full_stamp_position := (
		opening_world_rect.position
		- Vector2(source_bounds.position)
		* full_stamp_size / source_size
	)
	var full_stamp_rect := Rect2(
		full_stamp_position,
		full_stamp_size
	)
	var chunk_world_size := _get_chunk_world_size()
	var chunk_world_rect := Rect2(
		Vector2(
			0.0,
			float(chunk_index) * chunk_world_size.y
		),
		chunk_world_size
	)
	var affected_world_rect := full_stamp_rect.intersection(
		chunk_world_rect
	)
	if affected_world_rect.size.x <= 0.0 or affected_world_rect.size.y <= 0.0:
		return

	var mask_pixels_per_world_unit := (
		float(profile.mask_pixels_per_cell)
		/ float(terrain_manager.config.terrain_cell_world_size)
	)
	var stamp_size := Vector2i(
		maxi(
			ceili(
				full_stamp_size.x * mask_pixels_per_world_unit
			),
			1
		),
		maxi(
			ceili(
				full_stamp_size.y * mask_pixels_per_world_unit
			),
			1
		)
	)
	var resized_erase_mask := mask_data.erase_mask.duplicate()
	resized_erase_mask.resize(
		stamp_size.x,
		stamp_size.y,
		Image.INTERPOLATE_BILINEAR
	)
	if flip_x:
		resized_erase_mask.flip_x()
	if flip_y:
		resized_erase_mask.flip_y()

	var transparent_source := Image.create(
		stamp_size.x,
		stamp_size.y,
		false,
		Image.FORMAT_RGBA8
	)
	transparent_source.fill(EMPTY_MASK_COLOR)
	var chunk_mask_top := (
		chunk_index
		* terrain_manager.config.chunk_height_cells
		* profile.mask_pixels_per_cell
	)
	destination.blit_rect_mask(
		transparent_source,
		resized_erase_mask,
		Rect2i(Vector2i.ZERO, stamp_size),
		Vector2i(
			floori(
				full_stamp_position.x
				* mask_pixels_per_world_unit
			),
			floori(
				full_stamp_position.y
				* mask_pixels_per_world_unit
			) - chunk_mask_top
		)
	)


## Caches authored mask images and their transparent bounds.
func _prepare_hole_masks() -> void:
	_small_mask_data.clear()
	_big_mask_data.clear()
	for layer_index in range(profile.get_layer_count()):
		_small_mask_data.append(
			_create_hole_mask_data(
				profile.get_hole_mask(layer_index, false)
			)
		)
		_big_mask_data.append(
			_create_hole_mask_data(
				profile.get_hole_mask(layer_index, true)
			)
		)


## Loads one mask and measures the opening the artist authored.
func _create_hole_mask_data(texture: Texture2D) -> HoleMaskData:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null

	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i(-1, -1)
	var erase_mask := Image.create(
		image.get_width(),
		image.get_height(),
		false,
		Image.FORMAT_RGBA8
	)
	erase_mask.fill(EMPTY_MASK_COLOR)
	for source_y in range(image.get_height()):
		for source_x in range(image.get_width()):
			if (
				image.get_pixel(source_x, source_y).a
				> profile.transparent_alpha_threshold
			):
				continue
			minimum.x = mini(minimum.x, source_x)
			minimum.y = mini(minimum.y, source_y)
			maximum.x = maxi(maximum.x, source_x)
			maximum.y = maxi(maximum.y, source_y)
			erase_mask.set_pixel(
				source_x,
				source_y,
				SOLID_MASK_COLOR
			)
	if maximum.x < minimum.x or maximum.y < minimum.y:
		return null

	var data := HoleMaskData.new()
	data.erase_mask = erase_mask
	data.transparent_bounds = Rect2i(
		minimum,
		maximum - minimum + Vector2i.ONE
	)
	return data


## Returns the cached opening for one layer and impact size.
func _get_hole_mask_data(
	layer_index: int,
	use_big_hole: bool
) -> HoleMaskData:
	var mask_data := (
		_big_mask_data
		if use_big_hole
		else _small_mask_data
	)
	if layer_index < 0 or layer_index >= mask_data.size():
		return null
	return mask_data[layer_index]


## Builds one shader material for a terrain stratum.
func _create_layer_material(
	layer_index: int,
	world_origin: Vector2,
	chunk_world_size: Vector2
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = LAYER_SHADER
	var fill_texture := profile.get_fill_texture(layer_index)
	material.set_shader_parameter(&"fill_texture", fill_texture)
	material.set_shader_parameter(
		&"use_fill_texture",
		fill_texture != null
	)
	material.set_shader_parameter(
		&"layer_tint",
		profile.layer_tints[layer_index]
	)
	material.set_shader_parameter(&"world_origin", world_origin)
	material.set_shader_parameter(
		&"chunk_world_size",
		chunk_world_size
	)
	material.set_shader_parameter(
		&"fill_texture_world_size",
		profile.fill_texture_world_size
	)
	return material


## Uploads all changed masks for one impact or loaded chunk.
func _upload_chunk_masks(chunk: TerrainChunkVisual) -> void:
	for layer_index in range(chunk.mask_images.size()):
		chunk.mask_textures[layer_index].update(
			chunk.mask_images[layer_index]
		)


## Returns a conservative area containing every layer opening.
func _get_stamp_broad_rect(stamp: ImpactStamp) -> Rect2:
	var layer_growth := (
		profile.core_hole_padding
		+ profile.rim_width * maxi(profile.get_layer_count() - 1, 0)
	)
	var maximum_offset := 0.0
	for layer_index in range(profile.get_layer_count()):
		maximum_offset = maxf(
			maximum_offset,
			profile.get_layer_impact_offset(layer_index).length()
		)
	var broad_radius := (
		stamp.core_radius
		+ float(layer_growth)
		+ maximum_offset
	)
	return Rect2(
		stamp.center - Vector2.ONE * broad_radius,
		Vector2.ONE * broad_radius * 2.0
	)


## Returns one chunk's dimensions in terrain-local units.
func _get_chunk_world_size() -> Vector2:
	var config := terrain_manager.config
	return Vector2(
		config.terrain_width_cells
			* config.terrain_cell_world_size,
		config.chunk_height_cells
			* config.terrain_cell_world_size
	)


## Returns one chunk's editable mask dimensions.
func _get_chunk_mask_size() -> Vector2i:
	var config := terrain_manager.config
	return Vector2i(
		config.terrain_width_cells
			* profile.mask_pixels_per_cell,
		config.chunk_height_cells
			* profile.mask_pixels_per_cell
	)


## Returns the chunk index containing a terrain row.
func _world_row_to_chunk(world_row: int) -> int:
	return floori(
		float(world_row)
		/ float(terrain_manager.config.chunk_height_cells)
	)


## Connects one signal without creating a duplicate route.
func _connect_once(source_signal: Signal, target: Callable) -> void:
	if not source_signal.is_connected(target):
		source_signal.connect(target)
