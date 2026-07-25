class_name ActorPoseSet
extends Resource

## How it works:
## - Artists author a small list of named ActorPose entries per actor.
## - Consumers resolve poses by StringName and never mutate the authored list.
## - Missing, duplicate, or invalid entries fail safely at lookup time.
## - The invariant is that the first playable entry for a name wins.

@export var poses: Array[ActorPose] = []


## Returns the first playable pose with this name, or null when none exists.
func get_pose(pose_name: StringName) -> ActorPose:
	if pose_name.is_empty():
		return null
	for pose in poses:
		if (
			pose != null
			and pose.pose_name == pose_name
			and pose.is_playable()
		):
			return pose
	return null


## Reports whether this set can safely present the requested pose.
func has_pose(pose_name: StringName) -> bool:
	return get_pose(pose_name) != null
