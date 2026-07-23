class_name MiningHud
extends CanvasLayer

## Displays the remaining depth for the current run.

@export var run_state: RunState
@export var depth_label: Label


## Displays the starting depth.
func _ready() -> void:
	_update_remaining_depth(run_state.remaining_depth)


## Refreshes the label when depth changes.
func _on_depth_changed(_depth: int) -> void:
	_update_remaining_depth(run_state.remaining_depth)


## Shows how much gameplay depth remains before the run bottom.
func _update_remaining_depth(remaining_depth: int) -> void:
	depth_label.text = (
		"DEPTH  %s"
		% _format_number(remaining_depth)
	)


## Adds commas to a whole number.
func _format_number(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result
