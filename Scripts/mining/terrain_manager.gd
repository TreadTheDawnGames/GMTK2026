class_name TerrainManager
extends Node2D

## Generates, damages, loads, and unloads terrain chunks.

class TerrainChunk:
	## Holds the image and sprite for one loaded chunk.
	var index: int
	var image: Image
	var texture: ImageTexture
	var sprite: Sprite2D


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


@export var config: MiningConfig
@export var encounter_config: DepthEncounterConfig

var _active_chunks: Dictionary = {}
# Masks exist only for damaged chunks, so untouched chunks unload completely.
var _destruction_masks: Dictionary = {}
var _current_view_y: float # Logical terrain row anchored at the mining face.
var _loaded_first_chunk: int = -1
var _loaded_last_chunk: int = -1


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
	if depth_cells <= 0 or not _is_solid_cell(terrain_position):
		return result

	var affected_chunks: Dictionary = {}
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
			if not _is_solid_cell(cell):
				continue
			var ore_definition := _ore_definition_for_cell(cell)
			if ore_definition != null:
				var ore_id := ore_definition.ore_id
				result.ore_yields[ore_id] = (
					int(result.ore_yields.get(ore_id, 0)) + 1
				)
			var chunk_index := _world_to_chunk_index(cell.y)
			_set_cell_destroyed(cell)
			affected_chunks[chunk_index] = true
			result.cells_removed += 1

	for chunk_index: int in affected_chunks:
		if not _active_chunks.has(chunk_index):
			continue
		var chunk := _active_chunks[chunk_index] as TerrainChunk
		chunk.texture.update(chunk.image)

	#Create a big fancy number that shows how much you dug this hit
	#DigNumber.create(terrain_position, depth_cells, get_tree())

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


## Loads and positions terrain for a new view depth.
func set_view_y(view_y: float) -> void:
	_current_view_y = view_y
	_refresh_active_chunks()
	_position_active_chunks()


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
		chunk.sprite.position = Vector2(
			config.terrain_screen_center_x,
			config.mining_face_screen_y
			+ (chunk_center_y - _current_view_y) * scale
		)


## Creates one terrain chunk and adds it to the scene.
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


## Removes one rendered chunk while keeping its damage data.
func _unload_chunk(chunk_index: int) -> void:
	var chunk := _active_chunks[chunk_index] as TerrainChunk
	chunk.sprite.queue_free()
	_active_chunks.erase(chunk_index)


## Builds one chunk image with chambers and saved terrain damage.
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
		if world_y > config.get_bottom_surface_row():
			continue
		for cell_x in range(config.terrain_width_cells):
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
					chunk_index
				)
			)
			image.set_pixel(cell_x, local_y, cell_color)
	return image


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


## Saves a destroyed cell and clears its visible pixel.
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


## Gets or creates the saved damage mask for a chunk.
func _get_or_create_mask(chunk_index: int) -> PackedByteArray:
	if _destruction_masks.has(chunk_index):
		return _destruction_masks[chunk_index] as PackedByteArray
	var mask := PackedByteArray()
	mask.resize(config.terrain_width_cells * config.chunk_height_cells)
	_destruction_masks[chunk_index] = mask
	return mask


## Returns the chunk index containing a terrain row.
func _world_to_chunk_index(world_y: int) -> int:
	return floori(float(world_y) / float(config.chunk_height_cells))


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
