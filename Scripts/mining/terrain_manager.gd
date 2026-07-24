class_name TerrainManager
extends Node

## Owns terrain occupancy, mining damage, and encounter openings.

class DigResult:
	## Carries the terrain damage caused by one mining hit.
	var cells_removed: int = 0


	## Combines consecutive terrain damage into one resolved mining hit.
	func absorb(other: DigResult) -> void:
		cells_removed += other.cells_removed


## Reports newly opened terrain so presentation can reveal the damage.
signal terrain_damaged(
	destroyed_cells: Array[Vector2i],
	horizontal_direction: int
)
## Reports related narrow paths as one batch so presentation uploads once.
signal terrain_paths_damaged(
	destroyed_paths: Array,
	horizontal_direction: int
)
## Reports 2D view movement so world presentation follows the mining face.
signal view_position_changed(view_cell_position: Vector2)

@export var config: MiningConfig
@export var encounter_config: DepthEncounterConfig

# Masks prevent destroyed cells from being mined or collected twice.
var _destruction_masks: Dictionary[int, PackedByteArray] = {}
var _current_view_x: float
var _current_view_y: float
var _random := RandomNumberGenerator.new()


## Initializes coordinate conversion at the starting surface.
func _ready() -> void:
	_current_view_x = float(config.terrain_width_cells) * 0.5
	_current_view_y = float(config.initial_surface_row)
	_random.randomize()


## Clears a connected tunnel from the current column to the next landing.
func dig_tunnel(
	start_cell: Vector2i,
	depth_rows: int,
	half_width_cells: int,
	surface_contact_cell_x: int = -1,
	target_cell_x: int = -1
) -> DigResult:
	var result := DigResult.new()
	if depth_rows <= 0 or not _is_mineable_cell(start_cell):
		return result

	var destroyed_cells: Array[Vector2i] = []
	var final_mineable_row := config.get_bottom_surface_row()
	var tunnel_end_row := mini(
		start_cell.y + depth_rows,
		final_mineable_row
	)
	var safe_target_cell_x := (
		start_cell.x
		if target_cell_x < 0
		else clampi(target_cell_x, 0, config.terrain_width_cells - 1)
	)
	var horizontal_direction := signi(
		safe_target_cell_x - start_cell.x
	)
	var tunnel_row_count := tunnel_end_row - start_cell.y
	for row_index in range(tunnel_row_count):
		var cell_y := start_cell.y + row_index
		var path_center_x: int = _get_tunnel_center_x(
			start_cell.x,
			safe_target_cell_x,
			row_index,
			tunnel_row_count
		)
		# Test the same center column the player follows. Checking only the
		# starting column made diagonal paths stop at an unrelated chamber wall.
		if _is_encounter_chamber_cell(Vector2i(path_center_x, cell_y)):
			break
		var left_cell_x := path_center_x - half_width_cells
		var right_cell_x := path_center_x + half_width_cells
		if cell_y == start_cell.y and surface_contact_cell_x >= 0:
			left_cell_x = mini(left_cell_x, surface_contact_cell_x)
			right_cell_x = maxi(right_cell_x, surface_contact_cell_x)
		for cell_x in range(left_cell_x, right_cell_x + 1):
			var cell := Vector2i(cell_x, cell_y)
			if not _is_mineable_cell(cell):
				continue
			_set_cell_destroyed(cell)
			destroyed_cells.append(cell)
			result.cells_removed += 1

	if not destroyed_cells.is_empty():
		terrain_damaged.emit(
			destroyed_cells,
			clampi(horizontal_direction, -1, 1)
		)
	return result


## Breaks a jagged downward path with smaller branches from its sides.
func dig_branching_lightning(
	start_cell: Vector2i,
	depth_rows: int,
	branch_count: int,
	branch_length_cells: int
) -> DigResult:
	var result := DigResult.new()
	if depth_rows <= 0 or not _is_mineable_cell(start_cell):
		return result

	var authored_paths: Array = []
	var trunk_path: Array[Vector2i] = []
	var trunk_cell := start_cell
	for row_index in range(depth_rows):
		if row_index > 0:
			trunk_cell.x = clampi(
				trunk_cell.x + _random.randi_range(-1, 1),
				0,
				config.terrain_width_cells - 1
			)
			trunk_cell.y += 1
		if not is_ground_cell(trunk_cell):
			break
		trunk_path.append(trunk_cell)
	if trunk_path.is_empty():
		return result
	authored_paths.append(trunk_path)

	for branch_index in range(maxi(branch_count, 0)):
		var seed_minimum := mini(
			trunk_path.size() - 1,
			maxi(1, trunk_path.size() / 4)
		)
		var seed_index := _random.randi_range(
			seed_minimum,
			trunk_path.size() - 1
		)
		var branch_cell := trunk_path[seed_index]
		var branch_direction := (
			-1
			if branch_index % 2 == 0
			else 1
		)
		if _random.randi_range(0, 1) == 1:
			branch_direction *= -1
		var branch_path: Array[Vector2i] = []
		var branch_length := _random.randi_range(
			maxi(2, branch_length_cells / 2),
			maxi(branch_length_cells, 2)
		)
		for step_index in range(branch_length):
			branch_cell.x = clampi(
				branch_cell.x + branch_direction,
				0,
				config.terrain_width_cells - 1
			)
			if step_index % 2 == 0 or _random.randi_range(0, 1) == 1:
				branch_cell.y += 1
			if not is_ground_cell(branch_cell):
				break
			branch_path.append(branch_cell)
		if not branch_path.is_empty():
			authored_paths.append(branch_path)

	var destroyed_paths: Array = []
	var destroyed_lookup: Dictionary[Vector2i, bool] = {}
	for authored_path: Array[Vector2i] in authored_paths:
		var destroyed_path: Array[Vector2i] = []
		for cell in authored_path:
			if destroyed_lookup.has(cell) or not _is_mineable_cell(cell):
				continue
			_set_cell_destroyed(cell)
			destroyed_lookup[cell] = true
			destroyed_path.append(cell)
			result.cells_removed += 1
		if not destroyed_path.is_empty():
			destroyed_paths.append(destroyed_path)

	if not destroyed_paths.is_empty():
		terrain_paths_damaged.emit(destroyed_paths, 0)
	return result


## Converts a screen x-coordinate into a terrain column.
func screen_x_to_terrain_cell_x(screen_x: float) -> int:
	var cell_size := float(config.terrain_cell_world_size)
	var cell_x := floori(
		_current_view_x
		+ (screen_x - config.terrain_screen_center_x) / cell_size
	)
	return clampi(cell_x, 0, config.terrain_width_cells - 1)


## Converts a screen position into terrain-local coordinates.
func screen_to_terrain_position(screen_position: Vector2) -> Vector2:
	var cell_size := float(config.terrain_cell_world_size)
	return Vector2(
		_current_view_x * cell_size
			+ screen_position.x
			- config.terrain_screen_center_x,
		_current_view_y * cell_size
		+ screen_position.y
		- config.mining_face_screen_y
	)


## Converts terrain-local coordinates into a screen position.
func terrain_to_screen_position(terrain_position: Vector2) -> Vector2:
	var cell_size := float(config.terrain_cell_world_size)
	return Vector2(
		config.terrain_screen_center_x
			+ terrain_position.x
			- _current_view_x * cell_size,
		config.mining_face_screen_y
		+ terrain_position.y
		- _current_view_y * cell_size
	)


## Returns whether a terrain-local position is inside solid ground.
func is_solid_at_terrain_position(terrain_position: Vector2) -> bool:
	var cell_size := float(config.terrain_cell_world_size)
	var cell := Vector2i(
		floori(terrain_position.x / cell_size),
		floori(terrain_position.y / cell_size)
	)
	return is_solid_cell(cell)


## Returns whether a logical terrain cell currently supports the player.
func is_solid_cell(cell: Vector2i) -> bool:
	return is_ground_cell(cell) and not _is_cell_destroyed(cell)


## Returns whether a cell belongs to the undamaged terrain domain.
func is_ground_cell(cell: Vector2i) -> bool:
	if (
		cell.x < 0
		or cell.x >= config.terrain_width_cells
		or cell.y < config.initial_surface_row
		or cell.y > config.get_bottom_surface_row()
		or _is_encounter_chamber_cell(cell)
	):
		return false
	return true


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
		and not is_solid_cell(Vector2i(safe_x, cell_y))
	):
		cell_y += 1
	return cell_y


## Finds support along the exact centerline authored by dig_tunnel.
## After the sloped segment, the scan continues vertically through open
## chambers or destroyed floors at the final target column.
func find_tunnel_surface_cell(
	start_cell: Vector2i,
	target_cell_x: int,
	tunnel_depth_rows: int
) -> Vector2i:
	var bottom_surface_row: int = config.get_bottom_surface_row()
	var safe_start := Vector2i(
		clampi(start_cell.x, 0, config.terrain_width_cells - 1),
		clampi(
			start_cell.y,
			config.initial_surface_row,
			bottom_surface_row
		)
	)
	var safe_target_cell_x: int = clampi(
		target_cell_x,
		0,
		config.terrain_width_cells - 1
	)
	var tunnel_end_row: int = mini(
		safe_start.y + maxi(tunnel_depth_rows, 0),
		bottom_surface_row
	)
	var tunnel_row_count: int = tunnel_end_row - safe_start.y
	var cell_y: int = safe_start.y
	while cell_y < bottom_surface_row:
		var row_index: int = mini(
			cell_y - safe_start.y,
			tunnel_row_count
		)
		var path_center_x: int = _get_tunnel_center_x(
			safe_start.x,
			safe_target_cell_x,
			row_index,
			tunnel_row_count
		)
		var candidate: Vector2i = Vector2i(path_center_x, cell_y)
		if is_solid_cell(candidate):
			return candidate
		cell_y += 1
	return Vector2i(safe_target_cell_x, bottom_surface_row)


## Updates the view position used by terrain-to-screen conversion.
func set_view_position(view_cell_position: Vector2) -> void:
	if (
		is_equal_approx(_current_view_x, view_cell_position.x)
		and is_equal_approx(_current_view_y, view_cell_position.y)
	):
		return
	_current_view_x = view_cell_position.x
	_current_view_y = view_cell_position.y
	view_position_changed.emit(view_cell_position)


## Returns the view position used by newly attached presentation.
func get_view_position() -> Vector2:
	return Vector2(_current_view_x, _current_view_y)


## Reports whether a row is the intact top of the run or an authored room.
func is_authored_landing_floor(world_row: int) -> bool:
	if world_row == config.initial_surface_row:
		return true
	if encounter_config == null:
		return false
	var depth_row := world_row - config.initial_surface_row
	for encounter in encounter_config.encounters:
		if (
			encounter != null
			and encounter.resolve_depth(config.total_run_depth) == depth_row
		):
			return true
	return false


## Returns whether a cell can be destroyed by a new hit.
func _is_mineable_cell(cell: Vector2i) -> bool:
	return is_ground_cell(cell) and not _is_cell_destroyed(cell)


## Returns whether a cell is inside an encounter chamber.
func _is_encounter_chamber_cell(cell: Vector2i) -> bool:
	if encounter_config == null:
		return false

	var depth_row := cell.y - config.initial_surface_row
	var chamber_bounds := (
		encounter_config.get_chamber_horizontal_bounds(
			depth_row,
			config.total_run_depth,
			config.terrain_width_cells
		)
	)
	if cell.x < chamber_bounds.x or cell.x >= chamber_bounds.y:
		return false

	return encounter_config.is_chamber_row(
		depth_row,
		config.total_run_depth
	)


## Returns whether a cell has already been destroyed by a hit.
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


## Resolves one row of the shared destruction and player-fall centerline.
func _get_tunnel_center_x(
	start_cell_x: int,
	target_cell_x: int,
	row_index: int,
	tunnel_row_count: int
) -> int:
	if tunnel_row_count <= 0 or row_index >= tunnel_row_count:
		return target_cell_x
	var path_progress: float = (
		1.0
		if tunnel_row_count <= 1
		else float(row_index) / float(tunnel_row_count - 1)
	)
	return roundi(
		lerpf(
			float(start_cell_x),
			float(target_cell_x),
			path_progress
		)
	)


## Saves one destroyed cell so later hits cannot collect it again.
func _set_cell_destroyed(cell: Vector2i) -> void:
	var chunk_index := _world_to_chunk_index(cell.y)
	var local_y := cell.y - chunk_index * config.chunk_height_cells
	var mask := _get_or_create_mask(chunk_index)
	var mask_offset := local_y * config.terrain_width_cells + cell.x
	mask[mask_offset] = 1
	_destruction_masks[chunk_index] = mask


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
