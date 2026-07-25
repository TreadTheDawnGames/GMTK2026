class_name ActorSpriteView
extends Node

## How it works:
## - A caller requests a named pose without knowing sprite-sheet layout.
## - A valid pose atomically assigns the texture, grid, and first frame.
## - Multi-frame poses advance in _process; still poses do no per-frame work.
## - Missing or invalid poses leave every Sprite2D property untouched.
## - The invariant is that animation never advances outside the pose's range.

@export var actor_sprite: Sprite2D
@export var pose_set: ActorPoseSet

var _active_pose: ActorPose
var _elapsed_seconds: float = 0.0


## Starts a named pose, returning false without visible mutation if unavailable.
func play_pose(pose_name: StringName) -> bool:
	if not is_instance_valid(actor_sprite) or pose_set == null:
		return false
	var pose := pose_set.get_pose(pose_name)
	if pose == null:
		return false

	_active_pose = pose
	_elapsed_seconds = 0.0
	actor_sprite.texture = pose.texture
	actor_sprite.hframes = pose.horizontal_frames
	actor_sprite.vframes = pose.vertical_frames
	actor_sprite.frame = pose.first_frame
	set_process(
		pose.frame_count > 1
		and pose.frames_per_second > 0.0
	)
	return true


## Reports whether the assigned set contains a playable named pose.
func has_pose(pose_name: StringName) -> bool:
	return (
		is_instance_valid(actor_sprite)
		and pose_set != null
		and pose_set.has_pose(pose_name)
	)


## Advances within the active pose's authored frame range.
func _process(delta: float) -> void:
	if _active_pose == null:
		set_process(false)
		return
	_elapsed_seconds += delta
	var elapsed_frames := int(
		floor(_elapsed_seconds * _active_pose.frames_per_second)
	)
	var frame_offset := elapsed_frames
	if _active_pose.loops:
		frame_offset %= _active_pose.frame_count
	else:
		frame_offset = mini(frame_offset, _active_pose.frame_count - 1)
		if frame_offset == _active_pose.frame_count - 1:
			set_process(false)
	actor_sprite.frame = _active_pose.first_frame + frame_offset
