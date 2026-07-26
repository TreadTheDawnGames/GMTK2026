class_name ImpactShake
extends Node

## Shakes the game camera for mining impacts and sustained cinematic rumble.

@export_category("Reference")
@export var camera: Camera2D

@export_category("Shake")
@export_range(0.0, 20.0, 0.25) var base_strength_px: float = 2.5
@export_range(0.0, 20.0, 0.25) var combo_bonus_px: float = 2.5
@export_range(0.01, 1.0, 0.01) var duration_seconds: float = 0.16
@export_range(1.0, 120.0, 1.0) var samples_per_second: float = 45.0

@export_category("Direction")
## Portion of the shake spent as a kick away from the swing rather than as
## jitter. A directional kick reads considerably harder than random jitter of
## the same pixel size, which is why this defaults above half.
@export_range(0.0, 1.0, 0.05) var directional_portion: float = 0.65
## How much of the kick points down the pickaxe rather than sideways.
@export_range(0.0, 2.0, 0.05) var downward_bias: float = 1.0

var _remaining_seconds: float = 0.0
var _current_strength_px: float = 0.0
var _seconds_until_sample: float = 0.0
var _kick_direction: Vector2 = Vector2.DOWN
var _jitter_offset: Vector2 = Vector2.ZERO
var _sustained_strength_px: float = 0.0
var _sustained_jitter_offset: Vector2 = Vector2.ZERO
var _random := RandomNumberGenerator.new()


## Sleeps until the first impact requests a shake.
func _ready() -> void:
	_random.randomize()
	set_process(false)


## Starts a subtle shake scaled by the hit's normalized combo strength, kicked
## away from the side the pickaxe came down on.
func play_at_impact(
	_impact_screen_position: Vector2,
	cells_removed: int,
	combo_strength: float,
	_debris_multiplier: float,
	swing_side: int = 1
) -> void:
	if cells_removed <= 0:
		return
	_current_strength_px = lerpf(
		base_strength_px,
		base_strength_px + combo_bonus_px,
		clampf(combo_strength, 0.0, 1.0)
	)
	# A hit from the right drives the frame down and to the left.
	_kick_direction = Vector2(
		-signf(float(swing_side)) if swing_side != 0 else 0.0,
		downward_bias
	).normalized()
	_remaining_seconds = duration_seconds
	_seconds_until_sample = 0.0
	_jitter_offset = Vector2.ZERO
	set_process(true)


func begin_sustained(strength_px: float) -> void:
	_sustained_strength_px = maxf(strength_px, 0.0)
	_seconds_until_sample = 0.0
	set_process(_sustained_strength_px > 0.0 or _remaining_seconds > 0.0)


func end_sustained() -> void:
	_sustained_strength_px = 0.0
	_sustained_jitter_offset = Vector2.ZERO
	if _remaining_seconds <= 0.0:
		camera.offset = Vector2.ZERO
		set_process(false)


## Updates camera jitter and returns it to rest after the shake.
func _process(delta: float) -> void:
	_remaining_seconds = maxf(_remaining_seconds - delta, 0.0)
	var fade_weight := _remaining_seconds / duration_seconds
	# The jitter is resampled on its own cadence, but the kick has to move every
	# frame or the recoil reads as a second, softer shake instead of one hit.
	_seconds_until_sample -= delta
	if _seconds_until_sample <= 0.0:
		_seconds_until_sample = 1.0 / samples_per_second
		_jitter_offset = Vector2(
			_random.randf_range(-1.0, 1.0),
			_random.randf_range(-1.0, 1.0)
		) * (1.0 - directional_portion)
		_sustained_jitter_offset = Vector2(
			_random.randf_range(-1.0, 1.0),
			_random.randf_range(-1.0, 1.0)
		) * _sustained_strength_px
	var impact_offset := (
		_kick_direction * directional_portion * fade_weight
		+ _jitter_offset
	) * _current_strength_px * fade_weight
	camera.offset = impact_offset + _sustained_jitter_offset
	if _remaining_seconds <= 0.0 and _sustained_strength_px <= 0.0:
		camera.offset = Vector2.ZERO
		set_process(false)
