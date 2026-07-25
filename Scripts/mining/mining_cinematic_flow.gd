class_name MiningCinematicFlow
extends Node

## How it works:
## - One named interaction owns gameplay HUD, input, and camera focus.
## - Acquisition preserves the timing window and swing-queue states it found.
## - Focus remains a signal so MiningSceneWiring owns the camera connection.
## - Finish and cancel are idempotent and only release the matching owner.
## The invariant is that one cinematic can never unlock another cinematic.

signal camera_focus_requested
signal camera_released
signal flow_started(owner: StringName)
signal flow_finished(owner: StringName)

@export_category("References")
@export var timing_window: TimingWindowTask
@export var mining_controller: MiningController
@export var gameplay_hud: CanvasLayer
@export var impact_feedback_layer: CanvasLayer

var _owner: StringName
var _camera_is_focused: bool = false
var _previous_timing_process_mode: int = Node.PROCESS_MODE_INHERIT
var _previous_timing_visible: bool = true
var _previous_swing_queue_paused: bool = false
var _previous_gameplay_hud_visible: bool = true
var _previous_impact_feedback_visible: bool = true


## Claims the shared mining gate for one concrete interaction.
func try_begin(owner: StringName, focus_camera: bool = false) -> bool:
	if (
		owner.is_empty()
		or timing_window == null
		or mining_controller == null
		or is_busy()
		or mining_controller.is_swing_queue_paused()
	):
		return false
	_owner = owner
	_previous_timing_process_mode = timing_window.process_mode
	_previous_timing_visible = timing_window.visible
	_previous_swing_queue_paused = (
		mining_controller.is_swing_queue_paused()
	)
	if gameplay_hud != null:
		_previous_gameplay_hud_visible = gameplay_hud.visible
		gameplay_hud.visible = false
	if impact_feedback_layer != null:
		_previous_impact_feedback_visible = impact_feedback_layer.visible
		impact_feedback_layer.visible = false
	mining_controller.set_swing_queue_paused(true)
	timing_window.process_mode = Node.PROCESS_MODE_DISABLED
	timing_window.hide()
	flow_started.emit(_owner)
	if focus_camera:
		focus(owner)
	return true


## Freezes the gameplay view at the miner for the current owner.
func focus(owner: StringName) -> bool:
	if not is_owned_by(owner):
		return false
	if not _camera_is_focused:
		_camera_is_focused = true
		camera_focus_requested.emit()
	return true


## Restores the state captured by the matching owner.
func finish(owner: StringName) -> bool:
	if not is_owned_by(owner):
		return false
	var finished_owner := _owner
	if _camera_is_focused:
		_camera_is_focused = false
		camera_released.emit()
	mining_controller.set_swing_queue_paused(
		_previous_swing_queue_paused
	)
	timing_window.process_mode = _previous_timing_process_mode
	if _previous_timing_visible:
		timing_window.show()
	else:
		timing_window.hide()
	if gameplay_hud != null:
		gameplay_hud.visible = _previous_gameplay_hud_visible
	if impact_feedback_layer != null:
		impact_feedback_layer.visible = _previous_impact_feedback_visible
	_owner = &""
	flow_finished.emit(finished_owner)
	return true


## Restores gameplay through a short authored fade while dialogue stays visible.
func finish_with_presentation_fade(
	owner: StringName,
	fade_seconds: float
) -> bool:
	if not is_owned_by(owner):
		return false
	var hud_alpha: float = (
		gameplay_hud.modulate.a if gameplay_hud != null else 1.0
	)
	var feedback_alpha: float = (
		impact_feedback_layer.modulate.a
		if impact_feedback_layer != null
		else 1.0
	)
	if gameplay_hud != null:
		gameplay_hud.modulate.a = 0.0
	if impact_feedback_layer != null:
		impact_feedback_layer.modulate.a = 0.0
	if not finish(owner):
		return false
	var fade_duration := maxf(fade_seconds, 0.01)
	var fade_tween := create_tween()
	fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_tween.set_parallel(true)
	if gameplay_hud != null:
		fade_tween.tween_property(
			gameplay_hud,
			"modulate:a",
			hud_alpha,
			fade_duration
		)
	if impact_feedback_layer != null:
		fade_tween.tween_property(
			impact_feedback_layer,
			"modulate:a",
			feedback_alpha,
			fade_duration
		)
	return true


## Uses the same guarded cleanup for interrupted interactions.
func cancel(owner: StringName) -> bool:
	return finish(owner)


## Reports whether any interaction owns the mining gate.
func is_busy() -> bool:
	return not _owner.is_empty()


## Reports whether the caller owns the shared mining gate.
func is_owned_by(owner: StringName) -> bool:
	return not owner.is_empty() and _owner == owner


## Returns the current cinematic owner for diagnostics and verification.
func get_flow_owner() -> StringName:
	return _owner
