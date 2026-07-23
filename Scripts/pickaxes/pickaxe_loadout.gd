class_name PickaxeLoadout
extends RefCounted

## Tracks the pickaxes owned by the player and which one is equipped.

signal inventory_changed(owned_pickaxes: Array[PickaxeDefinition])
signal equipped_changed(definition: PickaxeDefinition)

var equipped: PickaxeDefinition:
	get:
		return _equipped

var _owned_by_id: Dictionary[StringName, PickaxeDefinition] = {}
var _equipped: PickaxeDefinition


## Creates a loadout with an optional starter pickaxe already equipped.
func _init(starter_pickaxe: PickaxeDefinition = null) -> void:
	if starter_pickaxe == null:
		return
	if starter_pickaxe.id == &"":
		push_warning("The starter pickaxe needs a non-empty id.")
		return
	_owned_by_id[starter_pickaxe.id] = starter_pickaxe
	_equipped = starter_pickaxe


## Reports whether the player owns the supplied pickaxe.
func owns(definition: PickaxeDefinition) -> bool:
	return (
		definition != null
		and definition.id != &""
		and _owned_by_id.has(definition.id)
	)


## Adds a pickaxe to the inventory once.
func unlock(definition: PickaxeDefinition) -> bool:
	if definition == null or definition.id == &"" or owns(definition):
		return false
	_owned_by_id[definition.id] = definition
	inventory_changed.emit(get_owned_pickaxes())
	return true


## Equips an owned pickaxe for subsequent mining hits.
func equip(definition: PickaxeDefinition) -> bool:
	if not owns(definition):
		return false
	var owned_definition: PickaxeDefinition = _owned_by_id[definition.id]
	if _equipped == owned_definition:
		return true
	_equipped = owned_definition
	equipped_changed.emit(owned_definition)
	return true


## Returns a snapshot of the currently owned pickaxes.
func get_owned_pickaxes() -> Array[PickaxeDefinition]:
	var owned: Array[PickaxeDefinition] = []
	for definition: PickaxeDefinition in _owned_by_id.values():
		owned.append(definition)
	return owned
