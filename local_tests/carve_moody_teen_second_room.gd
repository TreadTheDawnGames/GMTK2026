extends SceneTree

## How it works:
## - Rebuilds Encounter 7.5 as a deterministic keyhole/bell cavern.
## - A 49-column entry throat protects every possible snaking fall column.
## - Below it, asymmetric shoulders flare into a wider basin with sloped ends.
## - The shared baker derives all four visible strata from the logical room.
## - Verification rejects unsafe landings, a weak flare, or open outer walls.
## - The invariant is that every possible arrival reaches the protected floor.

const ROOM_PATH: String = (
	"res://resources/cinematics/sculpts/moody_teen_second_room.tres"
)
const MINING_CONFIG_PATH: String = "res://resources/mining/mining_config.tres"
const GRID_SIZE := Vector2i(384, 120)
const ANCHOR_OFFSET := Vector2i(-192, -110)
const ROOM_CENTRE_X: int = 192
const THROAT_HALF_WIDTH: int = 24
const SHOULDER_START_ROW: int = 34
const LEFT_BELL_LIMIT: int = 102
const RIGHT_BELL_LIMIT: int = 276
const MINIMUM_BELL_FLARE: int = 80

var _failures: Array[String] = []


func _initialize() -> void:
	var sculpt := load(ROOM_PATH) as CutsceneTerrainSculpt
	var mining_config := load(MINING_CONFIG_PATH) as MiningConfig
	if sculpt == null or mining_config == null:
		push_error("The second Ayden carve could not load its room or config.")
		quit(1)
		return

	_cut_room(sculpt)
	_verify_room(sculpt, mining_config)
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("MOODY_TEEN_SECOND_ROOM_CARVE_FAIL: %s" % failure)
		print("MOODY_TEEN_SECOND_ROOM_CARVE: NOT SAVED")
		quit(1)
		return

	var save_error := ResourceSaver.save(sculpt, ROOM_PATH)
	if save_error != OK:
		push_error(
			"Could not save second Ayden room: %s" % error_string(save_error)
		)
		quit(1)
		return
	print(
		"MOODY_TEEN_SECOND_ROOM_CARVE: SAVED open_cells=%d"
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
	for local_y in range(floor_row):
		var open_span := _get_open_span(local_y, floor_row)
		for local_x in range(open_span.x, open_span.y + 1):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)
	sculpt.end_edit()
	_shape_basin_floor(sculpt, floor_row)
	CutsceneSculptBaker.apply_visual_depth_masks(sculpt)


## The upper throat cannot narrow inside the landing band. Below row 34 the
## left shoulder opens first, while the right wall stays pinched before flaring
## into a deeper alcove. Small waves roughen the wall without blocking the fall.
func _get_open_span(local_y: int, floor_row: int) -> Vector2i:
	var throat_left := ROOM_CENTRE_X - THROAT_HALF_WIDTH
	var throat_right := ROOM_CENTRE_X + THROAT_HALF_WIDTH
	if local_y <= SHOULDER_START_ROW:
		var throat_chip := maxi(
			int(roundf(sin(float(local_y) * 0.47) * 1.5)),
			0
		)
		return Vector2i(throat_left - throat_chip, throat_right + throat_chip)

	var chamber_span := float(floor_row - 1 - SHOULDER_START_ROW)
	var left_progress := clampf(
		float(local_y - SHOULDER_START_ROW) / chamber_span,
		0.0,
		1.0
	)
	var right_progress := clampf(
		float(local_y - (SHOULDER_START_ROW + 13))
		/ float(floor_row - 1 - (SHOULDER_START_ROW + 13)),
		0.0,
		1.0
	)
	var left_ease := 1.0 - pow(1.0 - left_progress, 2.2)
	var right_ease := pow(right_progress, 0.82)
	var left_wave := sin(float(local_y) * 0.31 + 0.4) * 2.5
	var right_wave := sin(float(local_y) * 0.23 + 1.7) * 3.0
	var left_edge := int(roundf(
		lerpf(float(throat_left), float(LEFT_BELL_LIMIT), left_ease)
		+ left_wave
	))
	var right_edge := int(roundf(
		lerpf(float(throat_right), float(RIGHT_BELL_LIMIT), right_ease)
		+ right_wave
	))
	return Vector2i(
		mini(left_edge, throat_left),
		maxi(right_edge, throat_right)
	)


## Outside the protected arrival band, the bell rises into irregular stone
## benches. The centre stays perfectly level for the miner and tracked Ayden.
func _shape_basin_floor(
	sculpt: CutsceneTerrainSculpt,
	floor_row: int
) -> void:
	var safe_left := ROOM_CENTRE_X - THROAT_HALF_WIDTH
	var safe_right := ROOM_CENTRE_X + THROAT_HALF_WIDTH
	sculpt.begin_edit()
	for local_x in range(LEFT_BELL_LIMIT, safe_left):
		var distance := float(safe_left - local_x)
		var rise := clampi(
			int(roundf(distance * 0.075 + sin(float(local_x) * 0.41))),
			0,
			6
		)
		for local_y in range(floor_row - rise, floor_row):
			sculpt.set_solid_local(Vector2i(local_x, local_y), true)
	for local_x in range(safe_right + 1, RIGHT_BELL_LIMIT + 1):
		var distance := float(local_x - safe_right)
		var rise := clampi(
			int(roundf(distance * 0.06 + sin(float(local_x) * 0.37 + 1.2))),
			0,
			5
		)
		for local_y in range(floor_row - rise, floor_row):
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
		for local_y in range(floor_row):
			if sculpt.is_solid_local(Vector2i(column, local_y)):
				_failures.append(
					"Entry throat column %d is blocked at row %d."
					% [column, local_y]
				)
				break

	var upper_span := _get_open_span(SHOULDER_START_ROW, floor_row)
	var lower_span := _get_open_span(floor_row - 8, floor_row)
	var upper_width := upper_span.y - upper_span.x + 1
	var lower_width := lower_span.y - lower_span.x + 1
	if lower_width - upper_width < MINIMUM_BELL_FLARE:
		_failures.append("The lower chamber does not flare enough to read as a bell.")
	if (
		ROOM_CENTRE_X - lower_span.x
		== lower_span.y - ROOM_CENTRE_X
	):
		_failures.append("The bell is too symmetrical for the requested format.")

	for wall_x in [LEFT_BELL_LIMIT - 8, RIGHT_BELL_LIMIT + 8]:
		for local_y in range(SHOULDER_START_ROW, floor_row):
			if not sculpt.is_solid_local(Vector2i(wall_x, local_y)):
				_failures.append("Outer wall at column %d is open." % wall_x)
				break

	if sculpt.layer_solid_bits.size() != 4:
		_failures.append("The room does not carry all four visual strata.")
	var lower_centre := Vector2i(ROOM_CENTRE_X, floor_row - 18)
	if sculpt.is_solid_local(lower_centre):
		_failures.append("The lower bell centre is not open logical space.")
	if not sculpt.is_layer_solid_local(3, lower_centre):
		_failures.append("The deepest stratum does not close the backdrop.")

	print(
		(
			"MOODY_TEEN_SECOND_ROOM_CARVE: landing=%d worst=%d/%d "
			+ "throat_width=%d lower_width=%d"
		)
		% [
			landing_rows.size(),
			worst_shortfall,
			tolerance,
			upper_width,
			lower_width,
		]
	)
