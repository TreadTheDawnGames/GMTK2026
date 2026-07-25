@tool
class_name CutsceneBeat
extends Resource

## How it works:
## - One resource stores every timeline kind so the Inspector stays uniform.
## - Actor, marker, pose, cue, and dialogue fields are interpreted by `kind`.
## - `start_seconds` is authored time; equal starts are intentionally parallel.
## - `blocks` can hold the sequence clock at this beat's nominal end.
## - Validation reports authoring mistakes without changing the resource.
## - The invariant is that a beat's end is never earlier than its start.

enum Kind {
	MOVE,
	POSE,
	FACE,
	BOUNCE,
	WAIT,
	DIALOGUE,
	STAGE_CUE,
	PROP,
	STRIKE,
	SHOW,
	HIDE,
}

## The operation this timeline entry performs at its authored start time.
@export var kind: Kind = Kind.WAIT
## The cast or prop id driven by this beat; empty is valid for stage-only beats.
@export var actor: StringName
## The authored sequence time at which this beat becomes eligible to start.
@export var start_seconds: float = 0.0
## How long the beat takes; blocking beats may hold beyond this nominal end.
@export var duration_seconds: float = 0.0
## A direct child name under ActorMarkers or PropMarkers used as the target.
@export var target_marker: StringName
## An offset from the marker, or a stage-local position when no marker is set.
@export var target_offset: Vector2 = Vector2.ZERO
## Pose used by POSE and held as the movement pose during MOVE.
@export var pose: StringName
## AnimationPlayer clip for STAGE_CUE, or ActionMarkers child for STRIKE.
@export var cue: StringName
## Conversation requested from the owner for DIALOGUE; the player never opens it.
@export var conversation: DialogueConversation
## Inclusive dialogue line range; (-1, -1) means the whole conversation.
@export var line_range: Vector2i = Vector2i(-1, -1)
## Whether sequence time must wait for this beat to genuinely finish.
@export var blocks: bool = true
## Visual lift in pixels for MOVE beats following sampled terrain.
@export var step_height: float = 4.0
## Facing direction for FACE: -1 is left and 1 is right.
@export var facing: int = 0
## Number of presentation bounces requested by BOUNCE.
@export var bounce_count: int = 1
## An authoring note for the editor; playback never presents it to players.
@export_multiline var notes: String


## Returns the nominal end on the authored timeline.
func get_end_seconds() -> float:
	return start_seconds + maxf(duration_seconds, 0.0)


## Reports human-readable authoring errors for this one timeline entry.
func validate(known_actors: PackedStringArray) -> PackedStringArray:
	var errors := PackedStringArray()
	if start_seconds < 0.0:
		errors.append("start_seconds must not be negative.")
	if duration_seconds < 0.0:
		errors.append("duration_seconds must not be negative.")
	if step_height < 0.0:
		errors.append("step_height must not be negative.")
	if actor.is_empty() and _kind_requires_actor():
		errors.append("%s beat requires an actor." % _kind_name())
	if not actor.is_empty() and not _actor_is_known(known_actors):
		errors.append("Unknown actor id '%s'." % actor)
	if not actor.is_empty() and _kind_forbids_actor():
		errors.append("%s beat must not have an actor." % _kind_name())

	match kind:
		Kind.MOVE:
			if target_marker.is_empty() and target_offset.is_zero_approx():
				errors.append("MOVE beat needs a target marker or non-zero offset.")
		Kind.PROP:
			if target_marker.is_empty() and target_offset.is_zero_approx():
				errors.append("PROP beat needs a target marker or non-zero offset.")
		Kind.POSE:
			if pose.is_empty():
				errors.append("POSE beat needs a pose name.")
		Kind.FACE:
			if facing != -1 and facing != 1:
				errors.append("FACE beat facing must be -1 or 1.")
		Kind.BOUNCE:
			if bounce_count <= 0:
				errors.append("BOUNCE beat bounce_count must be positive.")
		Kind.DIALOGUE:
			if conversation == null:
				errors.append("DIALOGUE beat needs a conversation.")
			else:
				errors.append_array(_validate_line_range())
		Kind.STAGE_CUE, Kind.STRIKE:
			if cue.is_empty():
				errors.append("%s beat needs a cue name." % _kind_name())
		Kind.WAIT, Kind.SHOW, Kind.HIDE:
			pass

	return errors


func _kind_requires_actor() -> bool:
	return kind in [
		Kind.MOVE,
		Kind.POSE,
		Kind.FACE,
		Kind.BOUNCE,
		Kind.PROP,
		Kind.SHOW,
		Kind.HIDE,
	]


func _kind_forbids_actor() -> bool:
	return kind in [Kind.WAIT, Kind.DIALOGUE, Kind.STAGE_CUE, Kind.STRIKE]


func _actor_is_known(known_actors: PackedStringArray) -> bool:
	return actor == &"miner" or known_actors.has(str(actor))


func _kind_name() -> String:
	return Kind.keys()[kind] if kind >= 0 and kind < Kind.size() else "UNKNOWN"


func _validate_line_range() -> PackedStringArray:
	var errors := PackedStringArray()
	var whole_conversation := line_range == Vector2i(-1, -1)
	if whole_conversation:
		return errors
	if line_range.x < 0 or line_range.y < 0:
		errors.append("DIALOGUE line_range must be (-1, -1) or non-negative.")
		return errors
	if line_range.x > line_range.y:
		errors.append("DIALOGUE line_range must be inclusive and ordered.")
		return errors
	if line_range.y >= conversation.lines.size():
		errors.append("DIALOGUE line_range ends past the conversation lines.")
	return errors
