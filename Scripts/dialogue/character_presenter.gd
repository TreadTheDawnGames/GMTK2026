class_name CharacterPresenter
extends Node2D

## Displays CharacterAppearance unchanged unless an optional pose can play.
## Speech motion remains independent from the visible texture and sheet frame.

const SpeechReactionType = preload(
	"res://Scripts/dialogue/speech_reaction.gd"
)
const GroundWalkType = preload(
	"res://Scripts/cinematics/ground_walk.gd"
)

@export_category("References")
@export var character_sprite: Sprite2D
@export var actor_sprite_view: ActorSpriteView
@export var speech_reaction: SpeechReactionType

var _base_sprite_position: Vector2
var _departure_tween: Tween


## Stores the authored sprite position before an appearance is assigned.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_base_sprite_position = character_sprite.position
	speech_reaction.capture_rest_position()


## Applies the authored sprite configuration for one named character.
func apply_appearance(appearance: CharacterAppearance) -> void:
	speech_reaction.reset_speech_motion()
	if appearance == null:
		hide()
		return
	character_sprite.texture = appearance.texture
	character_sprite.hframes = appearance.horizontal_frames
	character_sprite.vframes = appearance.vertical_frames
	character_sprite.frame = appearance.frame
	character_sprite.scale = appearance.sprite_scale
	character_sprite.position = appearance.sprite_offset
	character_sprite.modulate = appearance.tint
	character_sprite.flip_h = appearance.flip_h
	_base_sprite_position = character_sprite.position
	speech_reaction.capture_rest_position()
	if actor_sprite_view != null:
		actor_sprite_view.pose_set = appearance.pose_set
		actor_sprite_view.play_pose(&"idle")


## Resets bounce timing before a new character conversation begins.
func reset_speech_motion() -> void:
	speech_reaction.reset_speech_motion()
	character_sprite.position = _base_sprite_position
	if actor_sprite_view != null:
		actor_sprite_view.play_pose(&"idle")


## Bounces until another speaker or the conversation takes over.
func react_to_presented_line() -> void:
	speech_reaction.react_to_presented_line()


## Reports whether this presenter can display an optional dialogue pose.
func has_pose(pose_name: StringName) -> bool:
	return (
		actor_sprite_view != null
		and actor_sprite_view.has_pose(pose_name)
	)


## Displays an optional dialogue pose without changing speech motion.
func play_pose(pose_name: StringName) -> bool:
	return (
		actor_sprite_view != null
		and actor_sprite_view.play_pose(pose_name)
	)


## Faces the visible character along its current travel direction.
func set_facing_direction(direction: int) -> void:
	if not is_instance_valid(character_sprite) or direction == 0:
		return
	character_sprite.flip_h = direction < 0


## Walks to one authored global position over sampled terrain.
func move_grounded_to(
	target_position: Vector2,
	duration: float,
	floor_sampler: Callable,
	hide_on_finish: bool = false,
	step_height: float = GroundWalkType.DEFAULT_STEP_HEIGHT
) -> Tween:
	reset_speech_motion()
	cancel_grounded_motion()
	var start_position := global_position
	var horizontal_direction := signf(target_position.x - start_position.x)
	if not is_zero_approx(horizontal_direction):
		set_facing_direction(1 if horizontal_direction > 0.0 else -1)
	var ground_path := GroundWalkType.build_path(
		start_position,
		target_position,
		floor_sampler,
		GroundWalkType.DEFAULT_STRIDE_PIXELS
	)
	_departure_tween = GroundWalkType.walk_along(
		self,
		ground_path,
		duration,
		step_height
	)
	if _departure_tween != null and hide_on_finish:
		_departure_tween.tween_callback(hide)
	return _departure_tween


## Stops presentation travel without changing the actor's current position.
func cancel_grounded_motion() -> void:
	if _departure_tween != null and _departure_tween.is_valid():
		_departure_tween.kill()
	_departure_tween = null


## Walks right and returns the pause-safe tween used to await the exit.
func depart_right(
	distance: float,
	duration: float,
	floor_sampler: Callable
) -> Tween:
	return move_grounded_to(
		global_position + Vector2.RIGHT * maxf(distance, 0.0),
		duration,
		floor_sampler,
		true
	)
