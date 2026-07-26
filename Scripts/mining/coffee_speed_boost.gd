class_name CoffeeSpeedBoost
extends Node

## How it works:
## - Retained for isolated previews; production Quibble no longer awards it.
## - The Quibble conversation callback awards one run-scoped speed boost.
## - The boost multiplies MinerRig playback, including real impact timing.
## - Duplicate conversation events cannot stack the reward.
## - Run reset restores the exact authored base playback speed.
## - The invariant is that coffee changes timing, never mining power or rewards.

signal boost_awarded(speed_multiplier: float)

@export_category("Reward")
@export var reward_conversation_id: StringName = &"coffee_cat_first"
@export_range(1.0, 4.0, 0.05) var speed_multiplier: float = 1.35

@export_category("References")
@export var miner_rig: MinerRig

var has_boost: bool = false
var _base_animation_speed_multiplier: float = 1.0
var _has_captured_base_speed: bool = false


## Captures designer-authored playback as the reset baseline.
func _ready() -> void:
	if miner_rig == null:
		push_error("CoffeeSpeedBoost requires a MinerRig reference.")
		return
	_capture_base_speed()


## Filters the shared dialogue completion signal to Quibble's reward.
func _on_conversation_finished(conversation_id: StringName) -> void:
	if conversation_id == reward_conversation_id:
		award_boost()


## Applies the persistent run boost and returns whether it was newly awarded.
func award_boost() -> bool:
	if has_boost or miner_rig == null:
		return false
	if not _has_captured_base_speed:
		_capture_base_speed()
	has_boost = true
	miner_rig.set_animation_speed_multiplier(
		_base_animation_speed_multiplier
		* maxf(speed_multiplier, 1.0)
	)
	boost_awarded.emit(speed_multiplier)
	return true


## Restores the authored speed for a fresh run.
func _on_run_reset() -> void:
	if miner_rig == null:
		has_boost = false
		return
	if not _has_captured_base_speed:
		_capture_base_speed()
	has_boost = false
	miner_rig.set_animation_speed_multiplier(
		_base_animation_speed_multiplier
	)


func _capture_base_speed() -> void:
	_base_animation_speed_multiplier = (
		miner_rig.animation_speed_multiplier
	)
	_has_captured_base_speed = true
