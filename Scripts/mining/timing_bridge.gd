class_name TimingBridge
extends Node

## Sends Caspian's timing results to the mining controller.

signal attempt_resolved(success: bool, combo: int, hit_direction: int)

@export var timing_window: TimingWindowTask


## Connects Caspian's timing result to mining.
func _ready() -> void:
	if not timing_window.pressed.is_connected(_on_timing_pressed):
		timing_window.pressed.connect(_on_timing_pressed)


## Sends a timing-bar result to mining.
func _on_timing_pressed(
	success: bool,
	combo: int,
	hit_direction: int
) -> void:
	attempt_resolved.emit(success, combo, hit_direction)
