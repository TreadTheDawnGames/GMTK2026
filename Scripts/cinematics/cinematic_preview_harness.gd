class_name CinematicPreviewHarness
extends Node

## How it works:
## - Boots the real mining scene, then jumps straight to one cinematic so a
##   sequence can be watched end to end without playing up to its trigger.
## - Everything runs through the production systems: real terrain, real
##   letterbox, real dialogue. Nothing here reimplements a cinematic.
## - Number keys pick a beat, R replays the current one, Esc quits.
## - It only drives triggers; it never fakes a sequence's internals, so if a
##   beat is broken here it is broken in the game.
## The invariant is that this harness is a launcher and owns no cinematic state.

const MINING_SCENE := preload("res://Scenes/mining/mining_proof.tscn")
## Written by the cutscene editor just before it launches this harness, so
## "playtest this cutscene" opens on the encounter being authored instead of
## the surface. Absent means the ordinary numbered beats.
const PLAYTEST_TARGET_PATH := "res://.cutscene_playtest_target"

var _game_root: Node
var _active_beat: StringName = &"intro"
var _requested_encounter_id: StringName


func _ready() -> void:
	_requested_encounter_id = _read_requested_encounter_id()
	if _requested_encounter_id.is_empty():
		_restart_with_beat(&"intro")
		return
	_restart_with_beat(&"requested")


## Reads the encounter the editor asked for. A missing or empty file is the
## normal case and must stay silent, because this harness is also opened
## directly with F6.
func _read_requested_encounter_id() -> StringName:
	if not FileAccess.file_exists(PLAYTEST_TARGET_PATH):
		return &""
	var file := FileAccess.open(PLAYTEST_TARGET_PATH, FileAccess.READ)
	if file == null:
		return &""
	return StringName(file.get_as_text().strip_edges())


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key_event := event as InputEventKey
	match key_event.keycode:
		KEY_1:
			_restart_with_beat(&"intro")
		KEY_2:
			_restart_with_beat(&"rat_colony")
		KEY_3:
			_restart_with_beat(&"encounter")
		KEY_R:
			_restart_with_beat(_active_beat)
		KEY_ESCAPE:
			get_tree().quit()
		_:
			return
	get_viewport().set_input_as_handled()


## Rebuilds the mining scene from scratch, so every replay starts from the same
## state instead of inheriting whatever the last run left behind.
func _restart_with_beat(beat: StringName) -> void:
	_active_beat = beat
	if is_instance_valid(_game_root):
		_game_root.queue_free()
		_game_root = null
	await get_tree().process_frame

	var run_state := RunState.get_global(self)
	if run_state != null:
		run_state.reset_run()

	_game_root = MINING_SCENE.instantiate()
	add_child(_game_root)
	move_child(_game_root, 0)
	await get_tree().process_frame
	await get_tree().process_frame

	match beat:
		&"intro":
			_set_status("Beat: surface arrival (playing)")
		&"rat_colony":
			await _skip_run_intro()
			await _play_rat_colony_encounter()
		&"encounter":
			await _skip_run_intro()
			await _play_depth_encounter()
		&"requested":
			await _skip_run_intro()
			await _play_named_encounter(_requested_encounter_id)
		_:
			_set_status("Unknown beat '%s'." % beat)


## Collapses the surface intro so a deep beat is not gated behind it. The intro
## still runs through its real code path; only its durations are shortened.
func _skip_run_intro() -> void:
	var arrival := _game_root.get_node_or_null(
		"MiningScene/ArrivalIntro"
	) as ArrivalIntroSequence
	var flow := _game_root.get_node_or_null(
		"MiningScene/Systems/CinematicFlow"
	) as MiningCinematicFlow
	var director := _game_root.get_node_or_null(
		"DialogueDirector"
	) as DialogueDirector
	if arrival == null or flow == null or director == null:
		_set_status("Could not find the intro systems to skip.")
		return
	# Press Start, because the title screen is the game.
	#
	# The menu is drawn over the live world rather than being a scene of its own,
	# so it does not go away on its own and nothing behind it begins until it is
	# dismissed. Left up, the whole cutscene played out underneath a title card,
	# a bus stop and three buttons. Asking the menu the way a player does is what
	# starts the run.
	var menu := _game_root.get_node_or_null(
		"MainMenuLayer/MainMenu"
	) as GameMainMenu
	if menu != null and menu.has_method("_on_start_button_pressed"):
		menu._on_start_button_pressed()
		await get_tree().process_frame
	_set_status("Skipping the surface intro...")
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
	await _wait_until(
		func() -> bool:
			return not flow.is_busy(),
		20.0
	)
	# Take the gate back if the intro still has not let go.
	#
	# MiningCinematicFlow admits one owner at a time, and DepthEncounterController
	# cannot reserve a cutscene while somebody else holds it. The arrival waits on
	# player input this harness never sends, so the wait above expires, the gate
	# stays held, and the requested cutscene silently never activates - which
	# looks exactly like the harness having just restarted the game on the
	# surface. Ending whatever holds it is the difference between the beat
	# playing and nothing happening at all.
	if flow.is_busy():
		flow.finish(flow._owner)
		await get_tree().process_frame
	if flow.is_busy():
		_set_status(
			"The surface intro will not release the cinematic gate, so this "
			+ "beat cannot start."
		)


## Selects Rotini's colony resource, then crosses its real ceiling threshold.
func _play_rat_colony_encounter() -> void:
	var encounter := _get_encounter_controller()
	if encounter == null:
		_set_status("Could not find the encounter controller.")
		return
	var encounter_index := _find_encounter_index(encounter, &"rutini_second")
	if encounter_index < 0:
		_set_status("Could not find Rotini's colony encounter.")
		return
	encounter._next_encounter_index = encounter_index
	_set_status("Beat: rat colony tunnel (crossing ceiling)")
	_descend_to(_get_encounter_ceiling(encounter, encounter_index))
	await get_tree().process_frame
	# Then the fall arrives. Two steps, in the order the game does them, so the
	# controller reserves the encounter and then activates it.
	_land_at(_get_encounter_floor_depth(encounter, encounter_index))
	await get_tree().process_frame
	_set_status(
		"Beat: rat colony tunnel (playing) - R replays, 1 intro, 3 encounter"
	)


## Drops the run to the first authored depth encounter and lets it fire.
func _play_depth_encounter() -> void:
	var encounter := _get_encounter_controller()
	if encounter == null:
		_set_status("Could not find the encounter controller.")
		return
	_set_status("Beat: depth encounter (descending)")
	_descend_to(_get_encounter_ceiling(encounter, 0))
	await get_tree().process_frame
	_set_status(
		"Beat: depth encounter (playing) - R replays, 1 intro, 2 rat colony"
	)


## Crosses one named encounter's real ceiling, so the cutscene being authored
## opens the way it opens in a run: the miner breaks through and falls into it.
func _play_named_encounter(encounter_id: StringName) -> void:
	var encounter := _get_encounter_controller()
	if encounter == null:
		_set_status("Could not find the encounter controller.")
		return
	var encounter_index := _find_encounter_index(encounter, encounter_id)
	if encounter_index < 0:
		_set_status("No encounter named '%s' is scheduled." % encounter_id)
		return
	encounter._next_encounter_index = encounter_index
	_set_status("Beat: %s (crossing ceiling)" % encounter_id)
	_descend_to(_get_encounter_ceiling(encounter, encounter_index))
	await get_tree().process_frame
	# Then the fall arrives. Two steps, in the order the game does them, so the
	# controller reserves the encounter and then activates it.
	_land_at(_get_encounter_floor_depth(encounter, encounter_index))
	await get_tree().process_frame
	_set_status("Beat: %s (playing) - R replays" % encounter_id)


func _get_encounter_controller() -> DepthEncounterController:
	return _game_root.get_node_or_null(
		"MiningScene/Systems/UpgradeEncounterController"
	) as DepthEncounterController


func _find_encounter_index(
	controller: DepthEncounterController,
	encounter_id: StringName
) -> int:
	for encounter_index in range(
		controller.encounter_config.encounters.size()
	):
		var encounter := controller.encounter_config.encounters[encounter_index]
		if encounter != null and encounter.encounter_id == encounter_id:
			return encounter_index
	return -1


func _get_encounter_ceiling(
	controller: DepthEncounterController,
	encounter_index: int
) -> int:
	var encounter := controller.encounter_config.encounters[encounter_index]
	return controller.encounter_config.get_encounter_ceiling_depth(
		encounter,
		controller.mining_config.total_run_depth
	)


## Moves the run's authoritative depth so terrain streams in as it normally
## would, rather than teleporting presentation on its own.
## Drops the run to a depth and tells the game it happened.
##
## Setting RunState.depth is not enough and never was: it is a plain variable, so
## assigning it notifies nobody, DepthEncounterController never hears the ceiling
## being crossed, and the harness sits on the surface looking like it restarted
## the game rather than opening the cutscene it was asked for.
##
## The controller wants two things before it will activate an encounter - the
## depth crossing its ceiling, and a landing at or below its floor - so both are
## announced here. The landing goes through the same handler ViewController's
## own signal reaches, which is why this drives the real sequence rather than a
## shortcut around it.
func _descend_to(depth_rows: int) -> void:
	var game_state := RunState.get_global(self)
	if game_state == null:
		return
	game_state.depth = depth_rows
	game_state.depth_changed.emit(depth_rows)


## Reports the fall finishing at a depth, which is the second half of what the
## controller waits for.
##
## Crossing a ceiling only reserves an encounter; it activates when a landing
## arrives at or below its floor. Descending alone therefore reserves a cutscene
## and then waits forever for a fall that never lands, which is what left the
## harness sitting on the surface.
func _land_at(depth_rows: int) -> void:
	var game_state := RunState.get_global(self)
	var encounter := _get_encounter_controller()
	if game_state == null or encounter == null:
		return
	var mining_config: MiningConfig = encounter.mining_config
	if mining_config == null:
		return
	game_state.mining_y = mining_config.initial_surface_row + depth_rows
	# The view is a separate authority from the run's depth. Setting depth alone
	# left the camera and the terrain parked on the surface while the encounter
	# ran underneath it, so the cutscene played out over a sunset and a bus stop.
	# Mining moves the view by handing ViewController the miner's cell, and so
	# does this, for the same reason everything else here goes through production
	# systems.
	var view := _get_view_controller()
	if view != null:
		view.follow_mining_position(
			Vector2i(game_state.mining_x, game_state.mining_y)
		)
		# Let the fall finish before saying it landed.
		#
		# The view travels to its target over time and drags the cast's layer
		# with it, while the encounter stage is positioned once and stays put.
		# Announcing the landing immediately started the opening walk against a
		# frame still moving underneath it: the actor walked to a floor sampled
		# mid-fall, the room then settled several hundred pixels away, and the
		# actor stayed behind - standing well below the room, off the bottom of
		# the screen. A real run only activates an encounter once the fall is
		# over, so waiting for it is what matches the game rather than racing it.
		await _wait_until(
			func() -> bool:
				return view.target_view_position.is_equal_approx(
					view.get_current_view_position()
				),
			8.0
		)
	encounter._on_landing_reached(game_state.mining_y)


func _get_view_controller() -> ViewController:
	if not is_instance_valid(_game_root):
		return null
	return _game_root.get_node_or_null(
		"MiningScene/Systems/ViewController"
	) as ViewController


## Returns the depth an encounter's floor sits at, which is where its landing
## has to be reported.
func _get_encounter_floor_depth(
	controller: DepthEncounterController,
	encounter_index: int
) -> int:
	var encounter := controller.encounter_config.encounters[encounter_index]
	return encounter.resolve_depth(controller.mining_config.total_run_depth)


func _wait_until(condition: Callable, timeout_seconds: float) -> void:
	var deadline := (
		Time.get_ticks_msec() + int(maxf(timeout_seconds, 0.0) * 1000.0)
	)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return
		await get_tree().process_frame


## Reports what the harness is doing, to the console rather than over the game.
##
## This used to print two lines across the bottom of the screen. Playtesting a
## cutscene means looking at the cutscene, and a debug caption sitting in the
## frame is the one thing guaranteed to be in shot. The keys still work; they
## are simply not advertised on top of the thing being reviewed.
func _set_status(message: String) -> void:
	print("[cutscene playtest] ", message)
