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
	CAMERA,
	AUDIO,
	VFX,
}

## The response curve used by BOUNCE. The stored value is presentation data;
## CutsceneSequencePlayer maps it to the matching runtime and scrub-preview
## motion so the editor and game cannot drift apart.
enum BounceStyle {
	GENTLE,
	SNAPPY,
	LINEAR,
}

## Typed camera requests keep framing authorable without embedding scripts.
enum CameraAction {
	FRAME,
	SHAKE,
	RESET,
}

## Typed audio requests distinguish one-shots from persistent music state.
enum AudioAction {
	PLAY_SFX,
	PLAY_MUSIC,
	STOP_MUSIC,
}

## VFX instances are addressed by id so a later beat can stop a looping effect.
enum VfxAction {
	SPAWN,
	STOP,
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
## Whether this MOVE begins from an authored point rather than from wherever the
## actor happens to be standing.
##
## Off by default, because chaining from the previous beat's end is what makes a
## sequence read as one continuous performance. Turn it on for the beat that has
## to begin somewhere exact - an entrance from off screen, or a walk re-staged
## after an edit upstream moved everything after it.
@export var starts_from_authored_point: bool = false
## A direct child name under ActorMarkers or PropMarkers used as the start.
## Ignored unless starts_from_authored_point is on.
@export var start_marker: StringName
## An offset from the start marker, or a stage-local position with no marker.
@export var start_offset: Vector2 = Vector2.ZERO
## Stage-local intermediate points traversed in order before the target.
##
## Empty preserves the original direct MOVE/PROP behavior. The whole route owns
## one duration, distributed by distance, so adding a waypoint never changes the
## authored beat's end or creates a hidden timing dependency.
@export var movement_waypoints: Array[Vector2] = []
## Pose used by POSE and held as the movement pose during MOVE.
@export var pose: StringName
## Whether a POSE beat's pose survives the spoken lines that follow it.
##
## Off by default, which is what a pose worn for one moment wants. Every presented
## dialogue line resets every presenter's speech motion and drops them back to
## idle, so an ordinary POSE beat placed before a DIALOGUE beat is undone by the
## first line the player reads.
##
## Turn it on for a pose the shot is BUILT on rather than one a beat puts on. The
## Treasure Hunter reaches the cafe holding nothing, because he gave both pickaxes
## away, and his no_pickaxe pose has to outlast eight lines of conversation - one
## of which is him saying he was tired of carrying things.
@export var holds_pose: bool = false
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
## Peak visual-only displacement for BOUNCE. Godot coordinates apply: a
## negative y bobs up, a positive y dips down, and x adds a sideways hop.
@export var bounce_offset: Vector2 = Vector2(0.0, -7.0)
## Motion response for BOUNCE without changing its authored timing.
@export var bounce_style: BounceStyle = BounceStyle.GENTLE

@export_category("Camera Action")
## Operation requested by a CAMERA beat.
@export var camera_action: CameraAction = CameraAction.FRAME
## Stage-relative framing displacement in pixels.
@export var camera_offset: Vector2 = Vector2.ZERO
## Requested camera zoom. Both axes must remain positive.
@export var camera_zoom: Vector2 = Vector2.ONE
## Peak shake displacement in pixels for CAMERA/SHAKE.
@export_range(0.0, 128.0, 0.1) var camera_shake_strength: float = 0.0

@export_category("Audio Action")
## Operation requested by an AUDIO beat.
@export var audio_action: AudioAction = AudioAction.PLAY_SFX
## Authored sound or music. STOP_MUSIC deliberately leaves this empty.
@export var audio_stream: AudioStream
## Godot audio bus used by the consumer.
@export var audio_bus: StringName = &"Master"
@export_range(-80.0, 24.0, 0.1) var audio_volume_db: float = 0.0
@export_range(0.01, 4.0, 0.01) var audio_pitch_scale: float = 1.0
## Optional music fade duration; zero means an immediate transition.
@export_range(0.0, 16.0, 0.05) var audio_fade_seconds: float = 0.0

@export_category("VFX Action")
## Operation requested by a VFX beat.
@export var vfx_action: VfxAction = VfxAction.SPAWN
## Stable id used to replace or stop a previously spawned effect.
@export var vfx_id: StringName
## Authored effect scene. STOP deliberately leaves this empty.
@export var vfx_scene: PackedScene

@export_category("Documentation")
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
	if not _vector_is_finite(target_offset):
		errors.append("target_offset must be finite.")
	if not _vector_is_finite(start_offset):
		errors.append("start_offset must be finite.")
	for waypoint_index in range(movement_waypoints.size()):
		if not _vector_is_finite(movement_waypoints[waypoint_index]):
			errors.append(
				"movement_waypoints[%d] must be finite." % waypoint_index
			)
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
			if duration_seconds <= 0.0:
				errors.append("BOUNCE beat needs a positive duration.")
			if bounce_offset.is_zero_approx():
				errors.append("BOUNCE beat needs a non-zero visual offset.")
		Kind.DIALOGUE:
			if conversation == null:
				errors.append("DIALOGUE beat needs a conversation.")
			else:
				errors.append_array(_validate_line_range())
		Kind.STAGE_CUE, Kind.STRIKE:
			if cue.is_empty():
				errors.append("%s beat needs a cue name." % _kind_name())
		Kind.CAMERA:
			if not _vector_is_finite(camera_offset):
				errors.append("CAMERA beat camera_offset must be finite.")
			if not _vector_is_finite(camera_zoom):
				errors.append("CAMERA beat camera_zoom must be finite.")
			if camera_zoom.x <= 0.0 or camera_zoom.y <= 0.0:
				errors.append("CAMERA beat camera_zoom must be positive.")
			if camera_shake_strength < 0.0:
				errors.append(
					"CAMERA beat camera_shake_strength must not be negative."
				)
			if (
				camera_action == CameraAction.SHAKE
				and camera_shake_strength <= 0.0
			):
				errors.append("CAMERA/SHAKE needs a positive strength.")
			if (
				camera_action == CameraAction.SHAKE
				and duration_seconds <= 0.0
			):
				errors.append("CAMERA/SHAKE needs a positive duration.")
		Kind.AUDIO:
			if (
				audio_action != AudioAction.STOP_MUSIC
				and audio_stream == null
			):
				errors.append("AUDIO play action needs an audio stream.")
			if audio_bus.is_empty():
				errors.append("AUDIO beat needs an audio bus.")
			if audio_pitch_scale <= 0.0:
				errors.append("AUDIO beat pitch scale must be positive.")
			if audio_fade_seconds < 0.0:
				errors.append("AUDIO beat fade must not be negative.")
		Kind.VFX:
			if vfx_id.is_empty():
				errors.append("VFX beat needs a stable effect id.")
			if vfx_action == VfxAction.SPAWN and vfx_scene == null:
				errors.append("VFX/SPAWN needs an effect scene.")
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
	return kind in [
		Kind.WAIT,
		Kind.DIALOGUE,
		Kind.STAGE_CUE,
		Kind.STRIKE,
		Kind.CAMERA,
		Kind.AUDIO,
	]


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


func _vector_is_finite(value: Vector2) -> bool:
	return (
		not is_nan(value.x)
		and not is_inf(value.x)
		and not is_nan(value.y)
		and not is_inf(value.y)
	)
