class_name CharacterAppearance
extends Resource

## Defines one sprite configuration available to an underground character.

@export var texture: Texture2D
@export_range(1, 64, 1) var horizontal_frames: int = 1
@export_range(1, 64, 1) var vertical_frames: int = 1
@export_range(0, 4_095, 1) var frame: int = 0
@export var sprite_scale: Vector2 = Vector2.ONE
## Horizontal staging only. Runtime and editor previews measure the lowest
## opaque row so transparent canvas padding cannot move a character's feet.
@export var sprite_offset: Vector2 = Vector2.ZERO
## Optional world-pixel correction when a carried prop extends below the body.
## Positive values lower the body into its sampled floor; zero keeps the
## bottommost opaque pixel on the actor origin.
@export var body_grounding_offset_y: float = 0.0
@export var tint: Color = Color.WHITE
@export var flip_h: bool = false
## Which way the source art already looks. Turning an actor to face its travel
## assumes art drawn looking right, so art drawn looking left walks backwards
## and ends a walk facing away from whoever it just approached. This says which
## it is; it does not mirror anything on its own.
@export var art_faces_left: bool = false
## Optional named idle/walk/speech poses; null preserves the current still sprite.
@export var pose_set: ActorPoseSet
