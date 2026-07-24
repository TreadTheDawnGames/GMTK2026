class_name PickaxeProgression
extends Node

## How it works:
## - NPC rewards are appended to one cumulative run stack.
## - Every owned definition contributes mining modifiers and timing targets.
## - The newest reward controls only the visible tool appearance.
## - The invariant is that granting an upgrade never disables an older one.

signal upgrade_granted(definition: PickaxeDefinition)
signal target_unlocks_changed(definitions: Array[PickaxeDefinition])

@export_category("References")
@export var miner_rig: MinerRig
@export var mining_controller: MiningController

@export_category("Starting Equipment")
@export var starter_pickaxe: PickaxeDefinition

var loadout: PickaxeLoadout


## Creates the run stack and applies its starting pickaxe.
func _ready() -> void:
	loadout = PickaxeLoadout.new(starter_pickaxe)
	if not loadout.equipped_changed.is_connected(
		_apply_visible_pickaxe
	):
		loadout.equipped_changed.connect(_apply_visible_pickaxe)
	_apply_stack()


## Adds a merchant gift to the active stack and makes it the visible tool.
func grant_upgrade(definition: PickaxeDefinition) -> bool:
	if definition == null or definition.id.is_empty():
		return false
	if not loadout.owns(definition) and not loadout.unlock(definition):
		return false
	if not loadout.equip(definition):
		return false
	_apply_stack()
	upgrade_granted.emit(definition)
	return true


## Applies cumulative behavior and publishes the combined target collection.
func _apply_stack() -> void:
	var active_pickaxes := loadout.get_owned_pickaxes()
	mining_controller.set_active_pickaxes(active_pickaxes)
	_apply_visible_pickaxe(loadout.equipped)
	target_unlocks_changed.emit(active_pickaxes)


## Applies only the newest pickaxe's appearance to the miner.
func _apply_visible_pickaxe(definition: PickaxeDefinition) -> void:
	if definition == null:
		return
	miner_rig.set_hammer_head_color(definition.hammer_head_color)
