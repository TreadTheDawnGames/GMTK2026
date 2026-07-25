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

## Rows below the surface to drop the miner before firing a deep beat, so the
## terrain around it has streamed exactly as it would in a real run.
@export_range(0, 100_000, 10) var deep_beat_depth_rows: int = 400
## Combo forced onto the breakthrough controller so the next hit qualifies.
@export_range(1, 100, 1) var forced_breakthrough_combo: int = 1

var _game_root: Node
var _status: Label
var _active_beat: StringName = &"intro"


func _ready() -> void:
	_build_status_label()
	_restart_with_beat(&"intro")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key_event := event as InputEventKey
	match key_event.keycode:
		KEY_1:
			_restart_with_beat(&"intro")
		KEY_2:
			_restart_with_beat(&"breakthrough")
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
		&"breakthrough":
			await _skip_run_intro()
			await _play_breakthrough()
		&"encounter":
			await _skip_run_intro()
			await _play_depth_encounter()
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
	_set_status("Skipping the surface intro...")
	arrival.attendant_pickup_enabled = false
	arrival.bus_arrival_seconds = 0.2
	arrival.bus_settle_seconds = 0.0
	arrival.miner_exit_delay_seconds = 0.05
	arrival.miner_reveal_hold_seconds = 0.05
	arrival.miner_walk_seconds = 0.1
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


## Arms the breakthrough and drives one qualifying hit through the real
## controller, so the beat is entered exactly as gameplay would enter it.
func _play_breakthrough() -> void:
	var controller := _game_root.get_node_or_null(
		"MiningScene/Systems/LayerBreakthroughController"
	) as LayerBreakthroughController
	var mining_controller := _game_root.get_node_or_null(
		"MiningScene/Systems/MiningController"
	) as MiningController
	if controller == null or mining_controller == null:
		_set_status("Could not find the breakthrough systems.")
		return
	_set_status("Beat: layer breakthrough (arming)")
	controller.minimum_combo = forced_breakthrough_combo
	_descend_to(deep_beat_depth_rows)
	await get_tree().process_frame
	mining_controller.resolve_attempt(true, forced_breakthrough_combo, 1)
	_set_status(
		"Beat: layer breakthrough (playing) - R replays, 1 intro, 3 encounter"
	)


## Drops the run to the first authored depth encounter and lets it fire.
func _play_depth_encounter() -> void:
	var encounter := _game_root.get_node_or_null(
		"MiningScene/Systems/UpgradeEncounterController"
	) as DepthEncounterController
	if encounter == null:
		_set_status("Could not find the encounter controller.")
		return
	_set_status("Beat: depth encounter (descending)")
	_descend_to(deep_beat_depth_rows)
	await get_tree().process_frame
	_set_status(
		"Beat: depth encounter (playing) - R replays, 1 intro, 2 breakthrough"
	)


## Moves the run's authoritative depth so terrain streams in as it normally
## would, rather than teleporting presentation on its own.
func _descend_to(depth_rows: int) -> void:
	var game_state := RunState.get_global(self)
	if game_state == null:
		return
	game_state.depth = depth_rows


func _wait_until(condition: Callable, timeout_seconds: float) -> void:
	var deadline := (
		Time.get_ticks_msec() + int(maxf(timeout_seconds, 0.0) * 1000.0)
	)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return
		await get_tree().process_frame


func _build_status_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(16.0, 16.0)
	_status.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	_status.add_theme_font_size_override("font_size", 15)
	layer.add_child(_status)


func _set_status(message: String) -> void:
	if _status != null:
		_status.text = "%s\n[1] intro  [2] breakthrough  [3] encounter  [R] replay  [Esc] quit" % message
