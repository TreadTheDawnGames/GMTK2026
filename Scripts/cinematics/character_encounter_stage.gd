class_name CharacterEncounterStage
extends Node2D

## How it works:
## - Named marker roots keep actor, prop, and action composition in the scene.
## - prepare() snapshots one presenter and places it at the authored entrance.
## - Opening/closing movement follows an injected production-floor sampler.
## - Dialogue stage_cue values play same-named AnimationPlayer animations.
## - Typed sequence actions are forwarded without making the stage their owner.
## - Closing may leave the actor at a persistent rest marker for review mode.
## - cancel_and_restore() stops motion/animation and restores the exact snapshot.
## - The stage never owns dialogue, rewards, mining gates, or encounter order.
## - The invariant is that an interrupted stage cannot strand actor state.

signal opening_finished
signal cue_started(cue_id: StringName, line_index: int)
signal cue_finished(cue_id: StringName)
signal closing_finished
signal presentation_strike_requested(screen_position: Vector2)
## Asks the owner to open real rock where a strike landed, for a character who
## mines their way into a room rather than walking into one.
signal presentation_rock_break_requested(
	screen_position: Vector2,
	radius_cells: int
)
## Asks the owner to slide the framed view off the framing this encounter settled
## on, in terrain cells, for a shot whose subject is not where the miner landed.
signal presentation_camera_pan_requested(offset_cells: Vector2)
signal sequence_dialogue_requested(
	conversation: DialogueConversation,
	line_range: Vector2i
)
## Typed timeline requests are forwarded to the encounter owner. If nothing is
## connected, playback still completes and the request is a safe no-op.
signal sequence_camera_action_requested(
	action: int,
	offset: Vector2,
	zoom: Vector2,
	shake_strength: float,
	duration_seconds: float
)
signal sequence_audio_action_requested(
	action: int,
	stream: AudioStream,
	bus: StringName,
	volume_db: float,
	pitch_scale: float,
	fade_seconds: float
)
signal sequence_vfx_action_requested(
	action: int,
	effect_id: StringName,
	scene: PackedScene,
	screen_position: Vector2,
	duration_seconds: float
)

## Terrain cells the framed view is displaced from the encounter focus.
##
## This exists to be animated. Every other way a cutscene moves is authored as a
## beat, but a pan is a continuous motion with its own easing, and an
## AnimationPlayer track is the one place in this project where a curve can be
## drawn rather than described. A STAGE_CUE beat plays that clip and blocks until
## it ends, so the timeline still owns when the pan happens and how long the shot
## waits for it, while the clip owns how it moves.
##
## The Thief finale is the legacy stage that animates it. New camera work belongs
## in typed CAMERA beats, which share the same view-controller boundary.
var camera_pan_offset_cells := Vector2.ZERO:
	set(value):
		if camera_pan_offset_cells.is_equal_approx(value):
			return
		camera_pan_offset_cells = value
		presentation_camera_pan_requested.emit(value)

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
## Seconds spent fading the actor out as the closing move runs. Zero leaves the
## old behaviour, where a departing actor is simply hidden when it arrives.
##
## Some visitors do not walk off; they go. The lantern-staff man hops once and
## fades where he stands, and the shot has to read as him ceasing to be there
## rather than as him stepping out of frame. Fading is a stage concern rather than
## an actor one because the stage already owns the reversible ownership of the
## presenter, and a presenter is reused across encounters: he is the same node all
## three times he appears, so anything that dims him has to be certain to put him
## back.
@export_range(0.0, 4.0, 0.05) var closing_fade_seconds: float = 0.0

@export_category("Actor Facing")
## Which way an actor faces on arrival, while settled to speak, and on leaving.
## -1 looks left, 1 looks right, and 0 leaves the facing alone.
##
## Zero everywhere preserves the old behaviour, where facing is whatever the walk
## last set. It matters for a visitor who is not looking at the miner: the
## lantern-staff man stands at the lip of his drop with his back turned, turns to
## deliver his warning, and turns back to it before he goes. Without this the
## walk's own direction is the only thing that can aim anyone, so a character who
## does not walk cannot be aimed at all.
##
## Facing is a world direction. CharacterPresenter folds art_faces_left in when
## it applies this, so -1 always means looking left whichever way the art is drawn.
@export_range(-1, 1, 1) var entrance_facing: int = 0
@export_range(-1, 1, 1) var conversation_facing: int = 0
@export_range(-1, 1, 1) var closing_facing: int = 0
## Dynamically keeps this actor beside the miner regardless of landing column.
@export var conversation_tracks_miner: bool = false
## Presenter-root offset; actor sprite offsets remain authored by appearance.
@export_range(-1024.0, 1024.0, 1.0) var conversation_root_offset_from_miner_x: float = 0.0
## Slides this stage's props with its tracked cast instead of leaving them
## pinned to the room.
##
## Off, and props belong to the rock: a ledge, a shaft, anything the terrain
## itself holds. On, and they belong to the conversation: the Treasure Hunter's
## hoard is the thing he is standing at and the thing the miner is looking past,
## so it has to keep the same relationship to both of them however far the
## snaking descent moved them. Left pinned, a miner landing on the hoard's side
## of the room ends up standing inside the pile.
##
## Only meaningful with conversation_tracks_miner on, because it copies the
## shift that tracking already applied. Off by default, so every room whose
## props are authored against its own terrain is untouched.
@export var props_track_tracked_cast: bool = false
## How much rock a strike on this stage opens, as a radius in terrain cells.
##
## Zero, the default, leaves a strike exactly what it has always been: dirt,
## smoke, shake and sparks against rock nothing removes. That is right for
## Rotini's rats, who are mining alongside the miner rather than through anything.
##
## Above zero the strike also breaks a bounded pocket of real terrain, which is
## what lets a character mine their way into a room. Pair it with a room whose
## approach is authored SEALED: the point is that the wall is intact when the shot
## opens, so a room already open makes the swing decorative again. The floor is
## never at risk however large this is, because the terrain call refuses guarded
## floor rows outright.
@export_range(0, 16, 1) var strike_breaks_rock_radius_cells: int = 0
## Optional visual-editor timeline. Null preserves the legacy opening walk.
@export var sequence: CutsceneSequence
## Actors already painted into this stage's own artwork, by actor id.
##
## A set piece can have a character drawn into it - Cheese Girl is part of the
## cafe storefront, not a figure standing in front of it - and placing her stand-in
## as well would show her twice. The cutscene editor skips these when it populates
## the cast, so the schedule can keep listing her as present in the scene.
@export var actors_drawn_into_set: Array[StringName] = []

var _presenter: CharacterPresenter
var _sequence_player: CutsceneSequencePlayer
var _floor_sampler: Callable
## Looks up any cast member by actor id. Injected by whoever owns the whole cast,
## because a stage only ever holds the one visitor it was given.
var cast_resolver: Callable

var _restore_position: Vector2
var _restore_visible: bool = false
var _restore_flip_h: bool = false
var _restore_modulate: Color = Color.WHITE
var _fade_tween: Tween
var _is_active: bool = false
var _active_cue: StringName


## Where the harness looks for the cutscene it has been asked to open. Shared
## with the editor plugin's playtest button, which writes the same file.
const _PLAYTEST_TARGET_PATH := "res://.cutscene_playtest_target"
const _PREVIEW_HARNESS_SCENE := "res://Scenes/cinematics/cinematic_preview.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Pressing Play on a cutscene should play that cutscene.
	#
	# Run on its own a stage is a room with markers in it and no game around it:
	# no miner, no letterbox, no dialogue, nothing to watch. Handing straight
	# over to the preview harness is what makes F6 on this scene mean what a
	# designer expects. Inside the real game this branch never runs, because the
	# stage is a child of the mining scene rather than the scene being played.
	if get_tree().current_scene == self:
		_play_as_standalone_cutscene()
		return
	if (
		is_instance_valid(animation_player)
		and not animation_player.animation_finished.is_connected(
			_on_animation_finished
		)
	):
		animation_player.animation_finished.connect(
			_on_animation_finished
		)


## Hands this cutscene to the preview harness, which boots the real game and
## breaks into this encounter's ceiling.
##
## The encounter id is read off the editor preview rather than duplicated onto
## this node, so there is only ever one place a stage says which cutscene it is.
## The preview frees itself in a running game, but queue_free is deferred, so it
## is still here to be asked during this frame.
func _play_as_standalone_cutscene() -> void:
	var encounter_id := &""
	var preview := get_node_or_null(NodePath("EditorTerrainPreview"))
	if preview != null:
		var authored: Variant = preview.get(&"encounter_id")
		if authored is StringName:
			encounter_id = authored

	if String(encounter_id).is_empty():
		push_warning(
			"This stage has no Encounter Id on its EditorTerrainPreview, so "
			+ "playing it alone cannot tell the harness which cutscene to "
			+ "open. It will start at the surface instead."
		)
	var file := FileAccess.open(_PLAYTEST_TARGET_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(String(encounter_id))
		file.close()

	# Deferred: changing scenes from inside _ready tears down the tree that is
	# still being built.
	get_tree().change_scene_to_file.call_deferred(_PREVIEW_HARNESS_SCENE)


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
	_follow_tracked_cast_with_props()
	_restore_position = presenter.global_position
	_restore_visible = presenter.visible
	_restore_flip_h = presenter.character_sprite.flip_h
	# A presenter is shared across every visit a character makes, so a previous
	# encounter that faded him out must not leave him arriving transparent.
	_restore_modulate = presenter.modulate
	presenter.modulate.a = 1.0
	_presenter.cancel_grounded_motion()
	var entrance_position := entrance_marker.global_position
	if _floor_sampler.is_valid():
		var entrance_floor_y := float(_floor_sampler.call(entrance_position.x))
		if not is_nan(entrance_floor_y) and not is_inf(entrance_floor_y):
			entrance_position.y = entrance_floor_y
	_presenter.global_position = entrance_position
	_presenter.show()
	_apply_facing(entrance_facing)
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
		_sample_level_floor.bind(_presenter.global_position.y),
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
	# After the walk, not before: a MOVE aims the actor along its own travel, so
	# anything set earlier is overwritten by the approach.
	_apply_facing(conversation_facing)
	opening_finished.emit()


## Tells a stage that a dialogue line has just gone up, and who is saying it.
##
## Does nothing here on purpose. Most stages hold still while people talk and
## need no notice of it; this exists for the ones running a continuous routine of
## their own, which otherwise have no way to know the shot is mid-sentence.
## Quibble's caffeine loop is the case that asked for it - he cannot be seen
## drinking his coffee while his own line is being typed out.
##
## The slot is passed rather than a bare "somebody is speaking", because whose
## line it is decides the answer: a character is free to carry on with whatever
## he is doing while the person opposite him talks.
##
## This is a notification, never permission. A stage may not present, advance, or
## delay a line from here; DialogueDirector remains the only thing that runs a
## conversation.
func on_dialogue_line_presented(
	_speaker_slot: StringName,
	_line_index: int
) -> void:
	pass


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
	_apply_facing(closing_facing)
	_start_closing_fade()
	var target_marker := (
		exit_marker if hide_actor_after_closing else rest_marker
	)
	var movement := _presenter.move_grounded_to(
		target_marker.global_position,
		closing_move_seconds,
		_sample_level_floor.bind(_presenter.global_position.y),
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
	_finish_closing_fade()
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
	if is_instance_valid(_fade_tween) and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	if is_instance_valid(_presenter):
		_presenter.cancel_grounded_motion()
		_presenter.global_position = _restore_position
		_presenter.character_sprite.flip_h = _restore_flip_h
		_presenter.modulate = _restore_modulate
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
	# Rock second, so the feedback and the opening are asked for in the order they
	# read: the swing lands, then the wall gives.
	if strike_breaks_rock_radius_cells > 0:
		presentation_rock_break_requested.emit(
			marker.global_position,
			strike_breaks_rock_radius_cells
		)
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


## Samples the same authored support used by every cutscene actor. Markers own
## horizontal staging only; their Y values must never pull a character away
## from the second-stratum support while entering, conversing, or leaving.
func _sample_level_floor(screen_x: float, _walk_floor_y: float) -> float:
	if not _floor_sampler.is_valid():
		return NAN
	return float(_floor_sampler.call(screen_x))


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


## Hops the actor once and fades them out over the closing move.
##
## The hop is the existing speech bounce rather than a new motion: it is already
## the one movement every presenter can make on the spot, and one of them under a
## fade reads as a departure the shot never has to follow.
func _start_closing_fade() -> void:
	if closing_fade_seconds <= 0.0 or not is_instance_valid(_presenter):
		return
	_presenter.react_to_presented_line()
	if is_instance_valid(_fade_tween) and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = _presenter.create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(
		_presenter,
		"modulate:a",
		0.0,
		closing_fade_seconds
	)


## Puts the shared presenter back to full opacity once the shot has released it.
## Without this the next encounter this character appears in opens with an
## invisible actor, and the reason would be three cutscenes away.
func _finish_closing_fade() -> void:
	if is_instance_valid(_fade_tween) and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	if closing_fade_seconds <= 0.0 or not is_instance_valid(_presenter):
		return
	_presenter.hide()
	_presenter.modulate = _restore_modulate


## Puts this stage's props under the same shift tracking gave its actor markers.
##
## DepthEncounterController slides ActorMarkers to the miner's landing column and
## leaves everything else where the room put it, which is right for a prop that
## belongs to the terrain and wrong for one that belongs to the conversation. The
## shift is read back off the marker root rather than recomputed, because the
## controller has already done that arithmetic against the miner's real foot
## position and a second derivation could only ever disagree with it.
##
## ActorMarkers is authored at the stage origin, so its x is exactly the
## accumulated shift. Assigning rather than adding keeps this correct on a repeat
## visit, where the root still carries the previous encounter's offset.
func _follow_tracked_cast_with_props() -> void:
	if (
		not props_track_tracked_cast
		or not conversation_tracks_miner
		or not is_instance_valid(actor_markers_root)
		or not is_instance_valid(prop_markers_root)
	):
		return
	prop_markers_root.position.x = actor_markers_root.position.x


## Turns the actor to face a world direction, or leaves them as they are on zero.
func _apply_facing(direction: int) -> void:
	if direction == 0 or not is_instance_valid(_presenter):
		return
	_presenter.set_facing_direction(direction)


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
	if not _sequence_player.camera_action_requested.is_connected(
		_on_sequence_camera_action_requested
	):
		_sequence_player.camera_action_requested.connect(
			_on_sequence_camera_action_requested
		)
	if not _sequence_player.audio_action_requested.is_connected(
		_on_sequence_audio_action_requested
	):
		_sequence_player.audio_action_requested.connect(
			_on_sequence_audio_action_requested
		)
	if not _sequence_player.vfx_action_requested.is_connected(
		_on_sequence_vfx_action_requested
	):
		_sequence_player.vfx_action_requested.connect(
			_on_sequence_vfx_action_requested
		)


## Resolves a timeline's actor id to something on screen.
##
## The stage owns exactly one presenter - the visitor it took in prepare() - so
## anything else a timeline names has to come from the schedule, which is the
## only thing holding the whole cast. A cafe beat addressing four characters
## resolves all four through the injected lookup; a stage running on its own in
## the editor resolves none and simply plays nothing, which is the old behaviour.
##
## `miner` deliberately still answers with the visitor rather than MinerRig. Every
## generated placeholder timeline in the project addresses its actor by that name,
## and repointing it at the real rig would have those timelines drive the player
## around his own cutscene the moment the runtime went live.
func _resolve_sequence_actor(actor_id: StringName) -> Node2D:
	if actor_id == &"miner":
		return _presenter
	if cast_resolver.is_valid():
		var resolved: Variant = cast_resolver.call(actor_id)
		if is_instance_valid(resolved):
			return resolved as Node2D
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


func _on_sequence_camera_action_requested(
	action: int,
	offset: Vector2,
	zoom: Vector2,
	shake_strength: float,
	duration_seconds: float
) -> void:
	sequence_camera_action_requested.emit(
		action,
		offset,
		zoom,
		shake_strength,
		duration_seconds
	)


func _on_sequence_audio_action_requested(
	action: int,
	stream: AudioStream,
	bus: StringName,
	volume_db: float,
	pitch_scale: float,
	fade_seconds: float
) -> void:
	sequence_audio_action_requested.emit(
		action,
		stream,
		bus,
		volume_db,
		pitch_scale,
		fade_seconds
	)


func _on_sequence_vfx_action_requested(
	action: int,
	effect_id: StringName,
	scene: PackedScene,
	screen_position: Vector2,
	duration_seconds: float
) -> void:
	sequence_vfx_action_requested.emit(
		action,
		effect_id,
		scene,
		screen_position,
		duration_seconds
	)


## Releases a timeline that is holding for dialogue it asked somebody else to run.
##
## A blocking DIALOGUE beat stops the sequence clock and waits, because a line
## takes as long as the player takes to read it and no authored duration can know
## that. The stage never presents dialogue itself, so the owner that did has to
## say when it finished; without this the timeline holds for the rest of the run.
func notify_dialogue_finished() -> void:
	if is_instance_valid(_sequence_player):
		_sequence_player.notify_dialogue_finished()


## Reports whether a timeline is driving this stage, so an owner knows whether
## the sequence or the conversation is the thing in charge.
func is_playing_sequence() -> bool:
	return is_instance_valid(_sequence_player) and _sequence_player.is_playing()
