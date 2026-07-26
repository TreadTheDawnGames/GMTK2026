@tool
class_name ActorPose
extends Resource

## How it works:
## - One entry names a texture or sprite-sheet range for an actor.
## - ActorSpriteView reads the grid and advances only this bounded frame range.
## - A one-frame range is a valid still pose.
## - The invariant is that every playable frame remains inside the sheet grid.

@export var pose_name: StringName
@export var texture: Texture2D
@export_range(1, 64, 1) var horizontal_frames: int = 1
@export_range(1, 64, 1) var vertical_frames: int = 1
@export_range(0, 4_095, 1) var first_frame: int = 0
@export_range(1, 4_096, 1) var frame_count: int = 1
@export_range(0.0, 120.0, 0.1) var frames_per_second: float = 8.0
@export var loops: bool = true


## Rejects incomplete entries without changing the currently visible sprite.
func is_playable() -> bool:
	var available_frames := horizontal_frames * vertical_frames
	return (
		not pose_name.is_empty()
		and texture != null
		and horizontal_frames > 0
		and vertical_frames > 0
		and first_frame >= 0
		and frame_count >= 1
		and first_frame + frame_count <= available_frames
		and (frame_count == 1 or frames_per_second > 0.0)
	)
