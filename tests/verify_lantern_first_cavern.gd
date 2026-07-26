extends SceneTree

## How it works:
## - Loads encounter 2's committed resource, sculpt, and real stage.
## - Proves the higher cavern, safe landing band, ledge, and 95-row shaft.
## - Exercises the authored opening/closing camera animations and RESET.
## - Checks the staff, restored vanishing bench, and layered terrain contract.
## The invariant is that the shaft cannot replace any legal landing support.

const ENCOUNTER_PATH := (
	"res://resources/encounters/cloak_lantern_first_encounter.tres"
)
const STAGE_PATH := (
	"res://Scenes/cinematics/lantern_first_encounter_stage.tscn"
)
const FLOOR_ROW: int = 110
const STAFF_LOCAL_X: int = 128
const SHAFT_BOTTOM_ROW: int = 205
const LEDGE_TOP_ROW: int = 102

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var encounter := load(ENCOUNTER_PATH) as DepthCharacterEncounter
	var stage_scene := load(STAGE_PATH) as PackedScene
	_expect(encounter != null, "Encounter 2 resource must load.")
	_expect(stage_scene != null, "Encounter 2 stage must parse.")
	if encounter == null or stage_scene == null:
		_finish()
		return

	var sculpt := encounter.terrain_sculpt
	_expect(sculpt != null, "Encounter 2 must reference its authored sculpt.")
	_expect(
		encounter.chamber_height_rows_override == 40,
		"The prepared chamber ceiling must match the raised cavern."
	)
	_expect(
		not encounter.dresses_trodden_floor
		and not encounter.lights_floor_as_plane,
		"Encounter 2 must not consume Encounter 9's floor shaders."
	)
	if sculpt != null:
		_verify_sculpt(sculpt)

	var stage := stage_scene.instantiate() as CharacterEncounterStage
	root.add_child(stage)
	await process_frame
	_verify_stage(stage)
	stage.queue_free()
	await process_frame
	_finish()


func _verify_sculpt(sculpt: CutsceneTerrainSculpt) -> void:
	_expect(
		sculpt.grid_size == Vector2i(384, 220),
		"The room must retain the authored shaft grid."
	)
	_expect(
		sculpt.layer_solid_bits.size() == 4,
		"The shared 2.5D presentation requires four derived masks."
	)
	var mining_config := load(
		"res://resources/mining/mining_config.tres"
	) as MiningConfig
	var half_span := mining_config.snake_half_span_cells
	var landing_rows := sculpt.get_landing_local_rows(half_span)
	_expect(landing_rows.size() == 49, "All 49 landing columns must resolve.")
	for index in range(landing_rows.size()):
		var landing_row := landing_rows[index]
		_expect(
			landing_row >= FLOOR_ROW
				- DepthEncounterController.LANDING_FLOOR_TOLERANCE_ROWS
				and landing_row <= FLOOR_ROW,
			"Landing column %d is outside the controller tolerance."
			% index
		)

	for local_x in [168, 192, 216]:
		_expect(
			_get_headroom(sculpt, local_x) >= 28,
			"Cavern headroom at column %d must be at least 28 rows."
			% local_x
		)
	for keeper_x in [133, 140]:
		_expect(
			_get_first_support(sculpt, keeper_x) == LEDGE_TOP_ROW,
			"Keeper ledge support at column %d moved off row 102."
			% keeper_x
		)
	_expect(
		not sculpt.is_solid_local(
			Vector2i(STAFF_LOCAL_X, SHAFT_BOTTOM_ROW - 1)
		)
		and sculpt.is_solid_local(
			Vector2i(STAFF_LOCAL_X, SHAFT_BOTTOM_ROW)
		),
		"The staff shaft must remain open for 95 rows and close at its floor."
	)
	_expect(
		_get_first_support(sculpt, STAFF_LOCAL_X - 12)
			<= SHAFT_BOTTOM_ROW - 6
			and _get_first_support(sculpt, STAFF_LOCAL_X + 12)
				<= SHAFT_BOTTOM_ROW - 6,
		"The shaft floor must rise around the staff as an impact bowl."
	)
	_expect(
		not sculpt.is_solid_local(Vector2i(140, FLOOR_ROW)),
		"The canonical unsupported ledge must remain over open shaft."
	)


func _verify_stage(stage: CharacterEncounterStage) -> void:
	_expect(
		stage.validate_stage().is_empty(),
		"Encounter 2 stage exports and named nodes must validate."
	)
	_expect(
		stage.entrance_marker.position == Vector2(-648, -64)
			and stage.conversation_marker.position == Vector2(-592, -64),
		"The Keeper must approach 56px toward the miner on his ledge."
	)
	_expect(
		is_equal_approx(stage.opening_move_seconds, 1.8),
		"The Keeper's canonical slow approach must last 1.8 seconds."
	)
	var staff := stage.get_node_or_null(^"PropMarkers/LanternStaff") as Sprite2D
	_expect(staff != null, "The abandoned lantern staff must remain composed.")
	if staff != null:
		_expect(
			is_equal_approx(staff.position.x, -689.0),
			"The staff must keep Jared's 15px rightward adjustment."
		)
		_expect(
			staff.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"The small staff must use sharp nearest filtering."
		)
	var bench := stage.get_node_or_null(^"PropMarkers/Bench") as Sprite2D
	_expect(bench != null, "The Keeper's approved bench must remain composed.")
	if bench != null:
		_expect(
			bench.position == Vector2(-474, -64),
			"The bench must keep its measured clearance and layer-one footing."
		)
		_expect(
			is_equal_approx(bench.modulate.a, 1.0),
			"The bench must be visible through the meeting."
		)

	var player := stage.animation_player
	_expect(
		player.has_animation(&"opening")
			and player.has_animation(&"closing")
			and player.has_animation(&"RESET"),
		"Discovery, handoff, and cancellation camera clips must exist."
	)
	if (
		player.has_animation(&"opening")
		and player.has_animation(&"closing")
		and player.has_animation(&"RESET")
	):
		player.play(&"opening")
		player.advance(1.8)
		_expect(
			stage.camera_pan_offset_cells == Vector2(-12, 0),
			"Opening must discover the Keeper with a 12-cell left pan."
		)
		player.play(&"closing")
		player.advance(0.9)
		_expect(
			stage.camera_pan_offset_cells == Vector2.ZERO,
			"Closing must restore gameplay framing."
		)
		if bench != null:
			_expect(
				is_zero_approx(bench.modulate.a),
				"The bench must disappear with the Keeper during closing."
			)
		player.play(&"opening")
		player.advance(1.8)
		player.play(&"RESET")
		player.advance(0.0)
		_expect(
			stage.camera_pan_offset_cells == Vector2.ZERO,
			"RESET must clear an interrupted camera displacement."
		)
		if bench != null:
			_expect(
				is_equal_approx(bench.modulate.a, 1.0),
				"RESET must restore the bench after cancellation or replay."
			)


func _get_first_support(
	sculpt: CutsceneTerrainSculpt,
	local_x: int
) -> int:
	var reached_opening := false
	for local_y in range(sculpt.grid_size.y):
		if sculpt.is_solid_local(Vector2i(local_x, local_y)):
			if reached_opening:
				return local_y
		else:
			reached_opening = true
	return -1


func _get_headroom(
	sculpt: CutsceneTerrainSculpt,
	local_x: int
) -> int:
	var support_row := _get_first_support(sculpt, local_x)
	if support_row < 0:
		return 0
	var open_rows := 0
	for local_y in range(support_row - 1, -1, -1):
		if sculpt.is_solid_local(Vector2i(local_x, local_y)):
			break
		open_rows += 1
	return open_rows


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("LANTERN_FIRST_CAVERN_VERIFY_PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("LANTERN_FIRST_CAVERN_VERIFY_FAIL: %s" % failure)
	quit(1)
