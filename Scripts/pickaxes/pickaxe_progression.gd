class_name PickaxeProgression
extends Node

## Owns the player's pickaxe collection and equips gifts from encounters.

signal upgrade_granted(definition: PickaxeDefinition)

@export_category("References")
@export var miner_rig: MinerRig
@export var mining_controller: MiningController

@export_category("Starting Equipment")
@export var starter_pickaxe: PickaxeDefinition

var loadout: PickaxeLoadout


## Creates the run loadout and applies its starting pickaxe.
func _ready() -> void:
	loadout = PickaxeLoadout.new(starter_pickaxe)
	if not loadout.equipped_changed.is_connected(
		_apply_equipped_pickaxe
	):
		loadout.equipped_changed.connect(_apply_equipped_pickaxe)
	_apply_equipped_pickaxe(loadout.equipped)


## Adds and equips the pickaxe presented by a completed encounter.
func grant_upgrade(definition: PickaxeDefinition) -> bool:
	if definition == null or definition.id.is_empty():
		return false
	if not loadout.owns(definition) and not loadout.unlock(definition):
		return false
	if not loadout.equip(definition):
		return false
	upgrade_granted.emit(definition)
	return true


## Applies the active pickaxe to mining behavior and hammer appearance.
func _apply_equipped_pickaxe(definition: PickaxeDefinition) -> void:
	if definition == null:
		return
	mining_controller.set_equipped_pickaxe(definition)
	miner_rig.set_hammer_head_color(definition.hammer_head_color)
