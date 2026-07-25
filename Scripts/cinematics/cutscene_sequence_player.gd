@tool
class_name CutsceneSequencePlayer
extends Node

## How it works:
## - An injected resolver supplies actors, global markers, terrain, and stage.
## - The authored clock starts eligible beats together and holds at blocking ends.
## - Presenter moves use sampled GroundWalk paths; props use plain position tweening.
## - Dialogue is only requested; the owner completes it with notify_dialogue_finished().
## - evaluate_at simulates the same cached path position math without mutations.
## - stop kills owned motion and invalidates every stale callback by generation.
## - The invariant is that a stopped or superseded sequence can emit nothing later.

signal beat_started(beat: CutsceneBeat, index: int)
signal beat_finished(beat: CutsceneBeat, index: int)
signal dialogue_requested(
	conversation: DialogueConversation,
	line_range: Vector2i
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
	if is_instance_valid(_stage):
		if _stage.cue_finished.is_connected(_on_stage_cue_finished):
			_stage.cue_finished.disconnect(_on_stage_cue_finished)
	_actor_resolver = actor_resolver
	_marker_resolver = marker_resolver
	_floor_sampler = floor_sampler
	_stage = stage
	if is_instance_valid(_stage) and not _stage.cue_finished.is_connected(
		_on_stage_cue_finished
	):
		_stage.cue_finished.connect(_on_stage_cue_finished)


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
## Result contains direct actor-id keys, an `actors` mirror, and `dialogue` data.
func evaluate_at(
	sequence: CutsceneSequence,
	seconds: float
) -> Dictionary:
	var result: Dictionary = {}
	if sequence == null:
		result[&"actors"] = {}
		result[&"dialogue"] = null
		return result
	var actor_states: Dictionary = {}
	var evaluation_seconds := maxf(seconds, 0.0)
	for actor_id_text in sequence.get_actor_ids():
		var actor_id := StringName(actor_id_text)
		var state := _evaluate_actor_at(
			sequence,
			actor_id,
			evaluation_seconds
		)
		actor_states[actor_id] = state
		result[actor_id] = state
	result[&"actors"] = actor_states
	result[&"dialogue"] = _evaluate_dialogue_at(
		sequence,
		evaluation_seconds
	)
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
		actor.global_position = target_position
		_finish_beat(beat_index, generation)
		return
	var tween: Tween
	if grounded and actor is CharacterPresenter:
		tween = (actor as CharacterPresenter).move_grounded_to(
			target_position,
			beat.duration_seconds,
			_floor_sampler,
			false,
			beat.step_height
		)
	else:
		_set_actor_facing(actor, signi(target_position.x - actor.global_position.x))
		tween = actor.create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(
			actor,
			"global_position",
			target_position,
			maxf(beat.duration_seconds, 0.01)
		).set_trans(Tween.TRANS_LINEAR)
	if tween == null:
		_finish_beat(beat_index, generation)
		return
	_register_tween(tween, beat_index, generation)


func _start_pose(beat: CutsceneBeat, beat_index: int, generation: int) -> void:
	var actor := _resolve_actor(beat.actor)
	if actor is CharacterPresenter:
		(actor as CharacterPresenter).play_pose(beat.pose)
	_schedule_delay(beat_index, beat.duration_seconds, generation)


func _start_face(beat: CutsceneBeat, beat_index: int, generation: int) -> void:
	var actor := _resolve_actor(beat.actor)
	if actor != null:
		_set_actor_facing(actor, beat.facing)
	_schedule_delay(beat_index, beat.duration_seconds, generation)


func _start_bounce(beat: CutsceneBeat, beat_index: int, generation: int) -> void:
	var actor := _resolve_actor(beat.actor)
	if actor is CharacterPresenter:
		(actor as CharacterPresenter).react_to_presented_line()
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
				var start_position: Vector2 = state[&"position"]
				var target_position := _resolve_target_position(beat)
				var is_grounded := beat.kind == CutsceneBeat.Kind.MOVE
				if is_grounded:
					var path := GroundWalkType.build_path(
						start_position,
						target_position,
						_floor_sampler,
						GroundWalkType.DEFAULT_STRIDE_PIXELS
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
					active_move = {
						"start": start_position,
						"target": target_position,
						"start_seconds": beat.start_seconds,
						"end": beat.get_end_seconds(),
						"duration": beat.duration_seconds,
						"grounded": false,
					}
				if not beat.pose.is_empty():
					state[&"pose"] = beat.pose
				_set_state_facing_for_move(state, start_position, target_position)
			CutsceneBeat.Kind.POSE:
				state[&"pose"] = beat.pose
			CutsceneBeat.Kind.FACE:
				state[&"facing"] = beat.facing
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
	return state


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
	return (move["start"] as Vector2).lerp(move["target"], progress)


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


func _resolve_actor(actor_id: StringName) -> Node2D:
	if not _actor_resolver.is_valid():
		return null
	var resolved: Variant = _actor_resolver.call(actor_id)
	if not is_instance_valid(resolved):
		return null
	return resolved as Node2D


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


func _get_actor_state(actor: Node2D) -> Dictionary:
	if actor == null:
		return {
			&"position": Vector2.ZERO,
			&"facing": 1,
			&"pose": &"",
			&"visible": false,
		}
	return {
		&"position": actor.global_position,
		&"facing": _get_actor_facing(actor),
		&"pose": &"",
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
