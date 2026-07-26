@tool
class_name CutsceneSequencePlayer
extends Node

## How it works:
## - An injected resolver supplies actors, global markers, terrain, and stage.
## - The authored clock starts eligible beats together and holds at blocking ends.
## - MOVE and PROP routes share distance-weighted waypoint path evaluation.
## - Dialogue is only requested; the owner completes it with notify_dialogue_finished().
## - Camera, audio, and VFX beats emit typed requests; absent consumers are no-ops.
## - evaluate_at simulates the same path/action state math without mutations.
## - stop kills owned motion and invalidates every stale callback by generation.
## - The invariant is that a stopped or superseded sequence can emit nothing later.

signal beat_started(beat: CutsceneBeat, index: int)
signal beat_finished(beat: CutsceneBeat, index: int)
signal dialogue_requested(
	conversation: DialogueConversation,
	line_range: Vector2i
)
signal camera_action_requested(
	action: int,
	offset: Vector2,
	zoom: Vector2,
	shake_strength: float,
	duration_seconds: float
)
signal audio_action_requested(
	action: int,
	stream: AudioStream,
	bus: StringName,
	volume_db: float,
	pitch_scale: float,
	fade_seconds: float
)
signal vfx_action_requested(
	action: int,
	effect_id: StringName,
	scene: PackedScene,
	screen_position: Vector2,
	duration_seconds: float
)
signal finished

const GroundWalkType = preload("res://Scripts/cinematics/ground_walk.gd")

enum BeatState {
	NOT_STARTED,
	ACTIVE,
	FINISHED,
}

var _actor_resolver: Callable
var _marker_resolver: Callable
var _floor_sampler: Callable
var _stage: CharacterEncounterStage

var _sequence: CutsceneSequence
var _sorted_indices: Array[int] = []
var _next_sorted_index: int = 0
var _beat_states: Array[int] = []
var _beat_tweens: Dictionary = {}
var _actor_motion_beats: Dictionary = {}
var _evaluation_initial_states: Dictionary = {}
var _timeline_seconds: float = 0.0
var _held_beat_index: int = -1
var _waiting_dialogue_index: int = -1
var _waiting_stage_cue_index: int = -1
var _play_generation: int = 0
var _is_playing: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Injects every lookup the player is allowed to perform for its lifetime.
func bind(
	actor_resolver: Callable,
	marker_resolver: Callable,
	floor_sampler: Callable,
	stage: CharacterEncounterStage = null
) -> void:
	if (
		is_instance_valid(_stage)
		and _stage.has_signal(&"cue_finished")
		and _stage.is_connected(&"cue_finished", _on_stage_cue_finished)
	):
		_stage.disconnect(&"cue_finished", _on_stage_cue_finished)
	_actor_resolver = actor_resolver
	_marker_resolver = marker_resolver
	_floor_sampler = floor_sampler
	_stage = stage
	if (
		is_instance_valid(_stage)
		and _stage.has_signal(&"cue_finished")
		and not _stage.is_connected(&"cue_finished", _on_stage_cue_finished)
	):
		_stage.connect(&"cue_finished", _on_stage_cue_finished)


## Starts a sequence; completion is reported through the finished signal.
func play(sequence: CutsceneSequence) -> void:
	if sequence == null:
		return
	if _is_playing:
		stop()
	_play_generation += 1
	_sequence = sequence
	_sorted_indices = _get_sorted_indices(sequence)
	_next_sorted_index = 0
	_beat_states.clear()
	_beat_states.resize(sequence.beats.size())
	for beat_index in range(_beat_states.size()):
		_beat_states[beat_index] = BeatState.NOT_STARTED
	_beat_tweens.clear()
	_actor_motion_beats.clear()
	_timeline_seconds = 0.0
	_held_beat_index = -1
	_waiting_dialogue_index = -1
	_waiting_stage_cue_index = -1
	_is_playing = true
	set_process(true)
	_capture_evaluation_initial_states(sequence)
	_advance_clock(0.0)
	_check_for_completion()


## Cancels all owned motion and invalidates callbacks without emitting finished.
func stop() -> void:
	if not _is_playing and _beat_tweens.is_empty():
		return
	_play_generation += 1
	_is_playing = false
	set_process(false)
	for tween_variant in _beat_tweens.values():
		var tween := tween_variant as Tween
		if tween != null and tween.is_valid():
			tween.kill()
	_beat_tweens.clear()
	for actor_id_variant in _evaluation_initial_states.keys():
		var actor_id := StringName(actor_id_variant)
		var actor := _resolve_actor(actor_id)
		if actor is CharacterPresenter:
			var presenter := actor as CharacterPresenter
			presenter.cancel_grounded_motion()
			presenter.reset_speech_motion()
	if is_instance_valid(_stage) and is_instance_valid(_stage.animation_player):
		_stage.animation_player.stop()
	_actor_motion_beats.clear()
	_sequence = null
	_sorted_indices.clear()
	_next_sorted_index = 0
	_beat_states.clear()
	_held_beat_index = -1
	_waiting_dialogue_index = -1
	_waiting_stage_cue_index = -1


## Reports whether the player still owns an unfinished sequence.
func is_playing() -> bool:
	return _is_playing


## Completes the active blocking dialogue beat after the owner finishes it.
func notify_dialogue_finished() -> void:
	if not _is_playing or _waiting_dialogue_index < 0:
		return
	var dialogue_index := _waiting_dialogue_index
	_waiting_dialogue_index = -1
	_finish_beat(dialogue_index, _play_generation)
	_check_for_completion()


## Evaluates authored presentation state without changing nodes or creating tweens.
## Result contains direct actor-id keys, an `actors` mirror, stage cue, and dialogue data.
func evaluate_at(
	sequence: CutsceneSequence,
	seconds: float
) -> Dictionary:
	var result: Dictionary = {}
	if sequence == null:
		result[&"actors"] = {}
		result[&"stage_cue"] = StringName()
		result[&"dialogue"] = null
		result[&"camera"] = _default_camera_state()
		result[&"audio"] = _default_audio_state()
		result[&"vfx"] = {}
		return result
	var actor_states: Dictionary = {}
	var evaluation_seconds := maxf(seconds, 0.0)
	var stage_cue := _evaluate_stage_cue_at(sequence, evaluation_seconds)
	for actor_id_text in sequence.get_actor_ids():
		var actor_id := StringName(actor_id_text)
		var state := _evaluate_actor_at(
			sequence,
			actor_id,
			evaluation_seconds
		)
		state[&"stage_cue"] = stage_cue
		actor_states[actor_id] = state
		result[actor_id] = state
	result[&"actors"] = actor_states
	result[&"stage_cue"] = stage_cue
	result[&"dialogue"] = _evaluate_dialogue_at(
		sequence,
		evaluation_seconds
	)
	result[&"camera"] = _evaluate_camera_at(sequence, evaluation_seconds)
	result[&"audio"] = _evaluate_audio_at(sequence, evaluation_seconds)
	result[&"vfx"] = _evaluate_vfx_at(sequence, evaluation_seconds)
	return result


func _process(delta: float) -> void:
	if not _is_playing:
		return
	_advance_clock(maxf(delta, 0.0))
	_check_for_completion()


func _advance_clock(delta: float) -> void:
	if _held_beat_index >= 0:
		if _beat_states[_held_beat_index] == BeatState.ACTIVE:
			return
		_held_beat_index = -1
	if _sequence == null:
		return
	var sequence_duration := _sequence.get_duration_seconds()
	_timeline_seconds = minf(
		_timeline_seconds + delta,
		sequence_duration
	)
	var initial_hold := _find_blocking_end(_timeline_seconds)
	if initial_hold["index"] >= 0:
		var hold_end := float(initial_hold["end"])
		var hold_index := int(initial_hold["index"])
		var hold_beat := _sequence.beats[hold_index]
		if _beat_states[hold_index] == BeatState.NOT_STARTED:
			_start_due_beats(hold_beat.start_seconds, true)
		_start_due_beats(hold_end, false)
	else:
		_start_due_beats(_timeline_seconds)
	var active_hold := _find_blocking_end(_timeline_seconds)
	if active_hold["index"] >= 0:
		_timeline_seconds = float(active_hold["end"])
		_held_beat_index = int(active_hold["index"])


func _start_due_beats(start_limit: float, include_limit: bool = true) -> void:
	while _next_sorted_index < _sorted_indices.size():
		var beat_index := _sorted_indices[_next_sorted_index]
		var beat := _sequence.beats[beat_index]
		var is_past_limit := (
			beat.start_seconds > start_limit + 0.00001
			if include_limit
			else beat.start_seconds >= start_limit - 0.00001
		)
		if is_past_limit:
			return
		_next_sorted_index += 1
		if _beat_states[beat_index] != BeatState.NOT_STARTED:
			continue
		_beat_states[beat_index] = BeatState.ACTIVE
		beat_started.emit(beat, beat_index)
		_start_beat(beat, beat_index, _play_generation)


func _start_beat(
	beat: CutsceneBeat,
	beat_index: int,
	generation: int
) -> void:
	if not _is_playing or generation != _play_generation:
		return
	match beat.kind:
		CutsceneBeat.Kind.MOVE:
			_start_move(beat, beat_index, generation, true)
		CutsceneBeat.Kind.PROP:
			_start_move(beat, beat_index, generation, false)
		CutsceneBeat.Kind.POSE:
			_start_pose(beat, beat_index, generation)
		CutsceneBeat.Kind.FACE:
			_start_face(beat, beat_index, generation)
		CutsceneBeat.Kind.BOUNCE:
			_start_bounce(beat, beat_index, generation)
		CutsceneBeat.Kind.WAIT:
			_schedule_delay(beat_index, beat.duration_seconds, generation)
		CutsceneBeat.Kind.DIALOGUE:
			_start_dialogue(beat, beat_index, generation)
		CutsceneBeat.Kind.STAGE_CUE:
			_start_stage_cue(beat, beat_index, generation)
		CutsceneBeat.Kind.STRIKE:
			_start_strike(beat, beat_index, generation)
		CutsceneBeat.Kind.SHOW:
			_start_visibility(beat, beat_index, generation, true)
		CutsceneBeat.Kind.HIDE:
			_start_visibility(beat, beat_index, generation, false)
		CutsceneBeat.Kind.CAMERA:
			_start_camera(beat, beat_index, generation)
		CutsceneBeat.Kind.AUDIO:
			_start_audio(beat, beat_index, generation)
		CutsceneBeat.Kind.VFX:
			_start_vfx(beat, beat_index, generation)
		_:
			_finish_beat(beat_index, generation)


func _start_move(
	beat: CutsceneBeat,
	beat_index: int,
	generation: int,
	grounded: bool
) -> void:
	var actor := _resolve_actor(beat.actor)
	if actor == null:
		push_warning("Cutscene actor '%s' is unavailable." % beat.actor)
		_finish_beat(beat_index, generation)
		return
	if beat.starts_from_authored_point:
		actor.global_position = _resolve_start_position(beat)
	var target_position := _resolve_target_position(beat)
	if not beat.pose.is_empty() and actor is CharacterPresenter:
		(actor as CharacterPresenter).play_pose(beat.pose)
	if _actor_motion_beats.has(beat.actor):
		var previous_index := int(_actor_motion_beats[beat.actor])
		var previous_tween := _beat_tweens.get(previous_index) as Tween
		if previous_tween != null and previous_tween.is_valid():
			previous_tween.kill()
		_beat_tweens.erase(previous_index)
		_finish_beat(previous_index, generation)
	_actor_motion_beats[beat.actor] = beat_index
	if beat.duration_seconds <= 0.0:
		_set_actor_facing(actor, signi(target_position.x - actor.global_position.x))
		if grounded and actor is CharacterPresenter and _floor_sampler.is_valid():
			var floor_y := float(_floor_sampler.call(target_position.x))
			if not is_nan(floor_y) and not is_inf(floor_y):
				target_position.y = floor_y
		actor.global_position = target_position
		_finish_beat(beat_index, generation)
		return
	var tween: Tween
	if (
		grounded
		and actor is CharacterPresenter
		and beat.movement_waypoints.is_empty()
	):
		tween = (actor as CharacterPresenter).move_grounded_to(
			target_position,
			beat.duration_seconds,
			_floor_sampler,
			false,
			beat.step_height
		)
	else:
		if actor is CharacterPresenter:
			(actor as CharacterPresenter).reset_speech_motion()
			(actor as CharacterPresenter).cancel_grounded_motion()
		var path := _build_move_path(
			actor.global_position,
			target_position,
			grounded,
			beat
		)
		tween = GroundWalkType.walk_along(
			actor,
			path,
			beat.duration_seconds,
			beat.step_height if grounded else 0.0
		)
	if tween == null:
		_finish_beat(beat_index, generation)
		return
	_register_tween(tween, beat_index, generation)


func _start_pose(beat: CutsceneBeat, beat_index: int, generation: int) -> void:
	var actor := _resolve_actor(beat.actor)
	if actor is CharacterPresenter:
		(actor as CharacterPresenter).play_pose(beat.pose, beat.holds_pose)
	_schedule_delay(beat_index, beat.duration_seconds, generation)


func _start_face(beat: CutsceneBeat, beat_index: int, generation: int) -> void:
	var actor := _resolve_actor(beat.actor)
	if actor != null:
		_set_actor_facing(actor, beat.facing)
	_schedule_delay(beat_index, beat.duration_seconds, generation)


func _start_bounce(beat: CutsceneBeat, beat_index: int, generation: int) -> void:
	var actor := _resolve_actor(beat.actor)
	if actor is CharacterPresenter:
		(actor as CharacterPresenter).play_cutscene_bounce(
			beat.bounce_offset,
			beat.duration_seconds,
			beat.bounce_count,
			_bounce_transition(beat.bounce_style)
		)
	_schedule_delay(beat_index, beat.duration_seconds, generation)


func _start_dialogue(
	beat: CutsceneBeat,
	beat_index: int,
	generation: int
) -> void:
	dialogue_requested.emit(beat.conversation, beat.line_range)
	if beat.blocks:
		_waiting_dialogue_index = beat_index
		return
	_schedule_delay(beat_index, beat.duration_seconds, generation)


func _start_stage_cue(
	beat: CutsceneBeat,
	beat_index: int,
	generation: int
) -> void:
	if is_instance_valid(_stage) and _stage.play_cue(beat.cue, -1):
		_waiting_stage_cue_index = beat_index
		return
	_schedule_delay(beat_index, beat.duration_seconds, generation)


func _start_strike(
	beat: CutsceneBeat,
	beat_index: int,
	generation: int
) -> void:
	if is_instance_valid(_stage):
		_stage.request_presentation_strike(beat.cue)
	_schedule_delay(beat_index, beat.duration_seconds, generation)


func _start_visibility(
	beat: CutsceneBeat,
	beat_index: int,
	generation: int,
	visible: bool
) -> void:
	var actor := _resolve_actor(beat.actor)
	if actor != null:
		actor.visible = visible
	_schedule_delay(beat_index, beat.duration_seconds, generation)


func _start_camera(
	beat: CutsceneBeat,
	beat_index: int,
	generation: int
) -> void:
	camera_action_requested.emit(
		beat.camera_action,
		beat.camera_offset,
		beat.camera_zoom,
		beat.camera_shake_strength,
		beat.duration_seconds
	)
	_schedule_delay(beat_index, beat.duration_seconds, generation)


func _start_audio(
	beat: CutsceneBeat,
	beat_index: int,
	generation: int
) -> void:
	audio_action_requested.emit(
		beat.audio_action,
		beat.audio_stream,
		beat.audio_bus,
		beat.audio_volume_db,
		beat.audio_pitch_scale,
		beat.audio_fade_seconds
	)
	_schedule_delay(beat_index, beat.duration_seconds, generation)


func _start_vfx(
	beat: CutsceneBeat,
	beat_index: int,
	generation: int
) -> void:
	vfx_action_requested.emit(
		beat.vfx_action,
		beat.vfx_id,
		beat.vfx_scene,
		_resolve_vfx_position(beat),
		beat.duration_seconds
	)
	_schedule_delay(beat_index, beat.duration_seconds, generation)


func _schedule_delay(
	beat_index: int,
	duration: float,
	generation: int
) -> void:
	if duration <= 0.0:
		_finish_beat(beat_index, generation)
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(duration)
	_register_tween(tween, beat_index, generation)


func _register_tween(tween: Tween, beat_index: int, generation: int) -> void:
	_beat_tweens[beat_index] = tween
	tween.finished.connect(
		_on_beat_tween_finished.bind(beat_index, generation),
		CONNECT_ONE_SHOT
	)


func _on_beat_tween_finished(beat_index: int, generation: int) -> void:
	_beat_tweens.erase(beat_index)
	_finish_beat(beat_index, generation)
	_check_for_completion()


func _on_stage_cue_finished(cue_id: StringName) -> void:
	if (
		not _is_playing
		or _waiting_stage_cue_index < 0
		or _sequence == null
	):
		return
	var beat_index := _waiting_stage_cue_index
	var beat := _sequence.beats[beat_index]
	if beat.cue != cue_id:
		return
	_waiting_stage_cue_index = -1
	_finish_beat(beat_index, _play_generation)
	_check_for_completion()


func _finish_beat(beat_index: int, generation: int) -> void:
	if (
		not _is_playing
		or generation != _play_generation
		or beat_index < 0
		or beat_index >= _beat_states.size()
		or _beat_states[beat_index] != BeatState.ACTIVE
	):
		return
	_beat_states[beat_index] = BeatState.FINISHED
	if _held_beat_index == beat_index:
		_held_beat_index = -1
	if _waiting_dialogue_index == beat_index:
		_waiting_dialogue_index = -1
	if _waiting_stage_cue_index == beat_index:
		_waiting_stage_cue_index = -1
	if _actor_motion_beats.values().has(beat_index):
		_actor_motion_beats.erase(
			_actor_motion_beats.find_key(beat_index)
		)
	beat_finished.emit(_sequence.beats[beat_index], beat_index)


func _check_for_completion() -> void:
	if not _is_playing or _sequence == null:
		return
	if _timeline_seconds < _sequence.get_duration_seconds() - 0.00001:
		return
	if _held_beat_index >= 0:
		return
	for state in _beat_states:
		if state != BeatState.FINISHED:
			return
	_is_playing = false
	set_process(false)
	var completed_generation := _play_generation
	_finished_for_generation(completed_generation)


func _finished_for_generation(generation: int) -> void:
	if generation == _play_generation:
		finished.emit()


func _find_blocking_end(current_time: float) -> Dictionary:
	var result := {"index": -1, "end": INF}
	if _sequence == null:
		return result
	for beat_index in _sorted_indices:
		var beat := _sequence.beats[beat_index]
		if (
			not beat.blocks
			or _beat_states[beat_index] == BeatState.FINISHED
			or beat.start_seconds > current_time + 0.00001
			or beat.get_end_seconds() > current_time + 0.00001
		):
			continue
		if beat.get_end_seconds() < float(result["end"]):
			result["index"] = beat_index
			result["end"] = beat.get_end_seconds()
	return result


func _get_sorted_indices(sequence: CutsceneSequence) -> Array[int]:
	var indices: Array[int] = []
	for beat_index in range(sequence.beats.size()):
		if sequence.beats[beat_index] == null:
			continue
		var insertion_index := indices.size()
		for candidate_index in range(indices.size()):
			var candidate_beat := sequence.beats[indices[candidate_index]]
			if candidate_beat.start_seconds > sequence.beats[beat_index].start_seconds:
				insertion_index = candidate_index
				break
		indices.insert(insertion_index, beat_index)
	return indices


func _capture_evaluation_initial_states(sequence: CutsceneSequence) -> void:
	_evaluation_initial_states.clear()
	for actor_id_text in sequence.get_actor_ids():
		var actor_id := StringName(actor_id_text)
		var actor := _resolve_actor(actor_id)
		_evaluation_initial_states[actor_id] = _get_actor_state(actor)


func _evaluate_actor_at(
	sequence: CutsceneSequence,
	actor_id: StringName,
	seconds: float
) -> Dictionary:
	var state: Dictionary
	if _sequence == sequence and _evaluation_initial_states.has(actor_id):
		state = (_evaluation_initial_states[actor_id] as Dictionary).duplicate()
	else:
		state = _get_actor_state(_resolve_actor(actor_id))
	var active_move: Dictionary = {}
	var persistent_pose: StringName = state.get(&"pose", StringName())
	var active_move_pose: StringName
	var active_move_pose_start: float = -INF
	var visual_offset := Vector2.ZERO
	var visual_offset_start := -INF
	for beat in sequence.get_beats_sorted():
		if beat.actor != actor_id or beat.start_seconds > seconds + 0.00001:
			continue
		if not active_move.is_empty():
			state[&"position"] = _position_for_move(
				active_move,
				beat.start_seconds
			)
			if beat.start_seconds >= float(active_move["end"]):
				active_move.clear()
		match beat.kind:
			CutsceneBeat.Kind.MOVE, CutsceneBeat.Kind.PROP:
				# An authored start overrides where the actor was left, which is
				# what lets a walk be staged on its own instead of inheriting
				# whatever the beat before it happened to end on.
				var start_position: Vector2 = (
					_resolve_start_position(beat)
					if beat.starts_from_authored_point
					else state[&"position"]
				)
				var target_position := _resolve_target_position(beat)
				var is_grounded := beat.kind == CutsceneBeat.Kind.MOVE
				if is_grounded:
					var path := _build_move_path(
						start_position,
						target_position,
						true,
						beat
					)
					active_move = {
						"start": start_position,
						"target": target_position,
						"start_seconds": beat.start_seconds,
						"end": beat.get_end_seconds(),
						"duration": beat.duration_seconds,
						"path": path,
						"grounded": true,
						"step_height": beat.step_height,
					}
				else:
					var prop_path := _build_move_path(
						start_position,
						target_position,
						false,
						beat
					)
					active_move = {
						"start": start_position,
						"target": target_position,
						"start_seconds": beat.start_seconds,
						"end": beat.get_end_seconds(),
						"duration": beat.duration_seconds,
						"path": prop_path,
						"grounded": false,
					}
				if (
					beat.kind == CutsceneBeat.Kind.MOVE
					and not beat.pose.is_empty()
					and _beat_is_active_at(beat, seconds)
					and beat.start_seconds >= active_move_pose_start
				):
					active_move_pose = beat.pose
					active_move_pose_start = beat.start_seconds
				_set_state_facing_for_move(state, start_position, target_position)
			CutsceneBeat.Kind.POSE:
				persistent_pose = beat.pose
			CutsceneBeat.Kind.FACE:
				state[&"facing"] = beat.facing
			CutsceneBeat.Kind.BOUNCE:
				if (
					_beat_is_active_at(beat, seconds)
					and beat.start_seconds >= visual_offset_start
				):
					visual_offset = _bounce_offset_at(beat, seconds)
					visual_offset_start = beat.start_seconds
			CutsceneBeat.Kind.SHOW:
				state[&"visible"] = true
			CutsceneBeat.Kind.HIDE:
				state[&"visible"] = false
			_:
				pass
	if not active_move.is_empty():
		state[&"position"] = _position_for_move(active_move, seconds)
		_set_state_facing_for_move(
			state,
			active_move.get("start", state[&"position"]),
			active_move.get("target", state[&"position"])
		)
	state[&"pose"] = (
			active_move_pose
			if not active_move_pose.is_empty()
			else persistent_pose
		)
	state[&"visual_offset"] = visual_offset
	return state


func _evaluate_stage_cue_at(
	sequence: CutsceneSequence,
	seconds: float
) -> StringName:
	var active_cue: StringName
	var active_start: float = -INF
	for beat in sequence.get_beats_sorted():
		if (
			beat.kind == CutsceneBeat.Kind.STAGE_CUE
			and _beat_is_active_at(beat, seconds)
			and beat.start_seconds >= active_start
		):
			active_cue = beat.cue
			active_start = beat.start_seconds
	return active_cue


func _beat_is_active_at(beat: CutsceneBeat, seconds: float) -> bool:
	if beat.start_seconds > seconds + 0.00001:
		return false
	if beat.duration_seconds <= 0.0:
		return is_equal_approx(seconds, beat.start_seconds)
	return seconds <= beat.get_end_seconds() + 0.00001


func _position_for_move(move: Dictionary, seconds: float) -> Vector2:
	var duration: float = move["duration"]
	var progress := (
		1.0
		if duration <= 0.0
		else clampf(
			(seconds - float(move["start_seconds"])) / duration,
			0.0,
			1.0
		)
	)
	if bool(move["grounded"]):
		return GroundWalkType.position_along_path(
			move["path"],
			progress,
			float(move["step_height"])
		)
	var path: PackedVector2Array = move.get(
		"path",
		PackedVector2Array([move["start"], move["target"]])
	)
	return GroundWalkType.position_along_path(path, progress, 0.0)


## Builds one distance-weighted route through every authored intermediate point.
##
## Path storage is bounded by waypoint count plus the terrain samples already
## bounded by GroundWalk's stride. It is created once per runtime move or scrub
## query and released with that operation; no per-frame accumulation occurs.
func _build_move_path(
	start_position: Vector2,
	target_position: Vector2,
	grounded: bool,
	beat: CutsceneBeat
) -> PackedVector2Array:
	var authored_points := PackedVector2Array([start_position])
	for waypoint in beat.movement_waypoints:
		authored_points.append(_resolve_stage_position(waypoint))
	authored_points.append(target_position)

	var route := PackedVector2Array()
	for point_index in range(1, authored_points.size()):
		var segment: PackedVector2Array
		if grounded:
			segment = GroundWalkType.build_path(
				authored_points[point_index - 1],
				authored_points[point_index],
				_floor_sampler,
				GroundWalkType.DEFAULT_STRIDE_PIXELS
			)
		else:
			segment = PackedVector2Array([
				authored_points[point_index - 1],
				authored_points[point_index],
			])
		for segment_point in segment:
			if route.is_empty() or not route[-1].is_equal_approx(segment_point):
				route.append(segment_point)
	if route.is_empty():
		route.append(target_position)
	return route


## Returns the visual displacement for one bounce at an arbitrary scrub time.
##
## Tween.interpolate_value is the same response function runtime Tweeners use,
## so the editor does not approximate gentle or snappy motion differently.
func _bounce_offset_at(beat: CutsceneBeat, seconds: float) -> Vector2:
	if beat.duration_seconds <= 0.0 or beat.bounce_count <= 0:
		return Vector2.ZERO
	var progress := clampf(
		(seconds - beat.start_seconds) / beat.duration_seconds,
		0.0,
		1.0
	)
	if progress >= 1.0:
		return Vector2.ZERO
	var cycle_progress := fposmod(
		progress * float(beat.bounce_count),
		1.0
	)
	var is_outbound := cycle_progress <= 0.5
	var half_progress := (
		cycle_progress * 2.0
		if is_outbound
		else (cycle_progress - 0.5) * 2.0
	)
	var response := float(Tween.interpolate_value(
		0.0 if is_outbound else 1.0,
		1.0 if is_outbound else -1.0,
		half_progress,
		1.0,
		_bounce_transition(beat.bounce_style),
		Tween.EASE_OUT if is_outbound else Tween.EASE_IN
	))
	return beat.bounce_offset * response


## Maps the authored style to the tween response used during real playback.
func _bounce_transition(style: int) -> Tween.TransitionType:
	match style:
		CutsceneBeat.BounceStyle.GENTLE:
			return Tween.TRANS_SINE
		CutsceneBeat.BounceStyle.SNAPPY:
			return Tween.TRANS_EXPO
		_:
			return Tween.TRANS_LINEAR


func _evaluate_dialogue_at(
	sequence: CutsceneSequence,
	seconds: float
) -> Variant:
	var selected: CutsceneBeat
	for beat in sequence.get_beats_sorted():
		if beat.kind != CutsceneBeat.Kind.DIALOGUE:
			continue
		var is_in_window := (
			seconds >= beat.start_seconds
			and (
				beat.duration_seconds <= 0.0
				or seconds <= beat.get_end_seconds()
			)
		)
		if is_in_window and (selected == null or beat.start_seconds >= selected.start_seconds):
			selected = beat
	if selected == null or selected.conversation == null:
		return null
	var line_index := 0
	if selected.line_range != Vector2i(-1, -1):
		line_index = selected.line_range.x
	var line: DialogueLine
	if line_index >= 0 and line_index < selected.conversation.lines.size():
		line = selected.conversation.lines[line_index]
	return {
		&"conversation": selected.conversation,
		&"line_range": selected.line_range,
		&"line_index": line_index,
		&"line": line,
	}


## Returns the frame target and a deterministic shake sample for editor scrubbing.
func _evaluate_camera_at(
	sequence: CutsceneSequence,
	seconds: float
) -> Dictionary:
	var state := _default_camera_state()
	for beat in sequence.get_beats_sorted():
		if (
			beat.kind != CutsceneBeat.Kind.CAMERA
			or beat.start_seconds > seconds + 0.00001
		):
			continue
		match beat.camera_action:
			CutsceneBeat.CameraAction.FRAME:
				var start_offset: Vector2 = state[&"offset"]
				var start_zoom: Vector2 = state[&"zoom"]
				var progress := _beat_progress_at(beat, seconds)
				var response := float(Tween.interpolate_value(
					0.0,
					1.0,
					progress,
					1.0,
					Tween.TRANS_SINE,
					Tween.EASE_IN_OUT
				))
				state[&"action"] = beat.camera_action
				state[&"offset"] = start_offset.lerp(
					beat.camera_offset,
					response
				)
				state[&"zoom"] = start_zoom.lerp(
					beat.camera_zoom,
					response
				)
				state[&"active"] = _beat_is_active_at(beat, seconds)
				state[&"progress"] = progress
			CutsceneBeat.CameraAction.SHAKE:
				if _beat_is_active_at(beat, seconds):
					var elapsed := maxf(
						seconds - beat.start_seconds,
						0.0
					)
					var strength := beat.camera_shake_strength
					state[&"action"] = beat.camera_action
					state[&"shake_strength"] = strength
					state[&"shake_offset"] = Vector2(
						sin(elapsed * 37.0),
						cos(elapsed * 53.0)
					) * strength
					state[&"active"] = true
					state[&"progress"] = _beat_progress_at(beat, seconds)
			CutsceneBeat.CameraAction.RESET:
				state = _default_camera_state()
				state[&"action"] = beat.camera_action
	return state


## Returns persistent music state plus one-shots whose authored windows are active.
func _evaluate_audio_at(
	sequence: CutsceneSequence,
	seconds: float
) -> Dictionary:
	var state := _default_audio_state()
	var active_sfx: Array[Dictionary] = []
	for beat in sequence.get_beats_sorted():
		if (
			beat.kind != CutsceneBeat.Kind.AUDIO
			or beat.start_seconds > seconds + 0.00001
		):
			continue
		var event := {
			&"action": beat.audio_action,
			&"stream": beat.audio_stream,
			&"bus": beat.audio_bus,
			&"volume_db": beat.audio_volume_db,
			&"pitch_scale": beat.audio_pitch_scale,
			&"fade_seconds": beat.audio_fade_seconds,
			&"start_seconds": beat.start_seconds,
		}
		match beat.audio_action:
			CutsceneBeat.AudioAction.PLAY_SFX:
				if _beat_is_active_at(beat, seconds):
					active_sfx.append(event)
			CutsceneBeat.AudioAction.PLAY_MUSIC:
				state[&"music"] = event
			CutsceneBeat.AudioAction.STOP_MUSIC:
				state[&"music"] = null
	state[&"sfx"] = active_sfx
	return state


## Returns effect instances that should exist at an arbitrary scrub time.
func _evaluate_vfx_at(
	sequence: CutsceneSequence,
	seconds: float
) -> Dictionary:
	var active_effects: Dictionary = {}
	for beat in sequence.get_beats_sorted():
		if (
			beat.kind != CutsceneBeat.Kind.VFX
			or beat.start_seconds > seconds + 0.00001
		):
			continue
		if beat.vfx_action == CutsceneBeat.VfxAction.STOP:
			active_effects.erase(beat.vfx_id)
			continue
		if (
			beat.duration_seconds > 0.0
			and seconds > beat.get_end_seconds() + 0.00001
		):
			active_effects.erase(beat.vfx_id)
			continue
		active_effects[beat.vfx_id] = {
			&"action": beat.vfx_action,
			&"id": beat.vfx_id,
			&"scene": beat.vfx_scene,
			&"position": _resolve_vfx_position(beat),
			&"start_seconds": beat.start_seconds,
			&"duration_seconds": beat.duration_seconds,
		}
	return active_effects


func _default_camera_state() -> Dictionary:
	return {
		&"action": CutsceneBeat.CameraAction.RESET,
		&"offset": Vector2.ZERO,
		&"zoom": Vector2.ONE,
		&"shake_strength": 0.0,
		&"shake_offset": Vector2.ZERO,
		&"active": false,
		&"progress": 1.0,
	}


func _default_audio_state() -> Dictionary:
	return {
		&"music": null,
		&"sfx": Array([], TYPE_DICTIONARY, &"", null),
	}


func _beat_progress_at(beat: CutsceneBeat, seconds: float) -> float:
	if beat.duration_seconds <= 0.0:
		return 1.0
	return clampf(
		(seconds - beat.start_seconds) / beat.duration_seconds,
		0.0,
		1.0
	)


func _resolve_actor(actor_id: StringName) -> Node2D:
	if not _actor_resolver.is_valid():
		return null
	var resolved: Variant = _actor_resolver.call(actor_id)
	if not is_instance_valid(resolved):
		return null
	return resolved as Node2D


## Resolves the authored point a MOVE starts from, the same way its target is
## resolved: a marker plus an offset, falling back to a stage-local position
## when no marker is named.
func _resolve_start_position(beat: CutsceneBeat) -> Vector2:
	if not beat.start_marker.is_empty() and _marker_resolver.is_valid():
		var resolved: Variant = _marker_resolver.call(beat.start_marker)
		if resolved is Vector2:
			var marker_position := resolved as Vector2
			if not is_nan(marker_position.x) and not is_nan(marker_position.y):
				return marker_position + beat.start_offset
	if is_instance_valid(_stage):
		return _stage.to_global(beat.start_offset)
	return beat.start_offset


func _resolve_target_position(beat: CutsceneBeat) -> Vector2:
	if not beat.target_marker.is_empty() and _marker_resolver.is_valid():
		var resolved: Variant = _marker_resolver.call(beat.target_marker)
		if resolved is Vector2:
			var marker_position := resolved as Vector2
			if not is_nan(marker_position.x) and not is_nan(marker_position.y):
				return marker_position + beat.target_offset
	if is_instance_valid(_stage):
		return _stage.to_global(beat.target_offset)
	return beat.target_offset


func _resolve_stage_position(local_position: Vector2) -> Vector2:
	if is_instance_valid(_stage):
		return _stage.to_global(local_position)
	return local_position


func _resolve_vfx_position(beat: CutsceneBeat) -> Vector2:
	if not beat.target_marker.is_empty():
		return _resolve_target_position(beat)
	if not beat.actor.is_empty():
		var actor := _resolve_actor(beat.actor)
		if actor != null:
			return actor.global_position + beat.target_offset
	return _resolve_stage_position(beat.target_offset)


func _get_actor_state(actor: Node2D) -> Dictionary:
	if actor == null:
		return {
			&"position": Vector2.ZERO,
			&"facing": 1,
			&"pose": &"",
			&"stage_cue": &"",
			&"visible": false,
		}
	return {
		&"position": actor.global_position,
		&"facing": _get_actor_facing(actor),
		&"pose": &"",
		&"stage_cue": &"",
		&"visible": actor.visible,
	}


func _get_actor_facing(actor: Node2D) -> int:
	if actor is CharacterPresenter:
		return -1 if (actor as CharacterPresenter).character_sprite.flip_h else 1
	return -1 if actor.scale.x < 0.0 else 1


func _set_actor_facing(actor: Node2D, direction: int) -> void:
	if direction == 0:
		return
	if actor.has_method(&"set_facing_direction"):
		actor.call(&"set_facing_direction", direction)
		return
	actor.scale.x = absf(actor.scale.x) * float(direction)


func _set_state_facing_for_move(
	state: Dictionary,
	start_position: Vector2,
	target_position: Vector2
) -> void:
	var direction := signi(roundi(target_position.x - start_position.x))
	if direction != 0:
		state[&"facing"] = direction
