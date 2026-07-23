class_name TimingBridge
extends Node

## Sends Caspian's timing results to the mining controller.

signal attempt_resolved(success: bool, combo: int)

@export var timing_window: TimingWindowTask

var _reported_recovery_failure: bool = false


## Connects Caspian's timing bar and recovery dial to mining.
func _ready() -> void:
	if not timing_window.pressed.is_connected(_on_timing_pressed):
		timing_window.pressed.connect(_on_timing_pressed)
	if not timing_window.is_node_ready():
		await timing_window.ready
	if not timing_window.timing_dial.pressed.is_connected(
		_on_recovery_dial_pressed
	):
		timing_window.timing_dial.pressed.connect(
			_on_recovery_dial_pressed
		)
	if not timing_window.timing_dial.visibility_changed.is_connected(
		_on_recovery_dial_visibility_changed
	):
		timing_window.timing_dial.visibility_changed.connect(
			_on_recovery_dial_visibility_changed
		)


## Sends a timing-bar result to mining.
func _on_timing_pressed(success: bool, combo: int) -> void:
	attempt_resolved.emit(success, combo)


## Sends one miss when the recovery dial fails.
func _on_recovery_dial_pressed(success: bool) -> void:
	# The dial emits failure once for the press and again while stopping.
	if success or _reported_recovery_failure:
		return
	_reported_recovery_failure = true
	attempt_resolved.emit(false, 0)


## Allows the next recovery dial to report a failure.
func _on_recovery_dial_visibility_changed() -> void:
	if timing_window.timing_dial.visible:
		_reported_recovery_failure = false
