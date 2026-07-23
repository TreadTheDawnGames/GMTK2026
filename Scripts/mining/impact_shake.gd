class_name ImpactShake
extends Node

## Shakes the game camera briefly when a successful mining hit lands.

@export_category("Reference")
@export var camera: Camera2D

@export_category("Shake")
@export_range(0.0, 20.0, 0.25) var base_strength_px: float = 2.5
@export_range(0.0, 20.0, 0.25) var combo_bonus_px: float = 2.5
@export_range(0.01, 1.0, 0.01) var duration_seconds: float = 0.16
@export_range(1.0, 120.0, 1.0) var samples_per_second: float = 45.0

var _remaining_seconds: float = 0.0
var _current_strength_px: float = 0.0
var _seconds_until_sample: float = 0.0
var _random := RandomNumberGenerator.new()


## Sleeps until the first impact requests a shake.
func _ready() -> void:
	_random.randomize()
	set_process(false)


## Starts a subtle shake scaled by the hit's normalized combo strength.
func play_at_impact(
	_impact_screen_position: Vector2,
	cells_removed: int,
	combo_strength: float,
	_debris_multiplier: float
) -> void:
	if cells_removed <= 0:
		return
	_current_strength_px = lerpf(
		base_strength_px,
		base_strength_px + combo_bonus_px,
		clampf(combo_strength, 0.0, 1.0)
	)
	_remaining_seconds = duration_seconds
	_seconds_until_sample = 0.0
	set_process(true)


## Updates camera jitter and returns it to rest after the shake.
func _process(delta: float) -> void:
	_remaining_seconds = maxf(_remaining_seconds - delta, 0.0)
	if _remaining_seconds <= 0.0:
		camera.offset = Vector2.ZERO
		set_process(false)
		return

	_seconds_until_sample -= delta
	if _seconds_until_sample > 0.0:
		return
	_seconds_until_sample = 1.0 / samples_per_second
	var fade_weight := _remaining_seconds / duration_seconds
	camera.offset = Vector2(
		_random.randf_range(-1.0, 1.0),
		_random.randf_range(-1.0, 1.0)
	) * _current_strength_px * fade_weight
