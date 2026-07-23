class_name MinerRig
extends Node2D

## Plays the miner's drawn frames and reports the authored contact moment.

signal impact_contact(screen_position: Vector2)
signal swing_finished

@export_category("Playback")
@export_range(0.1, 4.0, 0.05) var animation_speed_multiplier: float = 1.0
@export_range(0.0, 1.0, 0.05) var combo_speed_bonus: float = 0.35

@export_category("Placement")
## Seats the artwork into the layered opening without moving ChipOrigin logic.
@export_range(0.0, 64.0, 1.0) var terrain_grounding_offset_y: float = 32.0

@export_category("References")
@export var animation_player: AnimationPlayer
@export var visual_root: Node2D
@export var drawn_miner_sprite: Sprite2D
@export var impact_point: Marker2D
@export var stand_in_hammer_head: Line2D
@export var final_hammer_head_sprite: Sprite2D
@export var impact_audio_player: AudioStreamPlayer2D

var _playing_full_swing: bool = false
var _rest_position: Vector2


## Connects animation events and starts the idle animation.
func _ready() -> void:
	_rest_position = position
	# VisualRoot owns presentation placement. Keeping the offset off this
	# script's root prevents art tuning from changing mining coordinates.
	visual_root.position.y += terrain_grounding_offset_y
	if not animation_player.animation_finished.is_connected(
		_on_animation_finished
	):
		animation_player.animation_finished.connect(
			_on_animation_finished
		)
	_play_idle()


## Plays the successful strike at its combo and equipped-pickaxe speed.
func play_success(
	_combo: int,
	combo_strength: float,
	swing_speed_multiplier: float
) -> void:
	var combo_multiplier := lerpf(
		1.0,
		1.0 + combo_speed_bonus,
		combo_strength
	)
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(
		&"two_frame_success",
		-1.0,
		combo_multiplier * maxf(swing_speed_multiplier, 0.1)
	)


## Reports the hammer-tip position when the animation reaches the ground.
func _emit_success_impact() -> void:
	if impact_audio_player.stream != null:
		impact_audio_player.play()
	impact_contact.emit(impact_point.global_position)


## Plays the missed-swing animation.
func play_miss(_combo: int) -> void:
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"mine_miss")


## Holds the miner in the raised pickaxe pose.
func play_wind_up() -> void:
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_up")


## Holds the miner in the downward impact pose.
func play_wind_down() -> void:
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_down")


## Previews the raised and impact poses in sequence.
func play_full_swing() -> void:
	# Authoring preview for the two discrete mining poses.
	_playing_full_swing = true
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_up")
	animation_player.queue(&"wind_down")


## Sets the playback speed within the supported range.
func set_animation_speed_multiplier(value: float) -> void:
	animation_speed_multiplier = clampf(value, 0.1, 4.0)
	if is_instance_valid(animation_player):
		animation_player.speed_scale = animation_speed_multiplier


## Applies the equipped pickaxe color to every available miner art slot.
func set_hammer_head_color(color: Color) -> void:
	if is_instance_valid(stand_in_hammer_head):
		stand_in_hammer_head.default_color = color
	if is_instance_valid(final_hammer_head_sprite):
		final_hammer_head_sprite.self_modulate = color
	if (
		is_instance_valid(drawn_miner_sprite)
		and drawn_miner_sprite.material is ShaderMaterial
	):
		var drawn_material := (
			drawn_miner_sprite.material as ShaderMaterial
		)
		drawn_material.set_shader_parameter(&"tool_tint", color)


## Faces the visible miner toward the selected mining side.
func set_facing_direction(direction: int) -> void:
	if not is_instance_valid(visual_root) or direction == 0:
		return
	visual_root.scale.x = absf(visual_root.scale.x) * signi(direction)


## Reports which side currently holds the raised pickaxe.
func get_facing_direction() -> int:
	if (
		not is_instance_valid(visual_root)
		or is_zero_approx(visual_root.scale.x)
	):
		return 1
	return signi(roundi(visual_root.scale.x))


## Places the miner at true screen depth during falls, flips, and review.
func set_screen_depth_offset(screen_offset_y: float) -> void:
	position.y = _rest_position.y + screen_offset_y


## Returns finished actions to idle after any queued strike plays.
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"wind_up" and _playing_full_swing:
		return
	if animation_name == &"two_frame_success":
		_playing_full_swing = false
		_play_idle()
		swing_finished.emit()
		return
	if animation_name != &"idle" and animation_name != &"wind_up":
		_playing_full_swing = false
		_play_idle()


## Plays idle at the current speed setting.
func _play_idle() -> void:
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"idle")
