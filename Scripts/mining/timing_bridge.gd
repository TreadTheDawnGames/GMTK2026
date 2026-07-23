class_name TimingBridge
extends Node

## Isolates the mining environment from Caspian's timing-window API. Caspian's
## bar result is forwarded without changing its behavior. A failed recovery
## dial is translated into the single miss result expected by mining.

signal attempt_resolved(success: bool, combo: int)

@export var timing_window: TimingWindowTask

var _reported_recovery_failure: bool = false


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


func _on_timing_pressed(success: bool, combo: int) -> void:
	attempt_resolved.emit(success, combo)


func _on_recovery_dial_pressed(success: bool) -> void:
	# The dial emits failure once for the press and again while stopping.
	if success or _reported_recovery_failure:
		return
	_reported_recovery_failure = true
	attempt_resolved.emit(false, 0)


func _on_recovery_dial_visibility_changed() -> void:
	if timing_window.timing_dial.visible:
		_reported_recovery_failure = false
