class_name OreInventoryState
extends Node

## Stores collected ore totals for HUD, equipment, and shop systems.

signal ore_count_changed(
	ore_id: StringName,
	new_count: int,
	amount_delta: int
)
signal inventory_changed

var _ore_counts: Dictionary = {}


## Clears every collected ore when a new run starts.
func reset_inventory() -> void:
	_ore_counts.clear()
	inventory_changed.emit()


## Adds a mined batch and reports each changed total.
func add_ore_batch(ore_yields: Dictionary) -> void:
	var changed := false
	for ore_id: Variant in ore_yields:
		var typed_ore_id := StringName(ore_id)
		var amount := maxi(int(ore_yields[ore_id]), 0)
		if amount == 0:
			continue
		var new_count := get_ore_count(typed_ore_id) + amount
		_ore_counts[typed_ore_id] = new_count
		ore_count_changed.emit(typed_ore_id, new_count, amount)
		changed = true
	if changed:
		inventory_changed.emit()


## Spends one ore type only when the requested amount is available.
func try_spend_ore(ore_id: StringName, amount: int) -> bool:
	if amount < 0:
		return false
	var current_count := get_ore_count(ore_id)
	if current_count < amount:
		return false
	var new_count := current_count - amount
	_ore_counts[ore_id] = new_count
	ore_count_changed.emit(ore_id, new_count, -amount)
	inventory_changed.emit()
	return true


## Returns the collected total for one ore type.
func get_ore_count(ore_id: StringName) -> int:
	return int(_ore_counts.get(ore_id, 0))


## Returns a copy of all collected ore totals.
func get_all_ore_counts() -> Dictionary:
	return _ore_counts.duplicate()
