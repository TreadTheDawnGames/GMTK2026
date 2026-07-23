class_name OreInventoryState
extends Node

## Stores ore collected during the current run.

signal ore_count_changed(
	ore_id: StringName,
	new_count: int,
	amount_delta: int
)
signal inventory_changed

var _ore_counts: Dictionary[StringName, int] = {}


## Clears every collected ore when a new run starts.
func reset_inventory() -> void:
	_ore_counts.clear()
	inventory_changed.emit()


## Adds a mined batch and reports each changed total.
func add_ore_batch(
	ore_yields: Dictionary[StringName, int]
) -> void:
	var changed := false
	for ore_id: StringName in ore_yields:
		var amount := maxi(int(ore_yields[ore_id]), 0)
		if amount == 0:
			continue
		var new_count := get_ore_count(ore_id) + amount
		_ore_counts[ore_id] = new_count
		ore_count_changed.emit(ore_id, new_count, amount)
		changed = true
	if changed:
		inventory_changed.emit()


## Returns the collected total for one ore type.
func get_ore_count(ore_id: StringName) -> int:
	return int(_ore_counts.get(ore_id, 0))


## Returns a copy of all collected ore totals.
func get_all_ore_counts() -> Dictionary[StringName, int]:
	return _ore_counts.duplicate()
