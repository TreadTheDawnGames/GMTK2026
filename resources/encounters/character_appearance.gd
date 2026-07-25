class_name CharacterAppearance
extends Resource

## Defines one sprite configuration available to an underground character.

@export var texture: Texture2D
@export_range(1, 64, 1) var horizontal_frames: int = 1
@export_range(1, 64, 1) var vertical_frames: int = 1
@export_range(0, 4_095, 1) var frame: int = 0
@export var sprite_scale: Vector2 = Vector2.ONE
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var tint: Color = Color.WHITE
@export var flip_h: bool = false
## Optional named idle/walk/speech poses; null preserves the current still sprite.
@export var pose_set: ActorPoseSet
