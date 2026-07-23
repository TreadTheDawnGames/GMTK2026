class_name MiningHud
extends CanvasLayer

## Displays remaining depth and collected placeholder ore.

@export var run_state: RunState
@export var ore_inventory: OreInventoryState
@export var depth_label: Label
@export var ore_label: Label


## Displays the starting depth.
func _ready() -> void:
	_update_remaining_depth(run_state.remaining_depth)
	_update_ore_count()


## Refreshes the label when depth changes.
func _on_depth_changed(_depth: int) -> void:
	_update_remaining_depth(run_state.remaining_depth)


## Refreshes the ore total after collection.
func _on_ore_inventory_changed() -> void:
	_update_ore_count()


## Shows how much gameplay depth remains before the run bottom.
func _update_remaining_depth(remaining_depth: int) -> void:
	depth_label.text = (
		"DEPTH  %s"
		% _format_number(remaining_depth)
	)


## Shows the placeholder ore collected during this run.
func _update_ore_count() -> void:
	ore_label.text = (
		"ORE  %s"
		% _format_number(
			ore_inventory.get_ore_count(&"placeholder_ore")
		)
	)


## Adds commas to a whole number.
func _format_number(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result
