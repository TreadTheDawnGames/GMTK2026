@tool
class_name TerrainManager
extends Node

## Owns terrain occupancy, mining damage, and encounter openings.
## @tool so an editor terrain preview digs through this same authority rather
## than faking openings: what a designer breaks in the editor is a real
## dig_tunnel call against real cells, not a drawing that mimics one.

class DigResult:
	## Carries the terrain damage caused by one mining hit.
	var cells_removed: int = 0


	## Combines consecutive terrain damage into one resolved mining hit.
	func absorb(other: DigResult) -> void:
		cells_removed += other.cells_removed


class SculptPlacement:
	## Locates one authored cutscene room in world terrain cells, so a cell test
	## can reject a room with a rectangle check before converting coordinates.
	var sculpt: CutsceneTerrainSculpt
	var anchor_cell: Vector2i
	var world_rect: Rect2i


# One lightning event allocates at most 8 paths × 32 cells. Pickaxe exports use
# the same caps so direct callers cannot grow per-hit work beyond the web budget.
const MAX_LIGHTNING_CRACKS: int = 8
const MAX_LIGHTNING_CRACK_LENGTH: int = 32
const MAX_LIGHTNING_CRACK_DEPTH: int = 8


## Reports opened cells plus the pickaxe-contact center for their visual stamp.
signal terrain_damaged(
	destroyed_cells: Array[Vector2i],
	horizontal_direction: int,
	impact_origin_cell: Vector2i
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

# One bit per terrain cell prevents repeat mining. Growth is bounded by the
# configured run size (about 2.3 MiB for the default 192 x 100,000-cell run).
var _destruction_masks: Dictionary[int, PackedByteArray] = {}
var _current_view_x: float
var _current_view_y: float
var _random := RandomNumberGenerator.new()
# Built once from the encounter schedule and reused, because a cell test runs
# per cell per hit. Encounters without a sculpt contribute nothing, so a run
# with no authored rooms pays one empty-array check.
var _sculpt_placements: Array[SculptPlacement] = []
var _sculpt_placements_are_built: bool = false


## Initializes coordinate conversion at the starting surface.
func _ready() -> void:
	if config == null:
		if not Engine.is_editor_hint():
			push_error("TerrainManager requires a config.")
		return
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
	var path_start_cell_x := (
		start_cell.x
		if surface_contact_cell_x < 0
		else clampi(
			surface_contact_cell_x,
			0,
			config.terrain_width_cells - 1
		)
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
	var sculpt_placements := get_sculpt_placements()
	for row_index in range(tunnel_row_count):
		var cell_y := start_cell.y + row_index
		var path_center_x: int = _get_tunnel_center_x(
			path_start_cell_x,
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
		if cell_y == start_cell.y:
			# The pickaxe contact owns the blast center, while this short bridge
			# back to the player's feet keeps the new tunnel safely connected.
			left_cell_x = mini(left_cell_x, start_cell.x)
			right_cell_x = maxi(right_cell_x, start_cell.x)
		result.cells_removed += _destroy_tunnel_row(
			cell_y,
			left_cell_x,
			right_cell_x,
			sculpt_placements,
			destroyed_cells
		)

	if not destroyed_cells.is_empty():
		terrain_damaged.emit(
			destroyed_cells,
			clampi(horizontal_direction, -1, 1),
			Vector2i(path_start_cell_x, start_cell.y)
		)
	return result


## Destroys one contiguous tunnel row without repeating chunk and chamber
## lookups for every cell. Cell order and chamber exclusions match the former
## per-cell path exactly, so presentation and gem placement keep their contract.
func _destroy_tunnel_row(
	cell_y: int,
	left_cell_x: int,
	right_cell_x: int,
	sculpt_placements: Array[SculptPlacement],
	destroyed_cells: Array[Vector2i]
) -> int:
	var safe_left_x := maxi(left_cell_x, 0)
	var safe_right_x := mini(
		right_cell_x,
		config.terrain_width_cells - 1
	)
	if safe_left_x > safe_right_x:
		return 0

	var depth_row := cell_y - config.initial_surface_row
	var chamber_bounds := Vector2i.ZERO
	var is_chamber_row := false
	if encounter_config != null:
		chamber_bounds = encounter_config.get_chamber_horizontal_bounds(
			depth_row,
			config.total_run_depth,
			config.terrain_width_cells
		)
		is_chamber_row = encounter_config.is_chamber_row(
			depth_row,
			config.total_run_depth
		)

	var chunk_index := _world_to_chunk_index(cell_y)
	var local_y := cell_y - chunk_index * config.chunk_height_cells
	# dig_tunnel already proved the row center mineable, so this creates at most
	# one bounded mask per newly visited chunk, never one allocation per cell.
	var mask := _get_or_create_mask(chunk_index)
	var removed_count := 0
	for cell_x in range(safe_left_x, safe_right_x + 1):
		var cell := Vector2i(cell_x, cell_y)
		var is_inside_sculpt_opening := false
		var has_authored_sculpt_cell := false
		for placement in sculpt_placements:
			if not placement.world_rect.has_point(cell):
				continue
			has_authored_sculpt_cell = true
			is_inside_sculpt_opening = not placement.sculpt.is_solid_local(
				placement.sculpt.world_to_local(
					cell,
					placement.anchor_cell
				)
			)
			break
		if is_inside_sculpt_opening:
			continue
		if (
			not has_authored_sculpt_cell
			and is_chamber_row
			and cell_x >= chamber_bounds.x
			and cell_x < chamber_bounds.y
		):
			continue

		var mask_offset := (
			local_y * config.terrain_width_cells + cell_x
		)
		var byte_offset := mask_offset >> 3
		var bit_mask := 1 << (mask_offset & 7)
		if mask[byte_offset] & bit_mask != 0:
			continue
		mask[byte_offset] = mask[byte_offset] | bit_mask
		destroyed_cells.append(cell)
		removed_count += 1
	if removed_count > 0:
		_destruction_masks[chunk_index] = mask
	return removed_count


## Breaks shallow left/right cracks from a combo-sized blast's outer edge.
func dig_branching_lightning(
	impact_center_cell: Vector2i,
	impact_half_width_cells: int,
	combo_strength: float,
	max_crack_count: int,
	max_crack_length_cells: int,
	max_crack_depth_cells: int
) -> DigResult:
	var result := DigResult.new()
	if max_crack_count <= 0 or max_crack_length_cells <= 0:
		return result

	var effect_strength := clampf(combo_strength, 0.0, 1.0)
	var safe_max_crack_count := mini(
		max_crack_count,
		MAX_LIGHTNING_CRACKS
	)
	var safe_max_crack_length := mini(
		max_crack_length_cells,
		MAX_LIGHTNING_CRACK_LENGTH
	)
	var safe_max_crack_depth := clampi(
		max_crack_depth_cells,
		0,
		MAX_LIGHTNING_CRACK_DEPTH
	)
	var crack_count := clampi(
		roundi(
			lerpf(
				1.0,
				float(safe_max_crack_count),
				effect_strength
			)
		),
		1,
		maxi(safe_max_crack_count, 1)
	)
	var minimum_crack_length := mini(3, safe_max_crack_length)
	var crack_length_limit := clampi(
		roundi(
			lerpf(
				float(minimum_crack_length),
				float(safe_max_crack_length),
				effect_strength
			)
		),
		1,
		maxi(safe_max_crack_length, 1)
	)
	var crack_depth_limit := clampi(
		roundi(
			lerpf(
				0.0,
				float(safe_max_crack_depth),
				effect_strength
			)
		),
		0,
		safe_max_crack_depth
	)
	var authored_paths: Array = []
	var first_direction := (
		-1
		if _random.randi_range(0, 1) == 0
		else 1
	)
	for crack_index in range(crack_count):
		var crack_direction := (
			first_direction
			if crack_index % 2 == 0
			else -first_direction
		)
		var crack_cell := Vector2i(
			clampi(
				impact_center_cell.x
					+ crack_direction
						* (maxi(impact_half_width_cells, 0) + 1),
				0,
				config.terrain_width_cells - 1
			),
			impact_center_cell.y
		)
		var crack_path: Array[Vector2i] = []
		var crack_depth := 0
		var random_length_minimum := maxi(
			1,
			ceili(float(crack_length_limit) * 0.65)
		)
		var crack_length := _random.randi_range(
			random_length_minimum,
			crack_length_limit
		)
		for step_index in range(crack_length):
			if step_index > 0:
				crack_cell.x = clampi(
					crack_cell.x + crack_direction,
					0,
					config.terrain_width_cells - 1
				)
				var depth_roll := _random.randi_range(0, 99)
				if depth_roll < 34 and crack_depth < crack_depth_limit:
					crack_depth += 1
				elif depth_roll < 52 and crack_depth > 0:
					crack_depth -= 1
				crack_cell.y = impact_center_cell.y + crack_depth
			if not is_ground_cell(crack_cell):
				break
			crack_path.append(crack_cell)
		if not crack_path.is_empty():
			authored_paths.append(crack_path)

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


## Discards every recorded hit so a preview can rebuild from intact terrain.
func clear_damage() -> void:
	_destruction_masks.clear()


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
	tunnel_depth_rows: int,
	surface_contact_cell_x: int = -1
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
	var path_start_cell_x: int = (
		safe_start.x
		if surface_contact_cell_x < 0
		else clampi(
			surface_contact_cell_x,
			0,
			config.terrain_width_cells - 1
		)
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
			path_start_cell_x,
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


## Returns the world cell an encounter's authored room is measured from: the
## chamber's center column on its own solid floor row. Sculpt tooling and the
## renderer both anchor here, so a room cannot drift from the encounter it
## belongs to when the run length or terrain width changes.
func get_encounter_anchor_cell(
	encounter: DepthCharacterEncounter
) -> Vector2i:
	if encounter == null:
		return Vector2i.ZERO
	return Vector2i(
		floori(float(config.terrain_width_cells) * 0.5),
		config.initial_surface_row
			+ encounter.resolve_depth(config.total_run_depth)
	)


## Returns every authored room placed in world cells. Public so the renderer
## draws the same rock the miner stands on rather than deriving its own.
func get_sculpt_placements() -> Array[SculptPlacement]:
	if _sculpt_placements_are_built:
		return _sculpt_placements
	_sculpt_placements_are_built = true
	_sculpt_placements.clear()
	if encounter_config == null or config == null:
		return _sculpt_placements
	for encounter in encounter_config.encounters:
		if encounter == null or encounter.terrain_sculpt == null:
			continue
		var sculpt := encounter.terrain_sculpt
		# Resizing a room moves its footprint, so the cache has to die with any
		# edit. Listening here keeps that automatic instead of asking every
		# caller to remember.
		if not sculpt.changed.is_connected(invalidate_sculpt_placements):
			sculpt.changed.connect(invalidate_sculpt_placements)
		if not sculpt.enabled or not sculpt.get_sculpt_error().is_empty():
			continue
		var placement := SculptPlacement.new()
		placement.sculpt = sculpt
		placement.anchor_cell = get_encounter_anchor_cell(encounter)
		placement.world_rect = sculpt.get_world_rect(placement.anchor_cell)
		_sculpt_placements.append(placement)
	return _sculpt_placements


## Drops the cached room placements after a sculpt or the schedule changes.
func invalidate_sculpt_placements() -> void:
	_sculpt_placements_are_built = false


## Returns the authored room covering a terrain row, or null. The renderer asks
## once per row instead of once per mask pixel.
func get_sculpt_placement_for_row(world_row: int) -> SculptPlacement:
	for placement in get_sculpt_placements():
		if (
			world_row >= placement.world_rect.position.y
			and world_row < placement.world_rect.end.y
		):
			return placement
	return null


## Returns whether a cell can be destroyed by a new hit.
func _is_mineable_cell(cell: Vector2i) -> bool:
	return is_ground_cell(cell) and not _is_cell_destroyed(cell)


## Returns whether a cell is inside an encounter chamber.
func _is_encounter_chamber_cell(cell: Vector2i) -> bool:
	if encounter_config == null:
		return false

	# An authored room is the whole truth inside its own footprint. That is what
	# lets a designer both open rock the procedural taper left solid and leave a
	# pillar standing where the taper would have carved one away.
	for placement in get_sculpt_placements():
		if not placement.world_rect.has_point(cell):
			continue
		return not placement.sculpt.is_solid_local(
			placement.sculpt.world_to_local(cell, placement.anchor_cell)
		)

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
	var byte_offset := mask_offset >> 3
	var bit_mask := 1 << (mask_offset & 7)
	return mask[byte_offset] & bit_mask != 0


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
	var byte_offset := mask_offset >> 3
	var bit_mask := 1 << (mask_offset & 7)
	mask[byte_offset] = mask[byte_offset] | bit_mask
	_destruction_masks[chunk_index] = mask


## Gets or creates the saved damage mask for a chunk.
func _get_or_create_mask(chunk_index: int) -> PackedByteArray:
	if _destruction_masks.has(chunk_index):
		return _destruction_masks[chunk_index] as PackedByteArray
	var mask := PackedByteArray()
	var cell_count := (
		config.terrain_width_cells * config.chunk_height_cells
	)
	mask.resize(ceili(float(cell_count) / 8.0))
	_destruction_masks[chunk_index] = mask
	return mask


## Returns the chunk index containing a terrain row.
func _world_to_chunk_index(world_y: int) -> int:
	return floori(float(world_y) / float(config.chunk_height_cells))
