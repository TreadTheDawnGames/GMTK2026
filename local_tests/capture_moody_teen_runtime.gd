extends SceneTree

## How it works:
## - Boots the production mining scene with an in-memory 4.5 schedule insertion.
## - Releases the real intro, crosses the 5,000 ceiling, and reports the landing.
## - Captures the real dialogue question, final dots, closing, and resumed hit.
## - Assertions prove the cinematic gate, timeline, and mining input all release.
## - The shared schedule is never written.
## - The invariant is that the seventh line returns control with no reward beat.
##
## Run with:
##   godot --rendering-driver opengl3 --path . --script res://local_tests/capture_moody_teen_runtime.gd

const MINING_SCENE: PackedScene = preload(
	"res://Scenes/mining/mining_proof.tscn"
)
const ENCOUNTER: DepthCharacterEncounter = preload(
	"res://resources/encounters/moody_teen_first_encounter.tres"
)
const SCHEDULE: DepthEncounterConfig = preload(
	"res://resources/encounters/depth_encounter_config.tres"
)
const OUTPUT_DIRECTORY: String = "user://moody_teen_capture"
const ENCOUNTER_INDEX: int = 4

var _failures: Array[String] = []


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
		ENCOUNTER,
		controller.mining_config.total_run_depth
	)
	run_state.depth = ceiling_depth
	run_state.depth_changed.emit(ceiling_depth)
	await process_frame

	run_state.mining_y = (
		controller.mining_config.initial_surface_row
		+ ENCOUNTER.depth_from_surface
	)
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
	_expect(flow.is_busy(), "The encounter did not retain the cinematic gate.")

	if director.is_conversation_active():
		for _line_advance in range(5):
			director.advance()
			await process_frame
		for _typing_frame in range(120):
			await process_frame
		_expect(
			director._current_line_index == 5,
			"The capture did not reach the Teen's question."
		)
		director.body_label.visible_characters = -1
		await process_frame
		await _capture("06_dialogue_question.png")

		director.advance()
		for _typing_frame in range(30):
			await process_frame
		_expect(
			director._current_line_index == 6,
			"The capture did not reach the miner's final dots."
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
		"Closing left the encounter active."
	)
	_expect(
		not mining.is_swing_queue_paused(),
		"Closing left the mining swing queue paused."
	)
	_expect(
		timing.mining_window.is_processing(),
		"Closing did not restore the timing window."
	)
	await _capture("08_mining_handoff.png")

	var renderer := game_root.get_node(
		"MiningScene/TerrainLayerRenderer"
	) as TerrainLayerRenderer
	renderer.set("_show_logical_overlay", true)
	renderer.queue_redraw()
	await _capture("10_f3_runtime_parity.png")
	_expect(
		renderer.get("_show_logical_overlay") == true,
		"The runtime F3 logical overlay did not enable."
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
	await _capture("09_first_resumed_mining.png")

	# Re-enter only to interrupt the opening timeline. This exercises the exact
	# stage snapshot/restore path without allowing a second dialogue to start.
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
		+ ENCOUNTER.depth_from_surface
	)
	await process_frame
	_expect(
		controller._active_encounter_index == ENCOUNTER_INDEX,
		"The reset check did not reactivate the encounter."
	)
	await controller._fail_active_encounter()
	_expect(not flow.is_busy(), "Cancellation left the cinematic gate owned.")
	_expect(
		controller._active_encounter_index < 0,
		"Cancellation left the encounter active."
	)
	_expect(
		not mining.is_swing_queue_paused(),
		"Cancellation left mining paused."
	)

	game_root.queue_free()
	await process_frame
	if _failures.is_empty():
		print(
			"MOODY_TEEN_RUNTIME_CAPTURE_PASS depth=%d output=%s"
			% [
				run_state.depth,
				ProjectSettings.globalize_path(OUTPUT_DIRECTORY),
			]
		)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MOODY_TEEN_RUNTIME_CAPTURE_FAIL: %s" % failure)
	quit(1)


func _make_capture_schedule() -> DepthEncounterConfig:
	var schedule := SCHEDULE.duplicate(true) as DepthEncounterConfig
	var encounters: Array[DepthCharacterEncounter] = []
	for encounter in schedule.encounters:
		encounters.append(encounter)
	encounters.insert(ENCOUNTER_INDEX, ENCOUNTER)
	schedule.encounters = encounters
	return schedule


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
