@tool
class_name CutsceneSequence
extends Resource

## How it works:
## - Stores one Inspector-authored timeline and leaves beat array order intact.
## - Playback asks for a stable time-sorted copy when it needs scheduling.
## - Actor ids are collected in first-appearance order for editor lanes.
## - Validation delegates beat-specific checks and adds sequence-level errors.
## - The invariant is that authored ordering is never mutated by a query.

## Stable identifier used by tools, logs, and encounter authoring.
@export var sequence_id: StringName
## The authored timeline entries; equal start times are allowed to overlap.
@export var beats: Array[CutsceneBeat] = []


## Returns the largest nominal beat end, or zero for an empty sequence.
func get_duration_seconds() -> float:
	var duration := 0.0
	for beat in beats:
		if beat != null:
			duration = maxf(duration, beat.get_end_seconds())
	return duration


## Returns a stable time-sorted copy without changing the authored array.
func get_beats_sorted() -> Array[CutsceneBeat]:
	var sorted_beats: Array[CutsceneBeat] = []
	for beat in beats:
		if beat == null:
			continue
		var insertion_index := sorted_beats.size()
		for candidate_index in range(sorted_beats.size()):
			if beat.start_seconds < sorted_beats[candidate_index].start_seconds:
				insertion_index = candidate_index
				break
		sorted_beats.insert(insertion_index, beat)
	return sorted_beats


## Returns distinct actor ids in authored first-appearance order.
func get_actor_ids() -> PackedStringArray:
	var actor_ids := PackedStringArray()
	for beat in beats:
		if beat == null or beat.actor.is_empty():
			continue
		if not actor_ids.has(str(beat.actor)):
			actor_ids.append(str(beat.actor))
	return actor_ids


## Reports sequence and beat authoring errors without mutating any resource.
func validate(known_actors: PackedStringArray) -> PackedStringArray:
	var errors := PackedStringArray()
	if sequence_id.is_empty():
		errors.append("Cutscene sequence ID is required.")
	for beat_index in range(beats.size()):
		var beat := beats[beat_index]
		if beat == null:
			errors.append("Beat %d is empty." % (beat_index + 1))
			continue
		for beat_error in beat.validate(known_actors):
			errors.append("Beat %d: %s" % [beat_index + 1, beat_error])
	return errors
