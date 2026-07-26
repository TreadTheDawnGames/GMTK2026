extends SceneTree

## How it works:
## - Rebuilds the Moody Teen cavern deterministically from cell coordinates.
## - A broad uneven arch opens continuously down to the guarded landing floor.
## - The arch falls into solid irregular side walls at both ends.
## - The shared baker derives four visible depth masks from that logical cut.
## - Verification rejects unsafe landings, hanging rock, flat roofs, or open ends.
## - The invariant is that all 49 possible fall columns reach the same floor.

const ROOM_PATH: String = (
	"res://resources/cinematics/sculpts/moody_teen_first_room.tres"
)
const MINING_CONFIG_PATH: String = "res://resources/mining/mining_config.tres"
const GRID_SIZE := Vector2i(384, 120)
const ANCHOR_OFFSET := Vector2i(-192, -110)
const ROOM_CENTRE_X: int = 192
## One full 1152px frame wide at eight pixels per cell. Both walls kiss the
## discovery frame instead of living off screen, while extreme landings reveal
## more of one end without making the room feel like a rectangular shaft.
const LEFT_CAVERN_X: int = 120
const RIGHT_CAVERN_X: int = 264
const MINIMUM_ROOF_VARIATION: int = 12

var _failures: Array[String] = []


func _initialize() -> void:
	var sculpt := load(ROOM_PATH) as CutsceneTerrainSculpt
	var mining_config := load(MINING_CONFIG_PATH) as MiningConfig
	if sculpt == null or mining_config == null:
		push_error("The Moody Teen carve could not load its room or config.")
		quit(1)
		return

	_cut_room(sculpt)
	_verify_room(sculpt, mining_config)
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("MOODY_TEEN_ROOM_CARVE_FAIL: %s" % failure)
		print("MOODY_TEEN_ROOM_CARVE: NOT SAVED")
		quit(1)
		return

	var save_error := ResourceSaver.save(sculpt, ROOM_PATH)
	if save_error != OK:
		push_error("Could not save Moody Teen room: %s" % error_string(save_error))
		quit(1)
		return
	print(
		"MOODY_TEEN_ROOM_CARVE: SAVED open_cells=%d"
		% sculpt.get_open_cell_count()
	)
	quit(0)


func _cut_room(sculpt: CutsceneTerrainSculpt) -> void:
	sculpt.enabled = true
	sculpt.grid_size = GRID_SIZE
	sculpt.anchor_offset_cells = ANCHOR_OFFSET
	sculpt.protected_floor_rows = 3
	sculpt.edge_smoothing = 1.0
	sculpt.background_layer_index = 3
	sculpt.clear_layer_masks()
	sculpt.fill_all(true)

	var floor_row := sculpt.get_floor_local_row()
	sculpt.begin_edit()
	for local_x in range(LEFT_CAVERN_X, RIGHT_CAVERN_X + 1):
		var roof_row := _get_roof_row(local_x, floor_row)
		for local_y in range(roof_row, floor_row):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)
	sculpt.end_edit()
	_shape_side_walls(sculpt, floor_row)
	CutsceneSculptBaker.apply_visual_depth_masks(sculpt)


## Returns a broad authored arch with several rock-scale frequencies.
func _get_roof_row(local_x: int, floor_row: int) -> int:
	var half_width := float(RIGHT_CAVERN_X - LEFT_CAVERN_X) * 0.5
	var normalized := absf(float(local_x - ROOM_CENTRE_X)) / half_width
	var dome := 29.0 * (1.0 - pow(clampf(normalized, 0.0, 1.0), 1.65))
	var long_wave := sin(float(local_x) * 0.117) * 3.2
	var rock_wave := sin(float(local_x) * 0.431 + 0.8) * 1.8
	var height := clampi(int(roundf(39.0 + dome + long_wave + rock_wave)), 34, 72)
	return floor_row - height


## Leans both side walls inward toward the roof and gives their faces a small
## rock wave. These cells remain connected to the solid outside the room; they
## are wall mass, not floating collision inside the fall path.
func _shape_side_walls(
	sculpt: CutsceneTerrainSculpt,
	floor_row: int
) -> void:
	sculpt.begin_edit()
	for local_y in range(floor_row - 58, floor_row):
		var lift_ratio := float(floor_row - local_y) / 58.0
		var lean := int(roundf(14.0 * pow(lift_ratio, 1.35)))
		var left_wave := int(roundf(sin(float(local_y) * 0.39) * 2.2))
		var right_wave := int(roundf(sin(float(local_y) * 0.31 + 1.7) * 2.2))
		var left_edge := LEFT_CAVERN_X + maxi(lean + left_wave, 0)
		var right_edge := RIGHT_CAVERN_X - maxi(lean + right_wave, 0)
		for local_x in range(LEFT_CAVERN_X, left_edge):
			sculpt.set_solid_local(Vector2i(local_x, local_y), true)
		for local_x in range(right_edge + 1, RIGHT_CAVERN_X + 1):
			sculpt.set_solid_local(Vector2i(local_x, local_y), true)
	sculpt.end_edit()


func _verify_room(
	sculpt: CutsceneTerrainSculpt,
	mining_config: MiningConfig
) -> void:
	var sculpt_error := sculpt.get_sculpt_error()
	if not sculpt_error.is_empty():
		_failures.append("The room is unusable: %s" % sculpt_error)
		return

	var floor_row := sculpt.get_floor_local_row()
	var half_span := mining_config.snake_half_span_cells
	var landing_rows := sculpt.get_landing_local_rows(half_span)
	var first_x := sculpt.get_landing_first_local_x(half_span)
	if landing_rows.size() != half_span * 2 + 1:
		_failures.append("The full 49-column landing band is not represented.")

	var tolerance := DepthEncounterController.LANDING_FLOOR_TOLERANCE_ROWS
	var worst_shortfall := 0
	for index in range(landing_rows.size()):
		var landing_row := landing_rows[index]
		var column := first_x + index
		if landing_row < 0:
			_failures.append("Column %d has no reachable ground." % column)
			continue
		var shortfall := floor_row - landing_row
		worst_shortfall = maxi(worst_shortfall, shortfall)
		if shortfall > tolerance:
			_failures.append(
				"Column %d lands %d rows high (limit %d)."
				% [column, shortfall, tolerance]
			)

	var highest_roof := floor_row
	var lowest_roof := 0
	for local_x in range(
		ROOM_CENTRE_X - half_span,
		ROOM_CENTRE_X + half_span + 1
	):
		var first_open := _get_first_open_row(sculpt, local_x, floor_row)
		highest_roof = mini(highest_roof, first_open)
		lowest_roof = maxi(lowest_roof, first_open)
		if first_open < 0:
			continue
		for local_y in range(first_open, floor_row):
			if sculpt.is_solid_local(Vector2i(local_x, local_y)):
				_failures.append(
					"Column %d has hanging rock at row %d."
					% [local_x, local_y]
				)
				break
	for local_x in range(LEFT_CAVERN_X, RIGHT_CAVERN_X + 1):
		var roof_row := _get_first_open_row(sculpt, local_x, floor_row)
		if roof_row < 0:
			continue
		highest_roof = mini(highest_roof, roof_row)
		lowest_roof = maxi(lowest_roof, roof_row)
	if lowest_roof - highest_roof < MINIMUM_ROOF_VARIATION:
		_failures.append("The cavern roof is too flat to read as authored rock.")

	for wall_x in [LEFT_CAVERN_X - 8, RIGHT_CAVERN_X + 8]:
		if _get_first_open_row(sculpt, wall_x, floor_row) >= 0:
			_failures.append("End wall at column %d is open." % wall_x)

	if sculpt.layer_solid_bits.size() != 4:
		_failures.append("The room does not carry all four visual strata.")
	var centre_open := Vector2i(ROOM_CENTRE_X, floor_row - 30)
	if sculpt.is_solid_local(centre_open):
		_failures.append("The cavern centre is not open logical space.")
	if not sculpt.is_layer_solid_local(3, centre_open):
		_failures.append("The deepest stratum does not close the backdrop.")

	print(
		"MOODY_TEEN_ROOM_CARVE: landing=%d worst=%d/%d roof_variation=%d"
		% [
			landing_rows.size(),
			worst_shortfall,
			tolerance,
			lowest_roof - highest_roof,
		]
	)


func _get_first_open_row(
	sculpt: CutsceneTerrainSculpt,
	local_x: int,
	floor_row: int
) -> int:
	for local_y in range(floor_row):
		if not sculpt.is_solid_local(Vector2i(local_x, local_y)):
			return local_y
	return -1
