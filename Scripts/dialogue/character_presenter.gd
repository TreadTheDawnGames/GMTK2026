class_name CharacterPresenter
extends Node2D

## Displays a configured character and adds motion while they are speaking.

@export_category("References")
@export var character_sprite: Sprite2D

@export_category("Speech Motion")
@export_range(1.0, 30.0, 1.0) var bounce_height: float = 7.0
@export_range(0.04, 0.5, 0.01) var bounce_duration: float = 0.14

var _base_sprite_position: Vector2
var _bounce_tween: Tween
var _departure_tween: Tween


## Stores the authored sprite position before an appearance is assigned.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_base_sprite_position = character_sprite.position


## Applies the authored sprite configuration for one named character.
func apply_appearance(appearance: CharacterAppearance) -> void:
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
	reset_speech_motion()


## Resets bounce timing before a new character conversation begins.
func reset_speech_motion() -> void:
	if _bounce_tween != null and _bounce_tween.is_valid():
		_bounce_tween.kill()
	_bounce_tween = null
	character_sprite.position = _base_sprite_position


## Bounces until another speaker or the conversation takes over.
func react_to_presented_line() -> void:
	reset_speech_motion()
	var half_duration := bounce_duration * 0.5
	_bounce_tween = create_tween()
	_bounce_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_bounce_tween.tween_property(
		character_sprite,
		"position",
		_base_sprite_position + Vector2.UP * bounce_height,
		half_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_bounce_tween.tween_property(
		character_sprite,
		"position",
		_base_sprite_position,
		half_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Walks this character out through the chamber's authored right opening.
func depart_right(distance: float, duration: float) -> void:
	reset_speech_motion()
	if _departure_tween != null and _departure_tween.is_valid():
		_departure_tween.kill()
	_departure_tween = create_tween()
	_departure_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_departure_tween.tween_property(
		self,
		"position:x",
		position.x + maxf(distance, 0.0),
		maxf(duration, 0.01)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_departure_tween.tween_callback(hide)
