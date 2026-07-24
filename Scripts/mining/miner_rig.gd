class_name MinerRig
extends Node2D

## Plays the miner's drawn frames and reports the authored contact moment.

signal impact_contact(screen_position: Vector2)
signal swing_finished

@export_category("Playback")
@export_range(0.1, 4.0, 0.05) var animation_speed_multiplier: float = 1.0
@export_range(0.0, 1.0, 0.05) var combo_speed_bonus: float = 0.35

@export_category("Placement")
## Seats the miner on the pale top stratum at the surface and merchant floors.
@export_range(0.0, 64.0, 1.0) var intact_floor_grounding_offset_y: float = 16.0
## Slightly overlaps the sampled dirt edge so texture filtering cannot show a gap.
@export_range(0.0, 4.0, 0.25) var grounding_overlap_y: float = 1.0

@export_category("References")
@export var animation_player: AnimationPlayer
@export var visual_root: Node2D
@export var drawn_miner_sprite: Sprite2D
@export var landing_foot_anchor: Marker2D
@export var idle_miner_texture: Texture2D
@export var impact_miner_texture: Texture2D
@export var impact_point: Marker2D
@export var stand_in_hammer_head: Line2D
@export var final_hammer_head_sprite: Sprite2D
@export var impact_audio_player: AudioStreamPlayer2D

var _playing_full_swing: bool = false
var _rest_position: Vector2
var _visual_root_rest_y: float


## Connects animation events and starts the idle animation.
func _ready() -> void:
	_rest_position = position
	_visual_root_rest_y = visual_root.position.y
	_set_miner_texture(idle_miner_texture)
	show_intact_floor_grounding()
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
	_set_miner_texture(idle_miner_texture)
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
	_set_miner_texture(impact_miner_texture)
	if impact_audio_player.stream != null:
		impact_audio_player.play()
	impact_contact.emit(impact_point.global_position)


## Plays the missed-swing animation.
func play_miss(_combo: int) -> void:
	_set_miner_texture(idle_miner_texture)
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"mine_miss")


## Holds the miner in the raised pickaxe pose.
func play_wind_up() -> void:
	_set_miner_texture(idle_miner_texture)
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_up")


## Holds the miner in the downward impact pose.
func play_wind_down() -> void:
	_set_miner_texture(impact_miner_texture)
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_down")


## Previews the raised and impact poses in sequence.
func play_full_swing() -> void:
	# Authoring preview for the two discrete mining poses.
	_set_miner_texture(idle_miner_texture)
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


## Places the artwork above the first layer on an authored intact floor.
func show_intact_floor_grounding() -> void:
	_set_grounding_offset(intact_floor_grounding_offset_y)


## Seats the authored sole baseline on the renderer's sampled dirt support.
func seat_landing_foot_at_screen_y(support_screen_y: float) -> void:
	if is_nan(support_screen_y) or not is_instance_valid(landing_foot_anchor):
		return
	var grounding_delta: float = (
		support_screen_y
		+ grounding_overlap_y
		- landing_foot_anchor.global_position.y
	)
	var current_grounding_offset: float = (
		visual_root.position.y - _visual_root_rest_y
	)
	_set_grounding_offset(current_grounding_offset + grounding_delta)


## Returns the horizontal sole position used to sample organic terrain.
func get_landing_foot_screen_x() -> float:
	if not is_instance_valid(landing_foot_anchor):
		return global_position.x
	return landing_foot_anchor.global_position.x


## Changes presentation placement without moving ChipOrigin mining logic.
func _set_grounding_offset(offset_y: float) -> void:
	visual_root.position.y = _visual_root_rest_y + offset_y


## Swaps authored full-frame poses without changing gameplay coordinates.
func _set_miner_texture(texture: Texture2D) -> void:
	if texture != null and is_instance_valid(drawn_miner_sprite):
		drawn_miner_sprite.texture = texture


## Returns finished actions to idle after any queued strike plays.
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"wind_up" and _playing_full_swing:
		_set_miner_texture(impact_miner_texture)
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
	_set_miner_texture(idle_miner_texture)
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"idle")
