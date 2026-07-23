class_name PickaxeShopCoordinator
extends Node

## Connects mined ore, shop purchases, equipped tools, and mining effects.

@export_category("References")
@export var ore_inventory: OreInventoryState
@export var shop: PickaxeShop
@export var miner_rig: MinerRig
@export var mining_controller: MiningController

@export_category("Configuration")
@export var starter_pickaxe: PickaxeDefinition
@export var currency_ore_id: StringName = &"placeholder_ore"

var balance: ShopBalance
var loadout: PickaxeLoadout


## Creates the run wallet and equips the authored starter pickaxe.
func _ready() -> void:
	balance = ShopBalance.new(
		ore_inventory.get_ore_count(currency_ore_id)
	)
	loadout = PickaxeLoadout.new(starter_pickaxe)
	shop.configure(balance, loadout)
	ore_inventory.inventory_changed.connect(_sync_balance_from_ore)
	shop.purchase_result.connect(_on_purchase_result)
	loadout.equipped_changed.connect(_apply_equipped_pickaxe)
	_apply_equipped_pickaxe(loadout.equipped)


## Mirrors collected currency ore into the balance shown by the shop.
func _sync_balance_from_ore() -> void:
	balance.set_amount(ore_inventory.get_ore_count(currency_ore_id))


## Removes the ore already accepted by the shop's affordability check.
func _on_purchase_result(
	_definition: PickaxeDefinition,
	purchased: bool,
	_remaining_balance: int
) -> void:
	if not purchased:
		return
	if ore_inventory.try_spend_ore(
		currency_ore_id,
		_definition.cost
	):
		return
	push_error("A completed shop purchase could not spend its currency ore.")


## Applies the equipped pickaxe to mining behavior and hammer appearance.
func _apply_equipped_pickaxe(definition: PickaxeDefinition) -> void:
	if definition == null:
		return
	mining_controller.set_equipped_pickaxe(definition)
	miner_rig.set_hammer_head_color(definition.hammer_head_color)
