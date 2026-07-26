extends SceneTree

## Reports where the Thief's runtime presenter actually ends up.
##
## The stage's editor stand-in and the runtime presenter are different objects on
## different parents, and only the stand-in shows up in a capture. So a shot can
## look finished in every rendered frame and still have nobody in it when the
## game runs, which is exactly what happened. This drives the real controller the
## way the preview harness does and then prints the presenter's state next to the
## marks it was supposed to land on.
##
##   godot --headless --path . --script res://local_tests/diagnose_thief_presenter.gd

const MINING_SCENE: PackedScene = preload(
	"res://Scenes/mining/mining_proof.tscn"
)
const ENCOUNTER_ID: StringName = &"thief_finale"
const SETTLE_FRAMES: int = 240


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_root := MINING_SCENE.instantiate()
	root.add_child(game_root)
	await process_frame
	await process_frame

	var controller := game_root.get_node_or_null(
		"MiningScene/Systems/UpgradeEncounterController"
	) as DepthEncounterController
	var run_state := root.get_node_or_null(^"/root/GameState") as RunState
	var view := game_root.get_node_or_null(
		"MiningScene/Systems/ViewController"
	) as ViewController
	if controller == null or run_state == null:
		push_error("Could not reach the controller or the run state.")
		quit(1)
		return

	# The arrival intro owns the shared cinematic gate until the run has started,
	# and _schedule_next_encounter refuses silently while anything else holds it.
	# Skipping the intro the way the preview harness does is what makes this a
	# test of the encounter rather than a test of the title screen.
	await _skip_intro(game_root)

	var encounter_index := -1
	for index in range(controller.encounter_config.encounters.size()):
		var candidate := controller.encounter_config.encounters[index]
		if candidate != null and candidate.encounter_id == ENCOUNTER_ID:
			encounter_index = index
			break
	if encounter_index < 0:
		push_error("The finale is not in the schedule.")
		quit(1)
		return
	var encounter := controller.encounter_config.encounters[encounter_index]

	controller._next_encounter_index = encounter_index
	var floor_depth := encounter.resolve_depth(
		controller.mining_config.total_run_depth
	)
	var ceiling_depth := controller.encounter_config.get_encounter_ceiling_depth(
		encounter,
		controller.mining_config.total_run_depth
	)
	run_state.depth = ceiling_depth
	run_state.depth_changed.emit(ceiling_depth)
	await process_frame
	run_state.mining_y = (
		controller.mining_config.initial_surface_row + floor_depth
	)
	if view != null:
		view.follow_mining_position(
			Vector2i(run_state.mining_x, run_state.mining_y)
		)
		view.snap_follow_to_target()
	await process_frame
	controller._on_landing_reached(run_state.mining_y)
	for _settle in range(SETTLE_FRAMES):
		await process_frame

	_report(controller, game_root)
	game_root.queue_free()
	await process_frame
	quit(0)


## Dismisses the title menu and collapses the arrival so the gate is free.
func _skip_intro(game_root: Node) -> void:
	var arrival := game_root.get_node_or_null(
		"MiningScene/ArrivalIntro"
	) as ArrivalIntroSequence
	var flow := game_root.get_node_or_null(
		"MiningScene/Systems/CinematicFlow"
	) as MiningCinematicFlow
	var director := game_root.get_node_or_null(
		"DialogueDirector"
	) as DialogueDirector
	if arrival == null or flow == null or director == null:
		push_error("Could not find the intro systems to skip.")
		return
	var menu := game_root.get_node_or_null(
		"MainMenuLayer/MainMenu"
	) as GameMainMenu
	if menu != null and menu.has_method("_on_start_button_pressed"):
		menu._on_start_button_pressed()
		await process_frame
	arrival.attendant_pickup_enabled = false
	arrival.bus_arrival_seconds = 0.2
	arrival.bus_settle_seconds = 0.0
	arrival.miner_exit_delay_seconds = 0.05
	arrival.hold_before_dialogue_seconds = 0.0
	arrival.bus_departure_seconds = 0.2
	if director.cinematic_frame != null:
		director.cinematic_frame.blackout_reveal_seconds = 0.05
	for _frame in range(900):
		if director.is_conversation_active():
			break
		await process_frame
	if director.is_conversation_active():
		director.finish_conversation()
	for _frame in range(900):
		if not flow.is_busy():
			break
		await process_frame
	print("THIEF_DIAG intro_skipped flow_busy=%s" % str(flow.is_busy()))


## Prints everything that decides whether the figure is on screen.
func _report(
	controller: DepthEncounterController,
	game_root: Node
) -> void:
	print("THIEF_DIAG active_encounter=%d pending=%d next=%d" % [
		controller._active_encounter_index,
		controller._pending_encounter_index,
		controller._next_encounter_index,
	])
	var stage := controller._active_stage
	print("THIEF_DIAG active_stage=%s" % (
		stage.name if is_instance_valid(stage) else "<none>"
	))
	if is_instance_valid(stage):
		print("THIEF_DIAG stage_global=%s validate='%s'" % [
			str(stage.global_position),
			stage.validate_stage(),
		])
		var conversation_marker: Node2D = stage.conversation_marker
		if is_instance_valid(conversation_marker):
			print("THIEF_DIAG conversation_mark_global=%s" % str(
				conversation_marker.global_position
			))
		var organ := stage.get_node_or_null(^"PropMarkers/Organ") as Node2D
		if is_instance_valid(organ):
			print("THIEF_DIAG organ_global=%s visible=%s" % [
				str(organ.global_position),
				str(organ.visible),
			])

	var presenter: CharacterPresenter = (
		controller._presenters_by_actor_id.get(&"thief")
	)
	if presenter == null:
		print("THIEF_DIAG presenter=<MISSING for actor 'thief'>")
		print("THIEF_DIAG known_actors=%s" % str(
			controller._presenters_by_actor_id.keys()
		))
		return
	print("THIEF_DIAG presenter_global=%s visible=%s alpha=%.2f" % [
		str(presenter.global_position),
		str(presenter.visible),
		presenter.modulate.a,
	])
	print("THIEF_DIAG presenter_visible_in_tree=%s parent=%s" % [
		str(presenter.is_visible_in_tree()),
		str(presenter.get_parent().name) if presenter.get_parent() else "<none>",
	])
	var sprite := presenter.character_sprite
	if is_instance_valid(sprite):
		print(
			"THIEF_DIAG sprite texture=%s hframes=%d frame=%d scale=%s pos=%s"
			% [
				sprite.texture.resource_path if sprite.texture else "<none>",
				sprite.hframes,
				sprite.frame,
				str(sprite.scale),
				str(sprite.position),
			]
		)
	var layer := presenter.get_parent() as CanvasItem
	if layer != null:
		print("THIEF_DIAG cast_layer z=%d visible=%s" % [
			layer.z_index,
			str(layer.visible),
		])
	# Draw order between the prop and the figure standing at it. They are on the
	# same parent, so equal z means tree order decides, and the stage is added
	# long after the presenters were built.
	if is_instance_valid(stage):
		var organ := stage.get_node_or_null(^"PropMarkers/Organ") as Node2D
		print(
			"THIEF_DIAG order stage(parent=%s index=%d z=%d rel=%s)"
			% [
				stage.get_parent().name,
				stage.get_index(),
				stage.z_index,
				str(stage.z_as_relative),
			]
		)
		print(
			"THIEF_DIAG order presenter(index=%d z=%d rel=%s)"
			% [
				presenter.get_index(),
				presenter.z_index,
				str(presenter.z_as_relative),
			]
		)
		if is_instance_valid(organ):
			print(
				"THIEF_DIAG order organ(z=%d rel=%s) props_z=%d"
				% [
					organ.z_index,
					str(organ.z_as_relative),
					(stage.prop_markers_root as Node2D).z_index,
				]
			)
			# The whole point of the check: the figure has to win, and equal z
			# would hand it to tree order, where the stage is added last.
			var organ_wins := organ.z_index >= presenter.z_index
			print(
				"THIEF_DIAG VERDICT figure_is_%s"
				% ("HIDDEN_BY_ORGAN" if organ_wins else "visible")
			)
	# Where the camera is looking, so an off-screen figure can be told from an
	# invisible one.
	var view := game_root.get_node_or_null(
		"MiningScene/Systems/ViewController"
	) as ViewController
	if view != null:
		print("THIEF_DIAG view=(%.1f, %.1f) miner_screen_offset=%s" % [
			view.current_view_x,
			view.current_view_y,
			str(view.get_miner_screen_offset()),
		])
