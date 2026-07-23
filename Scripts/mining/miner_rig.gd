class_name MinerRig
extends Node2D

## Presentation-only cutout rig. Gameplay chooses an animation; this script
## never calculates terrain damage or depth.

@export_category("Playback")
@export_range(0.1, 4.0, 0.05) var animation_speed_multiplier: float = 1.0
@export_range(0.0, 1.0, 0.05) var combo_speed_bonus: float = 0.35

@export_category("References")
@export var animation_player: AnimationPlayer

var _playing_full_swing: bool = false


func _ready() -> void:
	_play_idle()


func play_success(
	_depth_advanced_px: int,
	_cells_removed: int,
	_combo: int,
	effect_strength: float
) -> void:
	var combo_multiplier := lerpf(
		1.0,
		1.0 + combo_speed_bonus,
		effect_strength
	)
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(
		&"mine_success",
		-1.0,
		combo_multiplier
	)


func play_miss(_combo: int) -> void:
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"mine_miss")


func play_wind_up() -> void:
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_up")


func play_wind_down() -> void:
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_down")


func play_full_swing() -> void:
	# Authoring preview for the three-control wind-up and wind-down clips.
	_playing_full_swing = true
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_up")
	animation_player.queue(&"wind_down")


func set_animation_speed_multiplier(value: float) -> void:
	animation_speed_multiplier = clampf(value, 0.1, 4.0)
	if is_instance_valid(animation_player):
		animation_player.speed_scale = animation_speed_multiplier


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"wind_up" and _playing_full_swing:
		return
	if animation_name != &"idle" and animation_name != &"wind_up":
		_playing_full_swing = false
		_play_idle()


func _play_idle() -> void:
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"idle")
