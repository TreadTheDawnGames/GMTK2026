class_name MinerRig
extends Node2D

## Plays animations for the miner cutout rig.

signal success_impact(screen_position: Vector2, effect_strength: float)

@export_category("Playback")
@export_range(0.1, 4.0, 0.05) var animation_speed_multiplier: float = 1.0
@export_range(0.0, 1.0, 0.05) var combo_speed_bonus: float = 0.35

@export_category("References")
@export var animation_player: AnimationPlayer
@export var impact_point: Marker2D

var _playing_full_swing: bool = false
var _pending_effect_strength: float = 0.0


## Starts the idle animation when the rig loads.
func _ready() -> void:
	_play_idle()


## Plays the successful hit animation faster for stronger combo hits.
func play_success(
	_depth_advanced_px: int,
	_cells_removed: int,
	_combo: int,
	effect_strength: float
) -> void:
	_pending_effect_strength = effect_strength
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


## Reports the hammer-tip position at the contact keyframe.
func _emit_success_impact() -> void:
	success_impact.emit(
		impact_point.global_position,
		_pending_effect_strength
	)


## Plays the missed-swing animation.
func play_miss(_combo: int) -> void:
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"mine_miss")


## Plays the wind-up animation.
func play_wind_up() -> void:
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_up")


## Plays the downward strike animation.
func play_wind_down() -> void:
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_down")


## Plays the complete wind-up and strike sequence.
func play_full_swing() -> void:
	# Authoring preview for the three-control wind-up and wind-down clips.
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


## Returns finished actions to idle after any queued strike plays.
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"wind_up" and _playing_full_swing:
		return
	if animation_name != &"idle" and animation_name != &"wind_up":
		_playing_full_swing = false
		_play_idle()


## Plays idle at the current speed setting.
func _play_idle() -> void:
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"idle")
