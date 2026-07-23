class_name MiningHud
extends CanvasLayer

## Displays the player's current depth.

@export var run_state: RunState
@export var depth_label: Label


## Displays the starting depth.
func _ready() -> void:
	_update_depth(run_state.depth_px)


## Refreshes the label when depth changes.
func _on_depth_changed(depth_px: int) -> void:
	_update_depth(depth_px)


## Updates the depth label text.
func _update_depth(depth_px: int) -> void:
	depth_label.text = "DEPTH  %s px" % _format_number(depth_px)


## Adds commas to a whole number.
func _format_number(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result
