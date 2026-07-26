extends SceneTree

## How it works:
## - Rebuilds Encounter 5's room from deterministic column profiles.
## - Opens one broad asymmetric cavern and keeps both ends closed.
## - Varies the roof, walls, and low floor rubble without floating rock.
## - Derives the shared foreground, wall-rim, and deep backdrop masks.
## - Refuses to save unless landing, headroom, shape, and depth checks pass.
## - The invariant is that visual layers never change the logical floor.

const ROOM_PATH: String = (
	"res://resources/cinematics/sculpts/cloak_lantern_warning_room.tres"
)
const MINING_CONFIG_PATH: String = "res://resources/mining/mining_config.tres"
const GRID_SIZE := Vector2i(384, 120)
const ANCHOR_OFFSET := Vector2i(-192, -110)
const LEFT_WALL_FOOT_X: int = 102
const RIGHT_WALL_FOOT_X: int = 282
const STANDING_FIRST_X: int = 148
const STANDING_LAST_X: int = 260
const MINIMUM_STANDING_HEADROOM: int = 29

var _failures: Array[String] = []


func _initialize() -> void:
	var sculpt := load(ROOM_PATH) as CutsceneTerrainSculpt
	var mining_config := load(MINING_CONFIG_PATH) as MiningConfig
	if sculpt == null or mining_config == null:
		push_error("Encounter 5 room authoring could not load its resources.")
		quit(1)
		return

	_author_room(sculpt)
	_verify_room(sculpt, mining_config)
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("ENCOUNTER_5_ROOM_FAIL: %s" % failure)
		print("ENCOUNTER_5_ROOM: NOT SAVED (%d problems)" % _failures.size())
		quit(1)
		return

	var save_error := ResourceSaver.save(sculpt, ROOM_PATH)
	if save_error != OK:
		push_error("Could not save Encounter 5's room: %s" % error_string(save_error))
		quit(1)
		return
	print("ENCOUNTER_5_ROOM: SAVED %s" % ROOM_PATH)
	print("  open cells=%d" % sculpt.get_open_cell_count())
	quit(0)


## Builds the logical chamber before deriving presentation-only depth.
func _author_room(sculpt: CutsceneTerrainSculpt) -> void:
	sculpt.enabled = true
	sculpt.grid_size = GRID_SIZE
	sculpt.anchor_offset_cells = ANCHOR_OFFSET
	sculpt.protected_floor_rows = 3
	sculpt.background_layer_index = 3
	sculpt.edge_smoothing = 1.0
	sculpt.begin_edit()
	sculpt.clear_layer_masks()
	sculpt.fill_all(true)
	var floor_row := sculpt.get_floor_local_row()
	for local_x in range(LEFT_WALL_FOOT_X, RIGHT_WALL_FOOT_X + 1):
		var headroom := _get_authored_headroom(local_x)
		var floor_bump := _get_floor_bump(local_x)
		var ceiling_row := maxi(floor_row - headroom, 0)
		var ground_row := floor_row - floor_bump
		for local_y in range(ceiling_row, ground_row):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)
	sculpt.end_edit()
	CutsceneSculptBaker.apply_visual_depth_masks(sculpt)


## Returns the asymmetric roof height at one column.
func _get_authored_headroom(local_x: int) -> int:
	var centre_x := 210.0
	var half_span := 110.0
	var normalized := absf(float(local_x) - centre_x) / half_span
	if normalized >= 1.0:
		return 3
	var wall_envelope := pow(1.0 - normalized, 0.38)
	var left_bowl := 7.0 * exp(-pow((float(local_x) - 154.0) / 34.0, 2.0))
	var discovery_lift := 12.0 * exp(
		-pow((float(local_x) - 203.0) / 27.0, 2.0)
	)
	var keeper_canopy := 8.0 * exp(
		-pow((float(local_x) - 265.0) / 38.0, 2.0)
	)
	var rock_jag := (
		sin(float(local_x) * 0.29) * 1.7
		+ sin(float(local_x) * 0.71 + 1.4) * 1.1
		+ sin(float(local_x) * 1.37 + 0.2) * 0.6
	)
	return clampi(
		roundi(9.0 + 27.0 * wall_envelope + left_bowl + discovery_lift
			+ keeper_canopy + rock_jag),
		3,
		53
	)


## Returns low deterministic rubble; it never exceeds the landing tolerance.
func _get_floor_bump(local_x: int) -> int:
	var shape := (
		sin(float(local_x) * 0.23)
		+ sin(float(local_x) * 0.61 + 0.8) * 0.55
	)
	return clampi(roundi(shape * 0.6 + 0.7), 0, 2)


## Proves the room's gameplay and presentation contracts before saving it.
func _verify_room(
	sculpt: CutsceneTerrainSculpt,
	mining_config: MiningConfig
) -> void:
	var sculpt_error := sculpt.get_sculpt_error()
	if not sculpt_error.is_empty():
		_failures.append("The sculpt is unusable: %s" % sculpt_error)
		return

	var floor_row := sculpt.get_floor_local_row()
	var landing_rows := sculpt.get_landing_local_rows(
		mining_config.snake_half_span_cells
	)
	var tolerance := DepthEncounterController.LANDING_FLOOR_TOLERANCE_ROWS
	var worst_shortfall := 0
	for landing_row: int in landing_rows:
		if landing_row < 0:
			_failures.append("A landing column has no opening or floor.")
			continue
		worst_shortfall = maxi(worst_shortfall, floor_row - landing_row)
	if worst_shortfall > tolerance:
		_failures.append(
			"Landing rubble reaches %d rows above the %d-row tolerance."
			% [worst_shortfall, tolerance]
		)

	var minimum_headroom := GRID_SIZE.y
	var lowest_roof_row := floor_row
	var highest_roof_row := 0
	for local_x in range(STANDING_FIRST_X, STANDING_LAST_X + 1):
		var headroom := _get_contiguous_headroom(sculpt, local_x)
		minimum_headroom = mini(minimum_headroom, headroom)
		var roof_row := floor_row - headroom
		lowest_roof_row = mini(lowest_roof_row, roof_row)
		highest_roof_row = maxi(highest_roof_row, roof_row)
	if minimum_headroom < MINIMUM_STANDING_HEADROOM:
		_failures.append(
			"The cast span has only %d rows of clear standing air."
			% minimum_headroom
		)
	if highest_roof_row - lowest_roof_row < 8:
		_failures.append("The visible roof is too even to read as authored rock.")

	for wall_column: int in [LEFT_WALL_FOOT_X - 12, RIGHT_WALL_FOOT_X + 12]:
		if _get_contiguous_headroom(sculpt, wall_column) > 0:
			_failures.append("End wall column %d is still open." % wall_column)

	if sculpt.layer_solid_bits.size() != 4:
		_failures.append("The cavern does not author all four visual strata.")
	else:
		var unique_masks: Array[PackedByteArray] = []
		for layer_bits: PackedByteArray in sculpt.layer_solid_bits:
			if not unique_masks.has(layer_bits):
				unique_masks.append(layer_bits)
		if unique_masks.size() < 3:
			_failures.append(
				"The cavern needs foreground, wall-rim, and backdrop silhouettes."
			)

	print(
		"ENCOUNTER_5_ROOM: landing=%d worst=%d/%d headroom=%d roof_variation=%d"
		% [
			landing_rows.size(),
			worst_shortfall,
			tolerance,
			minimum_headroom,
			highest_roof_row - lowest_roof_row,
		]
	)


## Measures unbroken air upward from the first grounded cell.
func _get_contiguous_headroom(
	sculpt: CutsceneTerrainSculpt,
	local_x: int
) -> int:
	var floor_row := sculpt.get_floor_local_row()
	var ground_row := floor_row
	while (
		ground_row - 1 >= 0
		and sculpt.is_solid_local(Vector2i(local_x, ground_row - 1))
	):
		ground_row -= 1
	var open_rows := 0
	for local_y in range(ground_row - 1, -1, -1):
		if sculpt.is_solid_local(Vector2i(local_x, local_y)):
			break
		open_rows += 1
	return open_rows
