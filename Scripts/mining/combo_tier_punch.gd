class_name ComboTierPunch
extends Node

## How it works:
## - Input: the ComboDirector's tier crossings. Output: a camera zoom kick that
##   eases back, so reaching a threshold reads as an event instead of as a
##   slightly stronger copy of the ordinary per-hit feedback.
## - Deliberately no hitstop. Engine.time_scale is global, and slowing it mid
##   swing stretches the miner's animation, which delays swing_finished, which
##   delays the next queued hit. A streak would stretch the player's own input
##   cadence as its reward. Any future freeze has to stop presentation only.
## - Owned state: the camera's authored zoom and the live punch amount.
## - The invariant is that camera zoom always returns to the value captured
##   before the first punch, including on run reset.

@export_category("References")
@export var camera: Camera2D
## Read only for its tier count, so the punch scales without this file
## restating how many tiers exist.
@export var combo_director: ComboDirector

@export_category("Camera")
## Extra zoom the first tier climb kicks in.
@export_range(0.0, 0.5, 0.01) var minimum_zoom_punch: float = 0.04
## Extra zoom the top tier climb kicks in.
@export_range(0.0, 0.5, 0.01) var maximum_zoom_punch: float = 0.12
## How hard the kick arrives. Separate from the recovery so the punch can snap
## in and drift out, which is what makes it read as an impact.
@export_range(1.0, 60.0, 0.5) var zoom_attack_per_second: float = 28.0
@export_range(0.1, 20.0, 0.1) var zoom_recovery_per_second: float = 2.5

var _base_zoom: Vector2 = Vector2.ONE
var _has_captured_zoom: bool = false
var _requested_punch: float = 0.0
var _current_punch: float = 0.0


## Captures the authored zoom and sleeps until the first tier climb.
func _ready() -> void:
	set_process(false)
	_capture_base_zoom()


## Requests one kick per climb, scaled across the director's tier count.
func _on_combo_tier_changed(tier: int, previous_tier: int) -> void:
	if tier <= previous_tier:
		return
	_requested_punch = maxf(
		_requested_punch,
		lerpf(
			minimum_zoom_punch,
			maximum_zoom_punch,
			_tier_strength(tier)
		)
	)
	set_process(true)


## Returns the camera to rest for a fresh run.
func _on_run_reset() -> void:
	_requested_punch = 0.0
	_current_punch = 0.0
	if _has_captured_zoom and camera != null:
		camera.zoom = _base_zoom
	set_process(false)


## Snaps toward the requested kick, then drifts both back to rest.
func _process(delta: float) -> void:
	_current_punch = move_toward(
		_current_punch,
		_requested_punch,
		zoom_attack_per_second * delta
	)
	_requested_punch = move_toward(
		_requested_punch,
		0.0,
		zoom_recovery_per_second * delta
	)
	if camera != null and _has_captured_zoom:
		camera.zoom = _base_zoom * (1.0 + _current_punch)
	if _current_punch <= 0.0 and _requested_punch <= 0.0:
		set_process(false)


## Normalizes a tier to 0..1 across the director's authored tier count.
func _tier_strength(tier: int) -> float:
	if combo_director == null:
		return 1.0
	var maximum_tier := combo_director.maximum_intensity
	if maximum_tier <= 1:
		return 1.0
	return clampf(float(tier - 1) / float(maximum_tier - 1), 0.0, 1.0)


## Reads the camera's rest zoom once, so the punch always returns to it.
func _capture_base_zoom() -> void:
	if camera == null or _has_captured_zoom:
		return
	_base_zoom = camera.zoom
	_has_captured_zoom = true
