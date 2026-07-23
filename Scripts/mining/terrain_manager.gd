class_name TerrainManager
extends Node2D

## Owns deterministic terrain generation, persistent destruction masks, and
## the viewport-bounded cache of rendered terrain chunks.

class TerrainChunk:
	## Runtime-only render data. Destruction persists separately after unload.
	var index: int
	var image: Image
	var texture: ImageTexture
	var sprite: Sprite2D


@export var config: MiningConfig

var _active_chunks: Dictionary = {}
# Masks exist only for damaged chunks, so untouched chunks unload completely.
var _destruction_masks: Dictionary = {}
var _current_view_y: float # Logical terrain row anchored at the mining face.
var _loaded_first_chunk: int = -1
var _loaded_last_chunk: int = -1


func _ready() -> void:
	set_view_y(float(config.initial_surface_row))


func chip_at(
	terrain_position: Vector2i,
	requested_cells: int,
	_impact_seed: int
) -> int:
	if requested_cells <= 0:
		return 0

	var removed_cells := 0
	var affected_chunks: Dictionary = {}
	var maximum_radius := maxi(config.terrain_width_cells, requested_cells)
	var reached_limit := false

	# Expanding rings keep every newly removed cell attached to the same bite.
	for radius in range(maximum_radius + 1):
		var inner_radius_squared := (radius - 1) * (radius - 1)
		var outer_radius_squared := radius * radius
		for cell_y in range(
			terrain_position.y - radius,
			terrain_position.y + radius + 1
		):
			for cell_x in range(
				terrain_position.x - radius,
				terrain_position.x + radius + 1
			):
				var cell := Vector2i(cell_x, cell_y)
				var offset := cell - terrain_position
				var distance_squared := offset.length_squared()
				if distance_squared > outer_radius_squared:
					continue
				if radius > 0 and distance_squared <= inner_radius_squared:
					continue
				if not _is_solid_cell(cell):
					continue

				var chunk_index := _world_to_chunk_index(cell.y)
				_set_cell_destroyed(cell)
				affected_chunks[chunk_index] = true
				removed_cells += 1
				if removed_cells >= requested_cells:
					reached_limit = true
					break
			if reached_limit:
				break
		if reached_limit:
			break

	for chunk_index: int in affected_chunks:
		if not _active_chunks.has(chunk_index):
			continue
		var chunk := _active_chunks[chunk_index] as TerrainChunk
		chunk.texture.update(chunk.image)

	return removed_cells


func screen_x_to_terrain_cell_x(screen_x: float) -> int:
	var cell_x := floori(
		(screen_x - config.terrain_screen_center_x)
		/ float(config.logical_pixel_scale)
		+ float(config.terrain_width_cells) * 0.5
	)
	return clampi(cell_x, 0, config.terrain_width_cells - 1)


func find_surface_row(cell_x: int, starting_row: int) -> int:
	var safe_x := clampi(cell_x, 0, config.terrain_width_cells - 1)
	var cell_y := maxi(starting_row, config.initial_surface_row)
	while _is_cell_destroyed(Vector2i(safe_x, cell_y)):
		cell_y += 1
	return cell_y


func set_view_y(view_y: float) -> void:
	_current_view_y = view_y
	_refresh_active_chunks()
	_position_active_chunks()


func _refresh_active_chunks() -> void:
	var viewport_height := get_viewport_rect().size.y
	var scale := float(config.logical_pixel_scale)
	var top_world_y := (
		_current_view_y
		- config.mining_face_screen_y / scale
	)
	var bottom_world_y := (
		_current_view_y
		+ (viewport_height - config.mining_face_screen_y) / scale
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
	# Keep only visible chunks plus the configured below-view generation margin.
	var last_chunk := last_visible_chunk + config.preload_chunks_below
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


func _position_active_chunks() -> void:
	var scale := float(config.logical_pixel_scale)
	for chunk_index: int in _active_chunks:
		var chunk := _active_chunks[chunk_index] as TerrainChunk
		var chunk_center_y := (
			float(chunk_index * config.chunk_height_cells)
			+ float(config.chunk_height_cells) * 0.5
		)
		chunk.sprite.position = Vector2(
			config.terrain_screen_center_x,
			config.mining_face_screen_y
			+ (chunk_center_y - _current_view_y) * scale
		)


func _load_chunk(chunk_index: int) -> void:
	var chunk := TerrainChunk.new()
	chunk.index = chunk_index
	chunk.image = _build_chunk_image(chunk_index)
	chunk.texture = ImageTexture.create_from_image(chunk.image)
	chunk.sprite = Sprite2D.new()
	chunk.sprite.name = "TerrainChunk_%d" % chunk_index
	chunk.sprite.texture = chunk.texture
	chunk.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	chunk.sprite.scale = Vector2.ONE * config.logical_pixel_scale
	add_child(chunk.sprite)
	_active_chunks[chunk_index] = chunk


func _unload_chunk(chunk_index: int) -> void:
	var chunk := _active_chunks[chunk_index] as TerrainChunk
	chunk.sprite.queue_free()
	_active_chunks.erase(chunk_index)


func _build_chunk_image(chunk_index: int) -> Image:
	var image := Image.create(
		config.terrain_width_cells,
		config.chunk_height_cells,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color.TRANSPARENT)
	var has_destruction := _destruction_masks.has(chunk_index)
	var mask := PackedByteArray()
	if has_destruction:
		mask = _destruction_masks[chunk_index] as PackedByteArray
	var chunk_start_y := chunk_index * config.chunk_height_cells

	for local_y in range(config.chunk_height_cells):
		var world_y := chunk_start_y + local_y
		if world_y < config.initial_surface_row:
			continue
		for cell_x in range(config.terrain_width_cells):
			var mask_offset := (
				local_y * config.terrain_width_cells
				+ cell_x
			)
			if has_destruction and mask[mask_offset] != 0:
				continue
			image.set_pixel(
				cell_x,
				local_y,
				_terrain_color_for_cell(cell_x, world_y, chunk_index)
			)
	return image


func _is_solid_cell(cell: Vector2i) -> bool:
	if (
		cell.x < 0
		or cell.x >= config.terrain_width_cells
		or cell.y < config.initial_surface_row
	):
		return false
	return not _is_cell_destroyed(cell)


func _is_cell_destroyed(cell: Vector2i) -> bool:
	if cell.y < 0:
		return false
	var chunk_index := _world_to_chunk_index(cell.y)
	if not _destruction_masks.has(chunk_index):
		return false
	var local_y := cell.y - chunk_index * config.chunk_height_cells
	var mask := _destruction_masks[chunk_index] as PackedByteArray
	var mask_offset := local_y * config.terrain_width_cells + cell.x
	return mask[mask_offset] != 0


func _set_cell_destroyed(cell: Vector2i) -> void:
	var chunk_index := _world_to_chunk_index(cell.y)
	var local_y := cell.y - chunk_index * config.chunk_height_cells
	var mask := _get_or_create_mask(chunk_index)
	var mask_offset := local_y * config.terrain_width_cells + cell.x
	mask[mask_offset] = 1
	_destruction_masks[chunk_index] = mask

	if _active_chunks.has(chunk_index):
		var chunk := _active_chunks[chunk_index] as TerrainChunk
		chunk.image.set_pixel(cell.x, local_y, Color.TRANSPARENT)


func _get_or_create_mask(chunk_index: int) -> PackedByteArray:
	if _destruction_masks.has(chunk_index):
		return _destruction_masks[chunk_index] as PackedByteArray
	var mask := PackedByteArray()
	mask.resize(config.terrain_width_cells * config.chunk_height_cells)
	_destruction_masks[chunk_index] = mask
	return mask


func _world_to_chunk_index(world_y: int) -> int:
	return floori(float(world_y) / float(config.chunk_height_cells))


func _terrain_color_for_cell(
	cell_x: int,
	world_y: int,
	chunk_index: int
) -> Color:
	var depth_band := world_y / config.depth_band_height_rows
	var cell_hash := config.global_seed
	cell_hash ^= cell_x * 374_761_393
	cell_hash ^= world_y * 668_265_263
	cell_hash ^= chunk_index * 2_147_483_647
	cell_hash ^= depth_band * 1_274_126_177
	if absi(cell_hash) % 17 == 0:
		return config.terrain_accent_color
	return config.terrain_color
