extends SceneTree

## How it works:
## - Boots the production mining scene with in-memory 4.5 and 7.5 insertions.
## - Crosses the real 10,500 ceiling and lets the production landing run.
## - Captures dialogue, camera reset, tool-driven parity, and resumed mining.
## - Re-entry cancellation proves every transient owner restores cleanly.
## - The invariant is <=1px local support error through the whole lifecycle.

const MINING_SCENE: PackedScene = preload(
	"res://Scenes/mining/mining_proof.tscn"
)
const FIRST_ENCOUNTER: DepthCharacterEncounter = preload(
	"res://resources/encounters/moody_teen_first_encounter.tres"
)
const SECOND_ENCOUNTER: DepthCharacterEncounter = preload(
	"res://resources/encounters/moody_teen_second_encounter.tres"
)
const SCHEDULE: DepthEncounterConfig = preload(
	"res://resources/encounters/depth_encounter_config.tres"
)
const OUTPUT_DIRECTORY: String = "user://moody_teen_second_capture"
const ENCOUNTER_INDEX: int = 8
const EXPECTED_DIALOGUE_ZOOM := Vector2(1.25, 1.25)

var _failures: Array[String] = []
var _prestage_support_delta: float = INF
var _prestage_support_error: float = INF
var _dialogue_sole_delta: float = INF
var _dialogue_miner_delta: float = INF
var _dialogue_overlap_delta: float = INF
var _closing_sole_delta: float = INF
var _resumed_sole_delta: float = INF


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1152, 648))
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	)
	var game_root := MINING_SCENE.instantiate()
	var schedule := _make_capture_schedule()
	var terrain := game_root.get_node(
		"MiningScene/TerrainManager"
	) as TerrainManager
	var controller := game_root.get_node(
		"MiningScene/Systems/UpgradeEncounterController"
	) as DepthEncounterController
	terrain.encounter_config = schedule
	controller.encounter_config = schedule
	root.add_child(game_root)
	await process_frame
	await process_frame

	var flow := game_root.get_node(
		"MiningScene/Systems/CinematicFlow"
	) as MiningCinematicFlow
	var director := game_root.get_node(
		"DialogueDirector"
	) as DialogueDirector
	var view := game_root.get_node(
		"MiningScene/Systems/ViewController"
	) as ViewController
	var camera := game_root.get_node("MiningScene/ImpactCamera") as Camera2D
	var miner_rig := game_root.get_node("MiningScene/MinerRig") as MinerRig
	var mining := game_root.get_node(
		"MiningScene/Systems/MiningController"
	) as MiningController
	var timing := game_root.get_node(
		"MiningScene/HUD/TimingWindow"
	) as TimingWindowTask
	var run_state := root.get_node("GameState") as RunState

	await _skip_intro(game_root, director, flow)
	controller._next_encounter_index = ENCOUNTER_INDEX
	var ceiling_depth := schedule.get_encounter_ceiling_depth(
		SECOND_ENCOUNTER,
		controller.mining_config.total_run_depth
	)
	var encounter_floor_y := (
		controller.mining_config.initial_surface_row
		+ SECOND_ENCOUNTER.depth_from_surface
	)
	run_state.mining_y = (
		controller.mining_config.initial_surface_row + ceiling_depth
	)
	view.follow_mining_position(
		Vector2i(run_state.mining_x, run_state.mining_y)
	)
	view.snap_follow_to_target()
	for _ceiling_stream_frame in range(30):
		await process_frame
	run_state.depth = ceiling_depth
	run_state.depth_changed.emit(ceiling_depth)
	var ayden_presenter := (
		controller._presenters_by_actor_id.get(&"moody_teen")
		as CharacterPresenter
	)
	_expect(ayden_presenter != null, "Ayden presenter was not resolved.")
	if ayden_presenter != null:
		var chamber_height := SECOND_ENCOUNTER.resolve_chamber_height_rows(
			schedule.chamber_height_rows
		)
		var descent_step_rows := maxi(
			floori(float(chamber_height) / 8.0),
			1
		)
		for descent_depth in range(
			ceiling_depth,
			SECOND_ENCOUNTER.depth_from_surface + 1,
			descent_step_rows
		):
			run_state.mining_y = (
				controller.mining_config.initial_surface_row
				+ descent_depth
			)
			view.follow_mining_position(
				Vector2i(run_state.mining_x, run_state.mining_y)
			)
			view.snap_follow_to_target()
			for _descent_settle_frame in range(3):
				await process_frame
			_prestage_support_error = _measure_cast_ground_error(
				controller,
				ayden_presenter,
				encounter_floor_y
			)
			_prestage_support_delta = absf(_prestage_support_error)
			if not is_nan(_prestage_support_delta):
				break
		_expect(
			_prestage_support_delta <= 1.0,
			"Ayden's prestaged sole misses local support by %.2fpx."
			% _prestage_support_delta
		)

	run_state.mining_y = encounter_floor_y
	view.follow_mining_position(
		Vector2i(run_state.mining_x, run_state.mining_y)
	)
	view.snap_follow_to_target()
	for _settle_frame in range(30):
		await process_frame
	controller._on_landing_reached(run_state.mining_y)
	await _wait_until(
		func() -> bool:
			return director.is_conversation_active(),
		12.0
	)
	_expect(director.is_conversation_active(), "Dialogue never became active.")
	_expect(flow.is_busy(), "Encounter 7.5 did not retain the cinematic gate.")
	if ayden_presenter != null:
		await _wait_until(
			func() -> bool:
				return camera.zoom.is_equal_approx(
					EXPECTED_DIALOGUE_ZOOM
				),
			3.0
		)
		# The first line is the Miner's dots, so let his intentional speech
		# reaction report completion before measuring the authored rest line.
		await _wait_until(
			func() -> bool:
				return not bool(
					miner_rig.speech_reaction.get("_is_reacting")
				),
			1.0
		)
		var cast_floor_offset := controller._resolve_cast_floor_offset(
			SECOND_ENCOUNTER
		)
		_dialogue_sole_delta = absf(
			_measure_cast_ground_error(
				controller,
				ayden_presenter,
				encounter_floor_y
			)
		)
		var miner_foot := miner_rig.get_cinematic_foot_screen_position()
		var miner_support := controller._sample_cutscene_floor(
			miner_foot.x,
			encounter_floor_y,
			cast_floor_offset
		)
		_dialogue_miner_delta = absf(miner_foot.y - miner_support)
		var actor_raw_support := controller._sample_cutscene_floor(
			ayden_presenter.global_position.x,
			encounter_floor_y,
			0.0
		)
		var miner_raw_support := controller._sample_cutscene_floor(
			miner_foot.x,
			encounter_floor_y,
			0.0
		)
		_dialogue_overlap_delta = absf(
			(
				ayden_presenter.global_position.y
				- actor_raw_support
			)
			- (miner_foot.y - miner_raw_support)
		)
		_expect(
			_dialogue_sole_delta <= 1.0,
			"Ayden's dialogue sole misses local support by %.2fpx."
			% _dialogue_sole_delta
		)
		_expect(
			_dialogue_miner_delta <= 1.0,
			"The miner's dialogue sole misses local support by %.2fpx."
			% _dialogue_miner_delta
		)
		_expect(
			_dialogue_overlap_delta <= 1.0,
			"Ayden and the miner use different ground overlaps by %.2fpx."
			% _dialogue_overlap_delta
		)

	if director.is_conversation_active():
		for _line_advance in range(5):
			director.advance()
			await process_frame
		for _typing_frame in range(120):
			await process_frame
		_expect(
			director._current_line_index == 5,
			"Runtime capture did not reach Ayden's repeated question."
		)
		_expect(
			camera.zoom.is_equal_approx(EXPECTED_DIALOGUE_ZOOM),
			"Typed dialogue camera did not reach 1.25 zoom."
		)
		director.body_label.visible_characters = -1
		await process_frame
		await _capture("06_dialogue_question.png")

		director.advance()
		for _typing_frame in range(30):
			await process_frame
		_expect(
			director._current_line_index == 6,
			"Runtime capture did not reach the miner's final dots."
		)
		director.body_label.visible_characters = -1
		await process_frame
		await _capture("07_final_dots.png")
		director.advance()

	await _wait_until(
		func() -> bool:
			return not flow.is_busy(),
		15.0
	)
	for _handoff_frame in range(45):
		await process_frame
	_expect(not flow.is_busy(), "Closing did not release the cinematic gate.")
	_expect(
		controller._active_encounter_index < 0,
		"Closing left Encounter 7.5 active."
	)
	_expect(
		not mining.is_swing_queue_paused(),
		"Closing left the mining swing queue paused."
	)
	_expect(
		timing.mining_window.is_processing(),
		"Closing did not restore the timing window."
	)
	_expect(
		camera.zoom.is_equal_approx(Vector2.ONE),
		"Closing did not restore neutral camera zoom."
	)
	if ayden_presenter != null:
		_closing_sole_delta = absf(
			_measure_cast_ground_error(
				controller,
				ayden_presenter,
				encounter_floor_y
			)
		)
		_expect(
			_closing_sole_delta <= 1.0,
			"Ayden's closing sole misses local support by %.2fpx."
			% _closing_sole_delta
		)
		_expect(ayden_presenter.visible, "Ayden did not persist after closing.")
	await _capture("08_mining_handoff.png")

	var renderer := game_root.get_node(
		"MiningScene/TerrainLayerRenderer"
	) as TerrainLayerRenderer
	renderer.set("_show_logical_overlay", true)
	renderer.queue_redraw()
	await _capture("10_runtime_parity.png")
	_expect(
		renderer.get("_show_logical_overlay") == true,
		"Runtime logical overlay did not enable."
	)
	renderer.set("_show_logical_overlay", false)
	renderer.queue_redraw()

	var depth_before_hit := run_state.depth
	if timing.mining_window.targets.is_empty():
		_failures.append("No timing target remained for the resumed hit.")
	else:
		var target := timing.mining_window.targets[0]
		timing.mining_window.slider_position = target.target_position
		Input.action_press(&"primary_action")
		await process_frame
		Input.action_release(&"primary_action")
		await _wait_until(
			func() -> bool:
				return not mining._is_swing_pending,
			4.0
		)
	_expect(run_state.depth > depth_before_hit, "The resumed hit mined no depth.")
	_expect(not mining._is_swing_pending, "The resumed hit never released.")
	if ayden_presenter != null:
		_expect(ayden_presenter.visible, "The resumed hit hid persistent Ayden.")
		for _resumed_settle_frame in range(30):
			await process_frame
		_resumed_sole_delta = absf(
			_measure_cast_ground_error(
				controller,
				ayden_presenter,
				encounter_floor_y
			)
		)
		_expect(
			_resumed_sole_delta <= 1.0,
			"Ayden's resumed-mining sole misses local support by %.2fpx."
			% _resumed_sole_delta
		)
	await _capture("09_first_resumed_mining.png")

	controller._latest_landing_world_y = (
		controller.mining_config.initial_surface_row
	)
	controller._next_encounter_index = ENCOUNTER_INDEX
	run_state.depth = ceiling_depth - 1
	run_state.depth_changed.emit(run_state.depth)
	run_state.depth = ceiling_depth
	run_state.depth_changed.emit(run_state.depth)
	controller._on_landing_reached(
		controller.mining_config.initial_surface_row
		+ SECOND_ENCOUNTER.depth_from_surface
	)
	await process_frame
	_expect(
		controller._active_encounter_index == ENCOUNTER_INDEX,
		"Reset check did not reactivate Encounter 7.5."
	)
	await controller._fail_active_encounter()
	_expect(not flow.is_busy(), "Cancellation left the cinematic gate owned.")
	_expect(
		controller._active_encounter_index < 0,
		"Cancellation left Encounter 7.5 active."
	)
	_expect(
		not mining.is_swing_queue_paused(),
		"Cancellation left mining paused."
	)
	if ayden_presenter != null:
		_expect(
			not ayden_presenter.visible,
			"Cancellation did not restore Ayden's pre-encounter hidden state."
		)

	game_root.queue_free()
	await process_frame
	print(
		(
			"MOODY_TEEN_SECOND_GROUNDING "
			+ "prestage_error=%+.2fpx prestage_delta=%.2fpx "
			+ "dialogue_delta=%.2fpx "
			+ "miner_delta=%.2fpx overlap_delta=%.2fpx "
			+ "closing_delta=%.2fpx resumed_delta=%.2fpx"
		)
		% [
			_prestage_support_error,
			_prestage_support_delta,
			_dialogue_sole_delta,
			_dialogue_miner_delta,
			_dialogue_overlap_delta,
			_closing_sole_delta,
			_resumed_sole_delta,
		]
	)
	if _failures.is_empty():
		print(
			(
				"MOODY_TEEN_SECOND_RUNTIME_CAPTURE_PASS "
				+ "prestage_delta=%.2fpx dialogue_delta=%.2fpx "
				+ "miner_delta=%.2fpx overlap_delta=%.2fpx "
				+ "closing_delta=%.2fpx resumed_delta=%.2fpx "
				+ "depth=%d output=%s"
			)
			% [
				_prestage_support_delta,
				_dialogue_sole_delta,
				_dialogue_miner_delta,
				_dialogue_overlap_delta,
				_closing_sole_delta,
				_resumed_sole_delta,
				run_state.depth,
				ProjectSettings.globalize_path(OUTPUT_DIRECTORY),
			]
		)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MOODY_TEEN_SECOND_RUNTIME_CAPTURE_FAIL: %s" % failure)
	quit(1)


func _measure_cast_ground_error(
	controller: DepthEncounterController,
	presenter: CharacterPresenter,
	encounter_floor_y: int
) -> float:
	var expected_support := controller._sample_cutscene_floor(
		presenter.global_position.x,
		encounter_floor_y,
		controller._resolve_cast_floor_offset(SECOND_ENCOUNTER)
	)
	return presenter.global_position.y - expected_support


func _make_capture_schedule() -> DepthEncounterConfig:
	var schedule := SCHEDULE.duplicate(true) as DepthEncounterConfig
	var encounters: Array[DepthCharacterEncounter] = []
	for encounter in schedule.encounters:
		encounters.append(encounter)
	if not _has_encounter(encounters, FIRST_ENCOUNTER.encounter_id):
		encounters.insert(4, FIRST_ENCOUNTER)
	if not _has_encounter(encounters, SECOND_ENCOUNTER.encounter_id):
		var quibble_index := -1
		for index in range(encounters.size()):
			if encounters[index].encounter_id == &"coffee_cat_first":
				quibble_index = index
				break
		encounters.insert(quibble_index + 1, SECOND_ENCOUNTER)
	schedule.encounters = encounters
	return schedule


func _has_encounter(
	encounters: Array[DepthCharacterEncounter],
	encounter_id: StringName
) -> bool:
	for encounter in encounters:
		if encounter.encounter_id == encounter_id:
			return true
	return false


func _skip_intro(
	game_root: Node,
	director: DialogueDirector,
	flow: MiningCinematicFlow
) -> void:
	var menu := game_root.get_node_or_null(
		"MainMenuLayer/MainMenu"
	) as GameMainMenu
	var arrival := game_root.get_node_or_null(
		"MiningScene/ArrivalIntro"
	) as ArrivalIntroSequence
	if menu != null:
		menu._on_start_button_pressed()
		await process_frame
	if arrival != null:
		arrival.attendant_pickup_enabled = false
		arrival.bus_arrival_seconds = 0.2
		arrival.bus_settle_seconds = 0.0
		arrival.miner_exit_delay_seconds = 0.05
		arrival.hold_before_dialogue_seconds = 0.0
		arrival.bus_departure_seconds = 0.2
	if director.cinematic_frame != null:
		director.cinematic_frame.blackout_reveal_seconds = 0.05
	await _wait_until(
		func() -> bool:
			return director.is_conversation_active(),
		15.0
	)
	if director.is_conversation_active():
		director.finish_conversation()
	await _wait_until(func() -> bool: return not flow.is_busy(), 8.0)
	if flow.is_busy():
		flow.finish(flow.get_flow_owner())
		await process_frame


func _wait_until(condition: Callable, timeout_seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return
		await process_frame


func _capture(file_name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_viewport().get_texture().get_image()
	if image == null:
		_failures.append("Nothing rendered for %s." % file_name)
		return
	var output_path := "%s/%s" % [OUTPUT_DIRECTORY, file_name]
	if image.save_png(output_path) != OK:
		_failures.append("Could not write %s." % output_path)


func _expect(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
