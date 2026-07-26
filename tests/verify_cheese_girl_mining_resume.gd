extends SceneTree

## How it works:
## - Boots the production mining scene and releases only the opening flow.
## - A real resolved strike crosses Cheese Girl's ceiling and is interrupted.
## - The production encounter runs until its dialogue is active, then closes.
## - Three real timing inputs must each animate, mine, and release their swing.
## - The invariant is that a completed encounter cannot retain a dead strike.

const MINING_SCENE: PackedScene = preload(
	"res://Scenes/mining/mining_proof.tscn"
)

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var game_root := MINING_SCENE.instantiate()
	root.add_child(game_root)
	await process_frame
	await process_frame

	var encounter := game_root.get_node(
		"MiningScene/Systems/UpgradeEncounterController"
	) as DepthEncounterController
	var flow := game_root.get_node(
		"MiningScene/Systems/CinematicFlow"
	) as MiningCinematicFlow
	var director := game_root.get_node(
		"DialogueDirector"
	) as DialogueDirector
	var mining := game_root.get_node(
		"MiningScene/Systems/MiningController"
	) as MiningController
	var view := game_root.get_node(
		"MiningScene/Systems/ViewController"
	) as ViewController
	var timing := game_root.get_node(
		"MiningScene/HUD/TimingWindow"
	) as TimingWindowTask
	var run_state := root.get_node("GameState") as RunState
	var first_encounter := encounter.encounter_config.encounters[0]
	var ceiling_depth := encounter.encounter_config.get_encounter_ceiling_depth(
		first_encounter,
		encounter.mining_config.total_run_depth
	)
	var floor_depth := first_encounter.resolve_depth(
		encounter.mining_config.total_run_depth
	)
	if flow.is_busy():
		flow.finish(flow.get_flow_owner())
		await process_frame

	# Match the live ordering: impact advances RunState, depth_changed claims the
	# cinematic, and that claim stops the animation before it can report finished.
	run_state.depth = ceiling_depth - 1
	run_state.mining_y = (
		encounter.mining_config.initial_surface_row + run_state.depth
	)
	mining.resolve_attempt(true, 1, 0)
	mining.resolve_impact(Vector2.ZERO)
	view.snap_follow_to_target()
	encounter._on_landing_reached(run_state.mining_y)
	_expect(
		run_state.depth
			>= floor_depth
				- DepthEncounterController.LANDING_FLOOR_TOLERANCE_ROWS
		and run_state.depth <= floor_depth,
		"The opening strike landed at depth %d instead of Cheese Girl's floor."
		% run_state.depth
	)

	for _frame in range(600):
		await process_frame
		if director.is_conversation_active():
			break
	_expect(
		director.is_conversation_active(),
		"Cheese Girl's interrupted strike must activate her conversation."
	)
	if director.is_conversation_active():
		director.finish_conversation()
	for _frame in range(900):
		await process_frame
		if not flow.is_busy():
			break
	_expect(
		not flow.is_busy()
		and not paused
		and encounter._active_encounter_index < 0
		and not mining.is_swing_queue_paused()
		and timing.mining_window.is_processing()
		and timing.mining_window.targets.size() > 0,
		"Completing Cheese Girl's cutscene must restore live mining input."
	)

	var resumed_depth := run_state.depth
	for hit_index in range(3):
		var depth_before := run_state.depth
		if timing.mining_window.targets.is_empty():
			_expect(false, "Mining must retain a target after every resumed strike.")
			break
		var target := timing.mining_window.targets[0]
		timing.mining_window.slider_position = target.target_position
		Input.action_press(&"primary_action")
		await process_frame
		Input.action_release(&"primary_action")
		for _frame in range(180):
			await process_frame
			if not mining._is_swing_pending:
				break
		_expect(
			run_state.depth > depth_before,
			"Resumed strike %d must advance depth." % (hit_index + 1)
		)
		_expect(
			not mining._is_swing_pending
			and mining._queued_swings.is_empty(),
			"Resumed strike %d must release before the next input."
			% (hit_index + 1)
		)
	_expect(
		run_state.depth > resumed_depth,
		"Mining must continue below Cheese Girl's encounter."
	)

	game_root.queue_free()
	await process_frame
	if _failures.is_empty():
		print("CHEESE_GIRL_MINING_RESUME_PASS depth=%d" % run_state.depth)
		quit(0)
		return
	for failure: String in _failures:
		push_error("CHEESE_GIRL_MINING_RESUME_FAIL: %s" % failure)
	quit(1)


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)
