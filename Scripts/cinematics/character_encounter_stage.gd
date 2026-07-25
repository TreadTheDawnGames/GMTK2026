class_name CharacterEncounterStage
extends Node2D

## How it works:
## - Named marker roots keep actor, prop, and action composition in the scene.
## - prepare() snapshots one presenter and places it at the authored entrance.
## - Opening/closing movement follows an injected production-floor sampler.
## - Dialogue stage_cue values play same-named AnimationPlayer animations.
## - Closing may leave the actor at a persistent rest marker for review mode.
## - cancel_and_restore() stops motion/animation and restores the exact snapshot.
## - The stage never owns dialogue, rewards, mining gates, or encounter order.
## - The invariant is that an interrupted stage cannot strand actor state.

signal opening_finished
signal cue_started(cue_id: StringName, line_index: int)
signal cue_finished(cue_id: StringName)
signal closing_finished
signal presentation_strike_requested(screen_position: Vector2)
signal sequence_dialogue_requested(
	conversation: DialogueConversation,
	line_range: Vector2i
)

@export_category("Named Marker Roots")
@export var actor_markers_root: Node2D
@export var prop_markers_root: Node2D
@export var action_markers_root: Node2D

@export_category("Actor Markers")
@export var entrance_marker: Marker2D
@export var conversation_marker: Marker2D
@export var work_marker: Marker2D
@export var rest_marker: Marker2D
@export var exit_marker: Marker2D

@export_category("Cue Playback")
@export var animation_player: AnimationPlayer
@export var opening_animation: StringName = &"opening"
@export var closing_animation: StringName = &"closing"

@export_category("Actor Motion")
@export_range(0.01, 8.0, 0.01) var opening_move_seconds: float = 0.6
@export_range(0.01, 8.0, 0.01) var closing_move_seconds: float = 0.6
@export_range(0.0, 16.0, 0.5) var opening_step_height: float = 4.0
@export var opening_pose: StringName = &"walk"
@export var conversation_pose: StringName = &"idle"
@export var closing_pose: StringName = &"walk"
@export var rest_pose: StringName = &"idle"
@export var hide_actor_after_closing: bool = false
## Dynamically keeps this actor beside the miner regardless of landing column.
@export var conversation_tracks_miner: bool = false
## Presenter-root offset; actor sprite offsets remain authored by appearance.
@export_range(-256.0, 256.0, 1.0) var conversation_root_offset_from_miner_x: float = 0.0
## Optional visual-editor timeline. Null preserves the legacy opening walk.
@export var sequence: CutsceneSequence

var _presenter: CharacterPresenter
var _sequence_player: CutsceneSequencePlayer
var _floor_sampler: Callable
var _restore_position: Vector2
var _restore_visible: bool = false
var _restore_flip_h: bool = false
var _is_active: bool = false
var _active_cue: StringName


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if (
		is_instance_valid(animation_player)
		and not animation_player.animation_finished.is_connected(
			_on_animation_finished
		)
	):
		animation_player.animation_finished.connect(
			_on_animation_finished
		)


## Takes reversible ownership of one presenter for this encounter visit.
func prepare(
	presenter: CharacterPresenter,
	floor_sampler: Callable
) -> bool:
	if (
		_is_active
		or not is_instance_valid(presenter)
		or not validate_stage().is_empty()
	):
		return false
	_presenter = presenter
	_floor_sampler = floor_sampler
	_restore_position = presenter.global_position
	_restore_visible = presenter.visible
	_restore_flip_h = presenter.character_sprite.flip_h
	_presenter.cancel_grounded_motion()
	_presenter.global_position = entrance_marker.global_position
	_presenter.show()
	_is_active = true
	return true


## Moves the actor into conversation while the authored opening clip plays.
func play_opening() -> void:
	if not _is_active:
		return
	if sequence != null:
		await _play_sequence_opening()
		return
	_play_pose_if_available(opening_pose)
	var movement := _presenter.move_grounded_to(
		conversation_marker.global_position,
		opening_move_seconds,
		_floor_sampler,
		false,
		opening_step_height
	)
	var animation_name := _play_named_animation(opening_animation)
	if movement != null:
		await movement.finished
	await _wait_for_animation(animation_name)
	if not _is_active:
		return
	_play_pose_if_available(conversation_pose)
	opening_finished.emit()


## Plays one editor-authored animation named by the active dialogue line.
func play_cue(cue_id: StringName, line_index: int) -> bool:
	if (
		not _is_active
		or cue_id.is_empty()
		or not animation_player.has_animation(cue_id)
	):
		return false
	_active_cue = cue_id
	animation_player.play(cue_id)
	cue_started.emit(cue_id, line_index)
	return true


## Moves to the persistent rest/exit marker after the conversation.
func play_closing() -> void:
	if not _is_active:
		return
	_play_pose_if_available(closing_pose)
	var target_marker := (
		exit_marker if hide_actor_after_closing else rest_marker
	)
	var movement := _presenter.move_grounded_to(
		target_marker.global_position,
		closing_move_seconds,
		_floor_sampler,
		hide_actor_after_closing
	)
	var animation_name := _play_named_animation(closing_animation)
	if movement != null:
		await movement.finished
	await _wait_for_animation(animation_name)
	if not _is_active:
		return
	if not hide_actor_after_closing:
		_play_pose_if_available(rest_pose)
	_is_active = false
	_presenter = null
	_floor_sampler = Callable()
	closing_finished.emit()


## Restores the presenter and stage animation after interruption or failure.
func cancel_and_restore() -> void:
	if not _is_active:
		return
	if is_instance_valid(_sequence_player):
		_sequence_player.stop()
	if is_instance_valid(animation_player):
		animation_player.stop()
		if animation_player.has_animation(&"RESET"):
			animation_player.play(&"RESET")
			animation_player.advance(0.0)
			animation_player.stop()
	if is_instance_valid(_presenter):
		_presenter.cancel_grounded_motion()
		_presenter.global_position = _restore_position
		_presenter.character_sprite.flip_h = _restore_flip_h
		if _restore_visible:
			_presenter.show()
		else:
			_presenter.hide()
		_presenter.reset_speech_motion()
	_presenter = null
	_floor_sampler = Callable()
	_active_cue = &""
	_is_active = false


## Requests one shared strike by an ActionMarkers child name from an animation.
func request_presentation_strike(marker_name: StringName) -> bool:
	if not _is_active or marker_name.is_empty():
		return false
	var marker := (
		action_markers_root.get_node_or_null(NodePath(marker_name))
		as Marker2D
	)
	if marker == null:
		push_error(
			"Encounter stage has no ActionMarkers/%s Marker2D."
			% marker_name
		)
		return false
	presentation_strike_requested.emit(marker.global_position)
	return true


## Reports actionable scene-authoring errors without taking actor ownership.
func validate_stage() -> String:
	var required_nodes: Array[Node] = [
		actor_markers_root,
		prop_markers_root,
		action_markers_root,
		entrance_marker,
		conversation_marker,
		work_marker,
		rest_marker,
		exit_marker,
		animation_player,
	]
	for required_node in required_nodes:
		if not is_instance_valid(required_node):
			return "Character encounter stage has an unassigned named node."
	if opening_move_seconds <= 0.0 or closing_move_seconds <= 0.0:
		return "Character encounter stage motion durations must be positive."
	return ""


func _play_named_animation(animation_name: StringName) -> StringName:
	if (
		animation_name.is_empty()
		or not animation_player.has_animation(animation_name)
	):
		return &""
	animation_player.play(animation_name)
	return animation_name


func _wait_for_animation(animation_name: StringName) -> void:
	if animation_name.is_empty():
		return
	while (
		_is_active
		and animation_player.is_playing()
		and animation_player.current_animation == animation_name
	):
		await animation_player.animation_finished


func _play_pose_if_available(pose_name: StringName) -> void:
	if (
		not pose_name.is_empty()
		and is_instance_valid(_presenter)
		and _presenter.has_pose(pose_name)
	):
		_presenter.play_pose(pose_name)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != _active_cue:
		return
	var finished_cue := _active_cue
	_active_cue = &""
	cue_finished.emit(finished_cue)


func _play_sequence_opening() -> void:
	_ensure_sequence_player()
	_sequence_player.bind(
		_resolve_sequence_actor,
		_resolve_sequence_marker,
		_floor_sampler,
		self
	)
	_sequence_player.play(sequence)
	while _is_active and _sequence_player.is_playing():
		await get_tree().process_frame
	if not _is_active:
		return
	opening_finished.emit()


func _ensure_sequence_player() -> void:
	if is_instance_valid(_sequence_player):
		return
	_sequence_player = CutsceneSequencePlayer.new()
	_sequence_player.name = &"CutsceneSequencePlayer"
	add_child(_sequence_player)
	if not _sequence_player.dialogue_requested.is_connected(
		_on_sequence_dialogue_requested
	):
		_sequence_player.dialogue_requested.connect(
			_on_sequence_dialogue_requested
		)


func _resolve_sequence_actor(actor_id: StringName) -> Node2D:
	if actor_id == &"miner":
		return _presenter
	return null


func _resolve_sequence_marker(marker_name: StringName) -> Vector2:
	var roots: Array[Node2D] = [actor_markers_root, prop_markers_root]
	for root in roots:
		if not is_instance_valid(root):
			continue
		var marker := root.get_node_or_null(NodePath(marker_name)) as Marker2D
		if marker != null:
			return marker.global_position
	return Vector2(NAN, NAN)


func _on_sequence_dialogue_requested(
	conversation: DialogueConversation,
	line_range: Vector2i
) -> void:
	sequence_dialogue_requested.emit(conversation, line_range)
