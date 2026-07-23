class_name MiningHud
extends CanvasLayer

## Read-only run presentation. Caspian's timing scene owns its own combo label.

@export var run_state: RunState
@export var depth_label: Label


func _ready() -> void:
	_update_depth(run_state.depth_px)


func _on_depth_changed(depth_px: int) -> void:
	_update_depth(depth_px)


func _update_depth(depth_px: int) -> void:
	depth_label.text = "DEPTH  %s px" % _format_number(depth_px)


func _format_number(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result
