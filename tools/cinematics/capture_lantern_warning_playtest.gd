extends SceneTree

## How it works:
## - Boots the production cinematic harness on Encounter 5.
## - Captures the live settle, camera, dialogue, parity, close, and mining handoff.
## - Finishes dialogue through its real director and requests one real swing.
## - ENCOUNTER_5_CAPTURE_DIR keeps evidence outside the repository.
## - Restores the harness target file after the run.
## - The invariant is that every frame comes from the production mining scene.

const PREVIEW_SCENE: PackedScene = preload(
	"res://Scenes/cinematics/cinematic_preview.tscn"
)
const PLAYTEST_TARGET_PATH: String = "res://.cutscene_playtest_target"
const ENCOUNTER_ID: String = "cloak_lantern_warning"
const DEFAULT_OUTPUT_DIRECTORY: String = "user://encounter_5_runtime_capture"
const VIEWPORT_SIZE := Vector2i(1152, 648)

var _output_directory: String
var _harness: CinematicPreviewHarness
var _previous_target: String
var _had_previous_target: bool = false
var _capture_count: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_output_directory = OS.get_environment("ENCOUNTER_5_CAPTURE_DIR")
	if _output_directory.is_empty():
		_output_directory = ProjectSettings.globalize_path(
			DEFAULT_OUTPUT_DIRECTORY
		)
	DirAccess.make_dir_recursive_absolute(_output_directory)
	root.size = VIEWPORT_SIZE
	_store_and_write_target()
	_harness = PREVIEW_SCENE.instantiate() as CinematicPreviewHarness
	root.add_child(_harness)

	var ready := await _wait_until(
		func() -> bool:
			return (
				is_instance_valid(_get_encounter_controller())
				and _get_encounter_controller()._active_stage != null
				and _get_encounter_controller()._active_stage._is_active
			),
		25.0
	)
	if not ready:
		await _finish_with_error("The production harness never activated Encounter 5.")
		return
	await process_frame
	await _capture("01_fall_discovery.png")

	await create_timer(0.25).timeout
	await _capture("02_camera_push.png")

	var dialogue_ready := await _wait_until(
		func() -> bool:
			var director := _get_dialogue_director()
			return director != null and director.is_conversation_active(),
		8.0
	)
	if not dialogue_ready:
		await _finish_with_error("Encounter 5 never reached its dialogue.")
		return
	await create_timer(0.15).timeout
	await _capture("03_dialogue_frame.png")

	_set_logical_overlay(true)
	await process_frame
	await _capture("04_f3_parity.png")
	_set_logical_overlay(false)

	var director := _get_dialogue_director()
	director.finish_conversation()
	var closing_started := await _wait_until(
		func() -> bool:
			var controller := _get_encounter_controller()
			if controller == null or controller._active_stage == null:
				return false
			var player := (
				controller._active_stage.animation_player as AnimationPlayer
			)
			return (
				player != null
				and player.current_animation == &"closing"
				and player.is_playing()
			),
		8.0
	)
	if not closing_started:
		await _finish_with_error("The Keeper/bench closing fade never started.")
		return
	await create_timer(0.3).timeout
	await _capture("05_closing_mid_fade.png")

	var mining_ready := await _wait_until(
		func() -> bool:
			var controller := _get_encounter_controller()
			var flow := _get_cinematic_flow()
			return (
				controller != null
				and controller._active_stage == null
				and flow != null
				and not flow.is_busy()
			),
		12.0
	)
	if not mining_ready:
		await _finish_with_error("Mining control did not return after Encounter 5.")
		return
	await _capture("06_closing_handoff.png")

	var run_state := root.get_node_or_null("/root/GameState") as RunState
	var depth_before := run_state.depth if run_state != null else -1
	var mining_controller := _get_mining_controller()
	mining_controller.resolve_attempt(true, 3, 1)
	var impact_finished := await _wait_until(
		func() -> bool:
			return run_state != null and run_state.depth > depth_before,
		5.0
	)
	if not impact_finished:
		await _finish_with_error("The first post-cutscene mining impact did not resolve.")
		return
	await process_frame
	await _capture("07_first_mining_impact.png")

	_restore_target()
	print(
		"ENCOUNTER_5_RUNTIME_CAPTURE: %d/7 frames in %s"
		% [_capture_count, _output_directory]
	)
	quit(0 if _capture_count == 7 else 1)


func _get_encounter_controller() -> DepthEncounterController:
	if not is_instance_valid(_harness) or not is_instance_valid(_harness._game_root):
		return null
	return _harness._game_root.get_node_or_null(
		"MiningScene/Systems/UpgradeEncounterController"
	) as DepthEncounterController


func _get_dialogue_director() -> DialogueDirector:
	if not is_instance_valid(_harness) or not is_instance_valid(_harness._game_root):
		return null
	return _harness._game_root.get_node_or_null(
		"DialogueDirector"
	) as DialogueDirector


func _get_cinematic_flow() -> MiningCinematicFlow:
	if not is_instance_valid(_harness) or not is_instance_valid(_harness._game_root):
		return null
	return _harness._game_root.get_node_or_null(
		"MiningScene/Systems/CinematicFlow"
	) as MiningCinematicFlow


func _get_mining_controller() -> MiningController:
	if not is_instance_valid(_harness) or not is_instance_valid(_harness._game_root):
		return null
	return _harness._game_root.get_node_or_null(
		"MiningScene/Systems/MiningController"
	) as MiningController


func _capture(file_name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	if image == null:
		push_error("Nothing rendered for %s." % file_name)
		return
	var output_path := _output_directory.path_join(file_name)
	if image.save_png(output_path) != OK:
		push_error("Could not write %s." % output_path)
		return
	_capture_count += 1


func _set_logical_overlay(enabled: bool) -> void:
	var renderer := _harness._game_root.get_node_or_null(
		"MiningScene/TerrainLayerRenderer"
	) as TerrainLayerRenderer
	if renderer == null:
		return
	renderer._show_logical_overlay = enabled
	renderer.queue_redraw()


func _wait_until(condition: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return false


func _store_and_write_target() -> void:
	_had_previous_target = FileAccess.file_exists(PLAYTEST_TARGET_PATH)
	if _had_previous_target:
		var previous := FileAccess.open(PLAYTEST_TARGET_PATH, FileAccess.READ)
		if previous != null:
			_previous_target = previous.get_as_text()
	var target := FileAccess.open(PLAYTEST_TARGET_PATH, FileAccess.WRITE)
	if target != null:
		target.store_string(ENCOUNTER_ID)


func _restore_target() -> void:
	if _had_previous_target:
		var target := FileAccess.open(PLAYTEST_TARGET_PATH, FileAccess.WRITE)
		if target != null:
			target.store_string(_previous_target)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PLAYTEST_TARGET_PATH))


func _finish_with_error(message: String) -> void:
	push_error(message)
	_restore_target()
	quit(1)
