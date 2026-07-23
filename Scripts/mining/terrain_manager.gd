class_name TerrainManager
extends Node2D

## Generates, damages, loads, and unloads terrain chunks.

signal terrain_cells_destroyed(
	cells: Array[Vector2i],
	impact_cell: Vector2i
)

class TerrainChunk:
	## Holds gameplay masks and the reusable visual for one loaded chunk.
	var index: int
	var composite_image: Image
	var composite_texture: ImageTexture
	var solid_mask_image: Image
	var solid_mask_texture: ImageTexture
	var domain_mask_image: Image
	var domain_mask_texture: ImageTexture
	var edge_mask_image: Image
	var edge_mask_texture: ImageTexture
	var ore_mask_image: Image
	var ore_mask_texture: ImageTexture
	var art_profile: TerrainArtProfile
	var visual: TerrainChunkVisual


class DigResult:
	## Carries terrain damage and collectible yields from one mining hit.
	var cells_removed: int = 0
	var ore_yields: Dictionary = {}


	## Combines consecutive terrain damage into one resolved mining hit.
	func absorb(other: DigResult) -> void:
		cells_removed += other.cells_removed
		for ore_id: StringName in other.ore_yields:
			ore_yields[ore_id] = (
				int(ore_yields.get(ore_id, 0))
				+ int(other.ore_yields[ore_id])
			)


@export_category("Configuration")
@export var config: MiningConfig
@export var encounter_config: DepthEncounterConfig
@export var art_profile_override: TerrainArtProfile

@export_category("Composition")
@export var chunk_visual_scene: PackedScene
@export var progressive_breaking_enabled: bool = false

var _active_chunks: Dictionary = {}
# Reserved masks prevent queued hits from mining the same cell twice.
var _destruction_masks: Dictionary = {}
# Revealed masks are the physical surface beneath the player's feet.
var _revealed_destruction_masks: Dictionary = {}
# Partial fades survive chunk streaming until their cells become physical air.
var _cell_fade_alphas: Dictionary = {}
var _current_view_y: float # Logical terrain row anchored at the mining face.
var _loaded_first_chunk: int = -1
var _loaded_last_chunk: int = -1
var _debug_view_mode: TerrainChunkVisual.ViewMode = (
	TerrainChunkVisual.ViewMode.FINAL
)


## Loads the terrain around the starting surface.
func _ready() -> void:
	set_view_y(float(config.initial_surface_row))


## Clears a safe vertical shaft with an optional extension toward the aimed side.
func dig_tunnel(
	terrain_position: Vector2i,
	depth_cells: int,
	half_width_cells: int,
	surface_contact_x: int = -1,
	horizontal_direction: int = 0,
	directional_reach_cells: int = 0
) -> DigResult:
	var result := DigResult.new()
	if depth_cells <= 0 or not _is_mineable_cell(terrain_position):
		return result

	var destroyed_cells: Array[Vector2i] = []
	var final_mineable_row := config.get_bottom_surface_row()
	var tunnel_end_row := mini(
		terrain_position.y + depth_cells,
		final_mineable_row
	)
	for cell_y in range(terrain_position.y, tunnel_end_row):
		# Reaching a chamber opens the full fall without damaging its floor.
		if _is_encounter_chamber_cell(Vector2i(terrain_position.x, cell_y)):
			break
		var left_cell_x := terrain_position.x - half_width_cells
		var right_cell_x := terrain_position.x + half_width_cells
		if horizontal_direction < 0:
			left_cell_x -= maxi(directional_reach_cells, 0)
		elif horizontal_direction > 0:
			right_cell_x += maxi(directional_reach_cells, 0)
		if cell_y == terrain_position.y and surface_contact_x >= 0:
			left_cell_x = mini(left_cell_x, surface_contact_x)
			right_cell_x = maxi(right_cell_x, surface_contact_x)
		for cell_x in range(left_cell_x, right_cell_x + 1):
			var cell := Vector2i(cell_x, cell_y)
			if not _is_mineable_cell(cell):
				continue
			var ore_definition := _ore_definition_for_cell(cell)
			if ore_definition != null:
				var ore_id := ore_definition.ore_id
				result.ore_yields[ore_id] = (
					int(result.ore_yields.get(ore_id, 0)) + 1
				)
			_set_cell_destroyed(cell)
			destroyed_cells.append(cell)
			result.cells_removed += 1

	_present_destroyed_cells(
		destroyed_cells,
		Vector2i(
			surface_contact_x
				if surface_contact_x >= 0
				else terrain_position.x,
			terrain_position.y
		)
	)

	return result


## Stamps a non-legacy brush for the standalone terrain preview.
func stamp_preview_brush(
	center: Vector2i,
	brush: MiningBrushDefinition,
	combo: int
) -> DigResult:
	var result := DigResult.new()
	if brush == null or brush.shape == MiningBrushDefinition.Shape.LEGACY_TUNNEL:
		return result
	var destroyed_cells: Array[Vector2i] = []
	for cell in brush.get_stamp_cells(center, combo):
		if not _is_mineable_cell(cell):
			continue
		var ore_definition := _ore_definition_for_cell(cell)
		if ore_definition != null:
			var ore_id := ore_definition.ore_id
			result.ore_yields[ore_id] = (
				int(result.ore_yields.get(ore_id, 0)) + 1
			)
		_set_cell_destroyed(cell)
		destroyed_cells.append(cell)
		result.cells_removed += 1
	_present_destroyed_cells(destroyed_cells, center)
	return result


## Converts a screen x-coordinate into a terrain column.
func screen_x_to_terrain_cell_x(screen_x: float) -> int:
	var cell_x := floori(
		(screen_x - config.terrain_screen_center_x)
		/ float(config.logical_pixel_scale)
		+ float(config.terrain_width_cells) * 0.5
	)
	return clampi(cell_x, 0, config.terrain_width_cells - 1)


## Converts a screen position into terrain pixel coordinates.
func screen_to_terrain_position(screen_position: Vector2) -> Vector2:
	var scale := float(config.logical_pixel_scale)
	var terrain_left := (
		config.terrain_screen_center_x
		- float(config.terrain_width_cells) * scale * 0.5
	)
	return Vector2(
		screen_position.x - terrain_left,
		_current_view_y * scale
		+ screen_position.y
		- config.mining_face_screen_y
	)


## Converts terrain pixel coordinates into a screen position.
func terrain_to_screen_position(terrain_position: Vector2) -> Vector2:
	var scale := float(config.logical_pixel_scale)
	var terrain_left := (
		config.terrain_screen_center_x
		- float(config.terrain_width_cells) * scale * 0.5
	)
	return Vector2(
		terrain_left + terrain_position.x,
		config.mining_face_screen_y
		+ terrain_position.y
		- _current_view_y * scale
	)


## Returns whether a terrain pixel is inside solid dirt.
func is_solid_at_terrain_position(terrain_position: Vector2) -> bool:
	var scale := float(config.logical_pixel_scale)
	var cell := Vector2i(
		floori(terrain_position.x / scale),
		floori(terrain_position.y / scale)
	)
	return _is_solid_cell(cell)


## Finds the next solid row beneath a terrain position.
func find_surface_row(cell_x: int, starting_row: int) -> int:
	var safe_x := clampi(cell_x, 0, config.terrain_width_cells - 1)
	var bottom_surface_row := config.get_bottom_surface_row()
	var cell_y := clampi(
		starting_row,
		config.initial_surface_row,
		bottom_surface_row
	)
	while (
		cell_y < bottom_surface_row
		and not _is_solid_cell(Vector2i(safe_x, cell_y))
	):
		cell_y += 1
	return cell_y


## Finds the landing row after all reserved breakage completes.
func find_reserved_surface_row(cell_x: int, starting_row: int) -> int:
	var safe_x := clampi(cell_x, 0, config.terrain_width_cells - 1)
	var bottom_surface_row := config.get_bottom_surface_row()
	var cell_y := clampi(
		starting_row,
		config.initial_surface_row,
		bottom_surface_row
	)
	while (
		cell_y < bottom_surface_row
		and not _is_mineable_cell(Vector2i(safe_x, cell_y))
	):
		cell_y += 1
	return cell_y


## Loads and positions terrain for a new view depth.
func set_view_y(view_y: float) -> void:
	_current_view_y = view_y
	_refresh_active_chunks()
	_position_active_chunks()


## Restores untouched terrain for preview and iteration scenes.
func reset_terrain() -> void:
	_destruction_masks.clear()
	_revealed_destruction_masks.clear()
	_cell_fade_alphas.clear()
	for chunk_index: int in _active_chunks.keys():
		_unload_chunk(chunk_index)
	_loaded_first_chunk = -1
	_loaded_last_chunk = -1
	set_view_y(_current_view_y)


## Shows the final terrain or one generated mask on every loaded chunk.
func set_debug_view_mode(view_mode: TerrainChunkVisual.ViewMode) -> void:
	_debug_view_mode = view_mode
	for chunk_index: int in _active_chunks:
		var chunk := _active_chunks[chunk_index] as TerrainChunk
		if _debug_view_mode == TerrainChunkVisual.ViewMode.EDGE_MASK:
			_rebuild_edge_mask(chunk)
			chunk.visual.update_edge_texture(chunk.edge_mask_image)
		chunk.visual.set_view_mode(_debug_view_mode)


## Reveals authoritative destruction in the current visual textures.
func reveal_destroyed_cells(cells: Array[Vector2i]) -> void:
	var cell_alphas: Dictionary = {}
	for cell in cells:
		cell_alphas[cell] = 0.0
	apply_destroyed_cell_fades(cell_alphas)


## Fades reserved pixels and commits cells whose fade reaches zero.
func apply_destroyed_cell_fades(cell_alphas: Dictionary) -> void:
	var affected_chunks: Dictionary = {}
	var edge_source_chunks: Dictionary = {}
	for cell: Vector2i in cell_alphas:
		var alpha := clampf(float(cell_alphas[cell]), 0.0, 1.0)
		if alpha <= 0.0:
			_cell_fade_alphas.erase(cell)
			_set_cell_revealed_destroyed(cell)
		else:
			_cell_fade_alphas[cell] = alpha
		var chunk_index := _world_to_chunk_index(cell.y)
		if not _active_chunks.has(chunk_index):
			continue
		var chunk := _active_chunks[chunk_index] as TerrainChunk
		var local_y := (
			cell.y - chunk_index * config.chunk_height_cells
		)
		var composite_color := chunk.composite_image.get_pixel(
			cell.x,
			local_y
		)
		composite_color.a = alpha
		chunk.composite_image.set_pixel(cell.x, local_y, composite_color)
		chunk.solid_mask_image.set_pixel(
			cell.x,
			local_y,
			Color(alpha, alpha, alpha, 1.0)
		)
		var ore_color := chunk.ore_mask_image.get_pixel(cell.x, local_y)
		ore_color.a = alpha
		chunk.ore_mask_image.set_pixel(cell.x, local_y, ore_color)
		affected_chunks[chunk_index] = true
		if alpha <= 0.0:
			edge_source_chunks[chunk_index] = true
	_refresh_affected_chunks(affected_chunks, edge_source_chunks)


## Loads nearby chunks and unloads chunks outside the view range.
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
	var last_chunk := mini(
		last_visible_chunk + config.preload_chunks_below,
		_world_to_chunk_index(config.get_bottom_surface_row())
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


## Positions loaded chunks around the current view depth.
func _position_active_chunks() -> void:
	var scale := float(config.logical_pixel_scale)
	for chunk_index: int in _active_chunks:
		var chunk := _active_chunks[chunk_index] as TerrainChunk
		var chunk_center_y := (
			float(chunk_index * config.chunk_height_cells)
			+ float(config.chunk_height_cells) * 0.5
		)
		chunk.visual.position = Vector2(
			config.terrain_screen_center_x,
			config.mining_face_screen_y
			+ (chunk_center_y - _current_view_y) * scale
		)


## Creates one terrain chunk and adds it to the scene.
func _load_chunk(chunk_index: int) -> void:
	if chunk_visual_scene == null:
		push_error("TerrainManager requires a chunk visual scene.")
		return
	var chunk := TerrainChunk.new()
	chunk.index = chunk_index
	chunk.art_profile = _art_profile_for_chunk(chunk_index)
	_build_chunk_images(chunk)
	chunk.composite_texture = ImageTexture.create_from_image(
		chunk.composite_image
	)
	chunk.solid_mask_texture = ImageTexture.create_from_image(
		chunk.solid_mask_image
	)
	chunk.domain_mask_texture = ImageTexture.create_from_image(
		chunk.domain_mask_image
	)
	chunk.edge_mask_texture = ImageTexture.create_from_image(
		chunk.edge_mask_image
	)
	chunk.ore_mask_texture = ImageTexture.create_from_image(
		chunk.ore_mask_image
	)
	chunk.visual = chunk_visual_scene.instantiate() as TerrainChunkVisual
	chunk.visual.name = "TerrainChunk_%d" % chunk_index
	chunk.visual.scale = Vector2.ONE * config.logical_pixel_scale
	var chunk_origin_px := Vector2(
		0.0,
		float(chunk_index * config.chunk_height_cells)
			* config.logical_pixel_scale
	)
	var chunk_world_size_px := Vector2(
		config.terrain_width_cells,
		config.chunk_height_cells
	) * config.logical_pixel_scale
	chunk.visual.configure(
		chunk.composite_texture,
		chunk.solid_mask_texture,
		chunk.domain_mask_texture,
		chunk.edge_mask_texture,
		chunk.ore_mask_texture,
		chunk.art_profile,
		chunk_origin_px,
		chunk_world_size_px
	)
	chunk.visual.set_view_mode(_debug_view_mode)
	add_child(chunk.visual)
	_active_chunks[chunk_index] = chunk


## Removes one rendered chunk while keeping its damage data.
func _unload_chunk(chunk_index: int) -> void:
	var chunk := _active_chunks[chunk_index] as TerrainChunk
	chunk.visual.queue_free()
	_active_chunks.erase(chunk_index)


## Builds the current composite plus solid, edge, and ore mask images.
func _build_chunk_images(chunk: TerrainChunk) -> void:
	chunk.composite_image = Image.create(
		config.terrain_width_cells,
		config.chunk_height_cells,
		false,
		Image.FORMAT_RGBA8
	)
	chunk.composite_image.fill(Color.TRANSPARENT)
	chunk.solid_mask_image = Image.create(
		config.terrain_width_cells,
		config.chunk_height_cells,
		false,
		Image.FORMAT_L8
	)
	chunk.solid_mask_image.fill(Color.BLACK)
	chunk.domain_mask_image = Image.create(
		config.terrain_width_cells,
		config.chunk_height_cells,
		false,
		Image.FORMAT_L8
	)
	chunk.domain_mask_image.fill(Color.BLACK)
	chunk.edge_mask_image = Image.create(
		config.terrain_width_cells,
		config.chunk_height_cells,
		false,
		Image.FORMAT_L8
	)
	chunk.edge_mask_image.fill(Color.BLACK)
	chunk.ore_mask_image = Image.create(
		config.terrain_width_cells,
		config.chunk_height_cells,
		false,
		Image.FORMAT_RGBA8
	)
	chunk.ore_mask_image.fill(Color.TRANSPARENT)
	var has_destruction := _revealed_destruction_masks.has(chunk.index)
	var mask := PackedByteArray()
	if has_destruction:
		mask = (
			_revealed_destruction_masks[chunk.index]
			as PackedByteArray
		)
	var chunk_start_y := chunk.index * config.chunk_height_cells

	for local_y in range(config.chunk_height_cells):
		var world_y := chunk_start_y + local_y
		if world_y < config.initial_surface_row:
			continue
		if world_y > config.get_bottom_surface_row():
			continue
		for cell_x in range(config.terrain_width_cells):
			chunk.domain_mask_image.set_pixel(
				cell_x,
				local_y,
				Color.WHITE
			)
			var cell := Vector2i(cell_x, world_y)
			if _is_encounter_chamber_cell(cell):
				continue
			var mask_offset := (
				local_y * config.terrain_width_cells
				+ cell_x
			)
			if has_destruction and mask[mask_offset] != 0:
				continue
			var ore_definition := _ore_definition_for_cell(cell)
			var cell_color := (
				ore_definition.color
				if ore_definition != null
				else _terrain_color_for_cell(
					cell_x,
					world_y,
					chunk.index
				)
			)
			chunk.composite_image.set_pixel(cell_x, local_y, cell_color)
			chunk.solid_mask_image.set_pixel(
				cell_x,
				local_y,
				Color.WHITE
			)
			if ore_definition != null:
				chunk.ore_mask_image.set_pixel(
					cell_x,
					local_y,
					ore_definition.color
				)
	for cell: Vector2i in _cell_fade_alphas:
		if _world_to_chunk_index(cell.y) != chunk.index:
			continue
		var local_y := (
			cell.y - chunk.index * config.chunk_height_cells
		)
		var alpha := float(_cell_fade_alphas[cell])
		var composite_color := chunk.composite_image.get_pixel(
			cell.x,
			local_y
		)
		composite_color.a = alpha
		chunk.composite_image.set_pixel(cell.x, local_y, composite_color)
		chunk.solid_mask_image.set_pixel(
			cell.x,
			local_y,
			Color(alpha, alpha, alpha, 1.0)
		)
		var ore_color := chunk.ore_mask_image.get_pixel(cell.x, local_y)
		ore_color.a = alpha
		chunk.ore_mask_image.set_pixel(cell.x, local_y, ore_color)
	if _should_generate_edges(chunk):
		_rebuild_edge_mask(chunk)


## Returns whether a terrain cell is solid.
func _is_solid_cell(cell: Vector2i) -> bool:
	if (
		cell.x < 0
		or cell.x >= config.terrain_width_cells
		or cell.y < config.initial_surface_row
		or cell.y > config.get_bottom_surface_row()
		or _is_encounter_chamber_cell(cell)
	):
		return false
	return not _is_cell_revealed_destroyed(cell)


## Returns whether a solid terrain cell is still available to a hit.
func _is_mineable_cell(cell: Vector2i) -> bool:
	if (
		cell.x < 0
		or cell.x >= config.terrain_width_cells
		or cell.y < config.initial_surface_row
		or cell.y > config.get_bottom_surface_row()
		or _is_encounter_chamber_cell(cell)
	):
		return false
	return not _is_cell_destroyed(cell)


## Returns whether a cell is inside an encounter chamber.
func _is_encounter_chamber_cell(cell: Vector2i) -> bool:
	if encounter_config == null:
		return false

	var scale := config.logical_pixel_scale
	var depth_row := cell.y - config.initial_surface_row
	var first_floor_row := roundi(
		float(encounter_config.first_floor_depth_px) / float(scale)
	)
	var interval_rows := maxi(
		roundi(
			float(encounter_config.repeat_interval_px) / float(scale)
		),
		1
	)
	var chamber_height_rows := maxi(
		ceili(
			float(encounter_config.chamber_height_px) / float(scale)
		),
		1
	)
	if depth_row < first_floor_row - chamber_height_rows:
		return false

	var chamber_width_cells := mini(
		ceili(
			float(encounter_config.chamber_width_px) / float(scale)
		),
		config.terrain_width_cells
	)
	var chamber_left := floori(
		float(config.terrain_width_cells - chamber_width_cells) * 0.5
	)
	var chamber_right := chamber_left + chamber_width_cells
	if cell.x < chamber_left or cell.x >= chamber_right:
		return false

	var floor_row := first_floor_row
	if depth_row > first_floor_row:
		floor_row += (
			ceili(
				float(depth_row - first_floor_row)
				/ float(interval_rows)
			)
			* interval_rows
		)
	var maximum_depth_rows := floori(
		float(config.total_run_depth_px) / float(scale)
	)
	if floor_row > maximum_depth_rows:
		return false
	var rows_until_floor := floor_row - depth_row
	return (
		rows_until_floor > 0
		and rows_until_floor <= chamber_height_rows
	)


## Returns whether a cell has already been destroyed.
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


## Returns whether a reserved cell has reached the visible break wave.
func _is_cell_revealed_destroyed(cell: Vector2i) -> bool:
	if cell.y < 0:
		return false
	var chunk_index := _world_to_chunk_index(cell.y)
	if not _revealed_destruction_masks.has(chunk_index):
		return false
	var local_y := cell.y - chunk_index * config.chunk_height_cells
	var mask := (
		_revealed_destruction_masks[chunk_index]
		as PackedByteArray
	)
	var mask_offset := local_y * config.terrain_width_cells + cell.x
	return mask[mask_offset] != 0


## Reserves a cell for one hit so later hits cannot claim it again.
func _set_cell_destroyed(cell: Vector2i) -> void:
	var chunk_index := _world_to_chunk_index(cell.y)
	var local_y := cell.y - chunk_index * config.chunk_height_cells
	var mask := _get_or_create_mask(chunk_index)
	var mask_offset := local_y * config.terrain_width_cells + cell.x
	mask[mask_offset] = 1
	_destruction_masks[chunk_index] = mask


## Commits one reserved cell to the physical and visible terrain state.
func _set_cell_revealed_destroyed(cell: Vector2i) -> void:
	var chunk_index := _world_to_chunk_index(cell.y)
	var local_y := cell.y - chunk_index * config.chunk_height_cells
	var mask := _get_or_create_revealed_mask(chunk_index)
	var mask_offset := local_y * config.terrain_width_cells + cell.x
	mask[mask_offset] = 1
	_revealed_destruction_masks[chunk_index] = mask


## Gets or creates the saved damage mask for a chunk.
func _get_or_create_mask(chunk_index: int) -> PackedByteArray:
	if _destruction_masks.has(chunk_index):
		return _destruction_masks[chunk_index] as PackedByteArray
	var mask := PackedByteArray()
	mask.resize(config.terrain_width_cells * config.chunk_height_cells)
	_destruction_masks[chunk_index] = mask
	return mask


## Gets or creates the physical damage mask advanced by the break wave.
func _get_or_create_revealed_mask(chunk_index: int) -> PackedByteArray:
	if _revealed_destruction_masks.has(chunk_index):
		return (
			_revealed_destruction_masks[chunk_index]
			as PackedByteArray
		)
	var mask := PackedByteArray()
	mask.resize(config.terrain_width_cells * config.chunk_height_cells)
	_revealed_destruction_masks[chunk_index] = mask
	return mask


## Returns the chunk index containing a terrain row.
func _world_to_chunk_index(world_y: int) -> int:
	return floori(float(world_y) / float(config.chunk_height_cells))


## Starts a progressive break wave or commits the hit immediately.
func _present_destroyed_cells(
	cells: Array[Vector2i],
	impact_cell: Vector2i
) -> void:
	if cells.is_empty():
		return
	if progressive_breaking_enabled:
		terrain_cells_destroyed.emit(cells, impact_cell)
		return
	reveal_destroyed_cells(cells)


## Uploads changed pixels and rebuilds edges only after physical removal.
func _refresh_affected_chunks(
	affected_chunks: Dictionary,
	edge_source_chunks: Dictionary
) -> void:
	for chunk_index: int in affected_chunks:
		if not _active_chunks.has(chunk_index):
			continue
		var chunk := _active_chunks[chunk_index] as TerrainChunk
		chunk.visual.update_damage_textures(
			chunk.composite_image,
			chunk.solid_mask_image,
			chunk.ore_mask_image
		)

	var edge_chunks_to_refresh: Dictionary = {}
	for chunk_index: int in edge_source_chunks:
		for refresh_index in range(chunk_index - 1, chunk_index + 2):
			if _active_chunks.has(refresh_index):
				edge_chunks_to_refresh[refresh_index] = true
	for chunk_index: int in edge_chunks_to_refresh:
		var chunk := _active_chunks[chunk_index] as TerrainChunk
		if _should_generate_edges(chunk):
			_rebuild_edge_mask(chunk)
			chunk.visual.update_edge_texture(chunk.edge_mask_image)


## Rebuilds exposed-edge data for one chunk without touching terrain state.
func _rebuild_edge_mask(chunk: TerrainChunk) -> void:
	chunk.edge_mask_image.fill(Color.BLACK)
	var edge_width := (
		chunk.art_profile.edge_width_cells
		if chunk.art_profile != null
		else 1
	)
	var chunk_start_y := chunk.index * config.chunk_height_cells
	for local_y in range(config.chunk_height_cells):
		var world_y := chunk_start_y + local_y
		for cell_x in range(config.terrain_width_cells):
			var cell := Vector2i(cell_x, world_y)
			if not _is_solid_cell(cell):
				continue
			if _has_air_neighbor(cell, edge_width):
				chunk.edge_mask_image.set_pixel(
					cell_x,
					local_y,
					Color.WHITE
				)


## Returns whether solid terrain is near open space within the edge width.
func _has_air_neighbor(cell: Vector2i, edge_width: int) -> bool:
	for offset_y in range(-edge_width, edge_width + 1):
		for offset_x in range(-edge_width, edge_width + 1):
			if absi(offset_x) + absi(offset_y) > edge_width:
				continue
			if offset_x == 0 and offset_y == 0:
				continue
			if not _is_solid_cell(cell + Vector2i(offset_x, offset_y)):
				return true
	return false


## Returns whether this chunk currently needs generated edge data.
func _should_generate_edges(chunk: TerrainChunk) -> bool:
	return (
		_debug_view_mode == TerrainChunkVisual.ViewMode.EDGE_MASK
		or (
			chunk.art_profile != null
			and chunk.art_profile.layered_rendering_enabled
		)
	)


## Selects an Inspector-authored art profile for one chunk depth.
func _art_profile_for_chunk(chunk_index: int) -> TerrainArtProfile:
	if art_profile_override != null:
		return art_profile_override
	var chunk_start_row := chunk_index * config.chunk_height_cells
	var depth_px := maxi(
		(chunk_start_row - config.initial_surface_row)
			* config.logical_pixel_scale,
		0
	)
	return config.get_art_profile_for_depth(depth_px)


## Returns a repeatable dirt color for one cell.
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


## Returns the deterministic ore occupying a solid terrain cell.
func _ore_definition_for_cell(cell: Vector2i) -> OreDefinition:
	if cell.y >= config.get_bottom_surface_row():
		return null
	var depth_px := (
		cell.y - config.initial_surface_row
	) * config.logical_pixel_scale
	var cell_hash := config.global_seed ^ 0x4F5245
	cell_hash ^= cell.x * 928_371_011
	cell_hash ^= cell.y * 689_287_499
	var roll := float(posmod(cell_hash, 10_000)) / 100.0
	var cumulative_chance := 0.0
	for ore_definition in config.ore_definitions:
		if (
			ore_definition == null
			or not ore_definition.can_spawn_at_depth(depth_px)
		):
			continue
		cumulative_chance += ore_definition.spawn_chance_percent
		if roll < cumulative_chance:
			return ore_definition
	return null
