extends SceneTree

## How it works:
## - Rebuilds encounter 2 from the shared mined-tunnel cut.
## - Raises and fractures the cavern, then opens the canonical 37-cell shaft.
## - Builds the Keeper's connected ledge after clearing unsafe hanging rock.
## - Derives the shared four visual depth masks and verifies every critical span.
## - Saves only when the landing, ledge, shaft, roof, and bottom floor all pass.
## The invariant is that the shaft never reaches the miner's landing band.

const ROOM_PATH := (
	"res://resources/cinematics/sculpts/cloak_lantern_first_room.tres"
)
const MINING_CONFIG_PATH := "res://resources/mining/mining_config.tres"

const GRID_SIZE := Vector2i(384, 220)
const ANCHOR_OFFSET := Vector2i(-192, -110)
const CAVERN_FIRST_X: int = 72
const CAVERN_LAST_X: int = 362
const BASE_CAVERN_HEIGHT: int = 30
const LEFT_WALL_FOOT_X: int = 78
const LEFT_WALL_FACE_X: int = 52
const RIGHT_WALL_FOOT_X: int = 354
const RIGHT_WALL_FACE_X: int = 378

const SHAFT_LEFT_X: int = 108
const SHAFT_RIGHT_X: int = 144
const SHAFT_BOTTOM_ROW: int = 205
const SHAFT_AUDIT_ROW: int = 154
const STAFF_LOCAL_X: int = 128
const STAFF_PIT_HALF_WIDTH: int = 18
const STAFF_PIT_RISE_ROWS: int = 10
const LEDGE_TIP_X: int = 132
const LEDGE_ROOT_X: int = 145
const LEDGE_TOP_ROW: int = 102
const LEDGE_WALL_X: int = 160
const KEEPER_ENTRANCE_X: int = 133
const KEEPER_CONVERSATION_X: int = 140

var _failures: Array[String] = []


func _initialize() -> void:
	var sculpt := load(ROOM_PATH) as CutsceneTerrainSculpt
	var mining_config := load(MINING_CONFIG_PATH) as MiningConfig
	if sculpt == null or mining_config == null:
		push_error("Encounter 2 authoring could not load its room or config.")
		quit(1)
		return

	_cut_room(sculpt)
	_verify_room(sculpt, mining_config)
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("LANTERN_FIRST_ROOM_FAIL: %s" % failure)
		print(
			"LANTERN_FIRST_ROOM: NOT SAVED (%d problems)"
			% _failures.size()
		)
		quit(1)
		return

	var save_error := ResourceSaver.save(sculpt, ROOM_PATH)
	if save_error != OK:
		push_error(
			"Could not save encounter 2's room: %s"
			% error_string(save_error)
		)
		quit(1)
		return
	print("LANTERN_FIRST_ROOM: SAVED %s" % ROOM_PATH)
	print("  open cells=%d" % sculpt.get_open_cell_count())
	quit(0)


func _cut_room(sculpt: CutsceneTerrainSculpt) -> void:
	sculpt.enabled = true
	sculpt.grid_size = GRID_SIZE
	sculpt.anchor_offset_cells = ANCHOR_OFFSET
	# This room intentionally opens through its floor into the staff shaft.
	sculpt.protected_floor_rows = 0

	CutsceneSculptBaker.carve_level_tunnel(sculpt, 22)
	_carve_high_cavern(sculpt)
	CutsceneSculptBaker.carve_jagged_end_wall(
		sculpt,
		LEFT_WALL_FOOT_X,
		LEFT_WALL_FACE_X
	)
	CutsceneSculptBaker.carve_jagged_end_wall(
		sculpt,
		RIGHT_WALL_FOOT_X,
		RIGHT_WALL_FACE_X
	)
	_clear_hanging_rock(sculpt)
	_carve_deep_shaft(sculpt)
	_shape_staff_pit(sculpt)
	_build_keeper_ledge(sculpt)
	CutsceneSculptBaker.apply_visual_depth_masks(sculpt)


func _carve_high_cavern(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	sculpt.begin_edit()
	for local_x in range(CAVERN_FIRST_X, CAVERN_LAST_X + 1):
		var progress := float(local_x - CAVERN_FIRST_X)
		var height := BASE_CAVERN_HEIGHT + roundi(
			sin(progress * 0.075) * 3.5
			+ sin(progress * 0.19 + 1.2) * 1.75
			+ sin(progress * 0.037 + 0.4) * 2.0
		)
		# The discovery volume lifts most over the ledge and landing span.
		if local_x >= 118 and local_x <= 230:
			height += roundi(
				5.0
				* sin(
					PI
					* float(local_x - 118)
					/ float(230 - 118)
				)
			)
		var ceiling_row := maxi(floor_row - height, 0)
		for local_y in range(ceiling_row, floor_row):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)
	sculpt.end_edit()

	# Irregular strike-sized bites keep the higher silhouette in the same
	# universe as the miner's impact openings.
	var brush := CutsceneSculptBrush.new()
	brush.radius_cells = 5.0
	brush.strength = 0.38
	brush.falloff = 0.58
	for local_x in range(CAVERN_FIRST_X, CAVERN_LAST_X + 1, 4):
		brush.seed_value = local_x * 17
		brush.roughen(
			sculpt,
			Vector2(
				float(local_x),
				float(floor_row - _get_clear_height(local_x))
			)
		)


func _get_clear_height(local_x: int) -> int:
	var progress := float(local_x - CAVERN_FIRST_X)
	var height := BASE_CAVERN_HEIGHT + roundi(
		sin(progress * 0.075) * 3.5
		+ sin(progress * 0.19 + 1.2) * 1.75
		+ sin(progress * 0.037 + 0.4) * 2.0
	)
	if local_x >= 118 and local_x <= 230:
		height += roundi(
			5.0
				* sin(
					PI
					* float(local_x - 118)
					/ float(230 - 118)
				)
		)
	return height


func _clear_hanging_rock(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	sculpt.begin_edit()
	for local_x in range(sculpt.grid_size.x):
		var first_open_row := -1
		for local_y in range(floor_row):
			if not sculpt.is_solid_local(Vector2i(local_x, local_y)):
				first_open_row = local_y
				break
		if first_open_row < 0:
			continue
		var ground_row := floor_row
		while (
			ground_row - 1 > first_open_row
			and sculpt.is_solid_local(Vector2i(local_x, ground_row - 1))
		):
			ground_row -= 1
		for local_y in range(first_open_row, ground_row):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)
	sculpt.end_edit()


func _carve_deep_shaft(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	sculpt.begin_edit()
	for local_y in range(floor_row, SHAFT_BOTTOM_ROW):
		var drift := roundi(
			sin(float(local_y) * 0.31) * 1.5
			+ sin(float(local_y) * 0.83 + 0.7) * 0.75
		)
		var left_x := SHAFT_LEFT_X + drift
		var right_x := SHAFT_RIGHT_X + drift
		for local_x in range(left_x, right_x + 1):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)
	sculpt.end_edit()

	# Offset impact arcs widen alternating walls without turning them into
	# row-by-row staircases.
	var brush := CutsceneSculptBrush.new()
	brush.radius_cells = 4.5
	brush.falloff = 0.3
	for local_y in range(floor_row + 7, SHAFT_BOTTOM_ROW - 5, 9):
		var is_left := ((local_y - floor_row) / 9) % 2 == 0
		var wall_x := SHAFT_LEFT_X if is_left else SHAFT_RIGHT_X
		brush.carve(
			sculpt,
			Vector2(
				float(wall_x + (2 if is_left else -2)),
				float(local_y)
			)
		)


func _shape_staff_pit(sculpt: CutsceneTerrainSculpt) -> void:
	# The shaft's lower support is a bowl, not a horizontal wall. Its deepest
	# point remains the canonical 95 rows down; rock rises toward both sides.
	sculpt.begin_edit()
	for local_x in range(
		STAFF_LOCAL_X - STAFF_PIT_HALF_WIDTH,
		STAFF_LOCAL_X + STAFF_PIT_HALF_WIDTH + 1
	):
		var distance := absf(float(local_x - STAFF_LOCAL_X))
		var edge_progress := clampf(
			distance / float(STAFF_PIT_HALF_WIDTH),
			0.0,
			1.0
		)
		var rise := roundi(
			float(STAFF_PIT_RISE_ROWS)
				* sin(edge_progress * PI * 0.5)
		)
		var jag := (
			0
			if distance <= 2.0
			else roundi(
				sin(float(local_x) * 1.43) * 0.8
				+ sin(float(local_x) * 0.57 + 1.1) * 0.55
			)
		)
		var support_row := clampi(
			SHAFT_BOTTOM_ROW - rise + jag,
			SHAFT_BOTTOM_ROW - STAFF_PIT_RISE_ROWS - 1,
			SHAFT_BOTTOM_ROW
		)
		for local_y in range(support_row, sculpt.grid_size.y):
			sculpt.set_solid_local(Vector2i(local_x, local_y), true)
	sculpt.end_edit()

	# Two small impact bites stop the bowl rim reading as a perfect cutout.
	var brush := CutsceneSculptBrush.new()
	brush.radius_cells = 2.8
	brush.falloff = 0.25
	brush.carve(
		sculpt,
		Vector2(
			float(STAFF_LOCAL_X - STAFF_PIT_HALF_WIDTH + 2),
			float(SHAFT_BOTTOM_ROW - STAFF_PIT_RISE_ROWS)
		)
	)
	brush.carve(
		sculpt,
		Vector2(
			float(STAFF_LOCAL_X + STAFF_PIT_HALF_WIDTH - 2),
			float(SHAFT_BOTTOM_ROW - STAFF_PIT_RISE_ROWS + 1)
		)
	)


func _build_keeper_ledge(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	sculpt.begin_edit()
	for local_x in range(LEDGE_TIP_X, LEDGE_ROOT_X):
		var thickness := 2 + posmod(local_x * 7 + 3, 3)
		for local_y in range(
			LEDGE_TOP_ROW,
			mini(LEDGE_TOP_ROW + thickness, floor_row)
		):
			sculpt.set_solid_local(Vector2i(local_x, local_y), true)
	# Resolve the cliff a row at a time. A height chosen per column creates the
	# visible staircase this remake is replacing; a wandering vertical face
	# gives the mask renderer a continuous fractured contour instead.
	for local_y in range(LEDGE_TOP_ROW, floor_row):
		var face_x := LEDGE_WALL_X + roundi(
			sin(float(local_y) * 1.31) * 1.2
			+ sin(float(local_y) * 0.47 + 0.8) * 0.8
		)
		for local_x in range(LEDGE_ROOT_X, face_x + 1):
			sculpt.set_solid_local(Vector2i(local_x, local_y), true)
	sculpt.end_edit()

	var brush := CutsceneSculptBrush.new()
	brush.radius_cells = 2.4
	brush.falloff = 0.25
	brush.carve(sculpt, Vector2(132.0, 106.0))
	brush.carve(sculpt, Vector2(138.5, 107.0))
	brush.carve(sculpt, Vector2(142.0, 107.0))
	brush.radius_cells = 3.2
	brush.carve(sculpt, Vector2(161.5, 104.0))
	brush.carve(sculpt, Vector2(162.0, 108.0))


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
	var first_landing_x := sculpt.get_landing_first_local_x(half_span)
	var tolerance := DepthEncounterController.LANDING_FLOOR_TOLERANCE_ROWS
	var worst_shortfall := 0
	for index in range(landing_rows.size()):
		var landing_x := first_landing_x + index
		var landing_row := landing_rows[index]
		if landing_row < 0:
			_failures.append("Landing column %d has no support." % landing_x)
			continue
		var shortfall := floor_row - landing_row
		worst_shortfall = maxi(worst_shortfall, shortfall)
		if shortfall > tolerance:
			_failures.append(
				"Landing column %d stops %d rows high (limit %d)."
				% [landing_x, shortfall, tolerance]
			)

	var minimum_headroom := 10_000
	for local_x in [168, 192, 216]:
		minimum_headroom = mini(
			minimum_headroom,
			_get_contiguous_headroom(sculpt, local_x)
		)
	if minimum_headroom < 28:
		_failures.append(
			"Landing cavern headroom fell to %d rows." % minimum_headroom
		)

	for keeper_x in [KEEPER_ENTRANCE_X, KEEPER_CONVERSATION_X]:
		var support_row := _get_first_support_below_opening(sculpt, keeper_x)
		if support_row != LEDGE_TOP_ROW:
			_failures.append(
				"Keeper column %d supports at row %d instead of %d."
				% [keeper_x, support_row, LEDGE_TOP_ROW]
			)

	var shaft_width := _get_open_run_width(
		sculpt,
		SHAFT_AUDIT_ROW,
		(SHAFT_LEFT_X + SHAFT_RIGHT_X) / 2
	)
	if shaft_width < SHAFT_RIGHT_X - SHAFT_LEFT_X + 1:
		_failures.append(
			"The deep shaft narrows to %d cells; 37 are required."
			% shaft_width
		)
	var staff_x := STAFF_LOCAL_X
	if (
		sculpt.is_solid_local(Vector2i(staff_x, SHAFT_BOTTOM_ROW - 1))
		or not sculpt.is_solid_local(Vector2i(staff_x, SHAFT_BOTTOM_ROW))
	):
		_failures.append("The staff shaft does not end on row 205.")
	var left_pit_support := _get_first_support_below_opening(
		sculpt,
		STAFF_LOCAL_X - 12
	)
	var right_pit_support := _get_first_support_below_opening(
		sculpt,
		STAFF_LOCAL_X + 12
	)
	if (
		SHAFT_BOTTOM_ROW - left_pit_support < 6
		or SHAFT_BOTTOM_ROW - right_pit_support < 6
	):
		_failures.append(
			"The staff floor does not rise into a visible impact bowl."
		)
	if not sculpt.is_solid_local(Vector2i(LEDGE_ROOT_X, LEDGE_TOP_ROW + 6)):
		_failures.append("The Keeper ledge is detached from its cavern wall.")
	if sculpt.is_solid_local(Vector2i(KEEPER_CONVERSATION_X, 110)):
		_failures.append("Rock filled the void beneath the ledge overhang.")

	print(
		(
			"LANTERN_FIRST_ROOM: landing=%d worst=%d/%d, "
			+ "headroom=%d, shaft=%d wide x %d deep"
		)
		% [
			landing_rows.size(),
			worst_shortfall,
			tolerance,
			minimum_headroom,
			shaft_width,
			SHAFT_BOTTOM_ROW - floor_row,
		]
	)


func _get_first_support_below_opening(
	sculpt: CutsceneTerrainSculpt,
	local_x: int
) -> int:
	var reached_opening := false
	for local_y in range(sculpt.grid_size.y):
		if not sculpt.is_solid_local(Vector2i(local_x, local_y)):
			reached_opening = true
		elif reached_opening:
			return local_y
	return -1


func _get_contiguous_headroom(
	sculpt: CutsceneTerrainSculpt,
	local_x: int
) -> int:
	var support_row := _get_first_support_below_opening(sculpt, local_x)
	if support_row < 0:
		return 0
	var open_rows := 0
	for local_y in range(support_row - 1, -1, -1):
		if sculpt.is_solid_local(Vector2i(local_x, local_y)):
			break
		open_rows += 1
	return open_rows


func _get_open_run_width(
	sculpt: CutsceneTerrainSculpt,
	local_y: int,
	seed_x: int
) -> int:
	if sculpt.is_solid_local(Vector2i(seed_x, local_y)):
		return 0
	var left_x := seed_x
	var right_x := seed_x
	while left_x - 1 >= 0 and not sculpt.is_solid_local(
		Vector2i(left_x - 1, local_y)
	):
		left_x -= 1
	while right_x + 1 < sculpt.grid_size.x and not sculpt.is_solid_local(
		Vector2i(right_x + 1, local_y)
	):
		right_x += 1
	return right_x - left_x + 1
