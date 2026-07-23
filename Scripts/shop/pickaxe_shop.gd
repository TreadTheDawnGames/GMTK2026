class_name PickaxeShop
extends Control

## Presents authored pickaxe stock and resolves purchases against supplied run state.

signal shop_closed
signal purchase_requested(definition: PickaxeDefinition, cost: int)
signal purchase_result(
	definition: PickaxeDefinition,
	purchased: bool,
	remaining_balance: int
)
signal equip_requested(definition: PickaxeDefinition)
signal equip_result(definition: PickaxeDefinition, equipped: bool)

@export_category("Stock")
@export var stock: Array[PickaxeDefinition] = []
@export var starts_open: bool = false

@export_category("References")
@export var balance_label: Label
@export var item_list: ItemList
@export var name_label: Label
@export var description_label: Label
@export var stats_label: Label
@export var status_label: Label
@export var primary_button: Button
@export var close_button: Button

var _balance: ShopBalance
var _loadout: PickaxeLoadout
var _selected_index: int = 0


## Connects shop controls and applies the requested startup visibility.
func _ready() -> void:
	if not item_list.item_selected.is_connected(_on_item_selected):
		item_list.item_selected.connect(_on_item_selected)
	if not close_button.pressed.is_connected(_on_close_button_pressed):
		close_button.pressed.connect(_on_close_button_pressed)
	if not primary_button.pressed.is_connected(
		_on_primary_button_pressed
	):
		primary_button.pressed.connect(_on_primary_button_pressed)
	visible = starts_open
	_refresh()


## Supplies the wallet and equipment state used by this shop visit.
func configure(balance: ShopBalance, loadout: PickaxeLoadout) -> void:
	if _balance != null and _balance.amount_changed.is_connected(_on_balance_changed):
		_balance.amount_changed.disconnect(_on_balance_changed)
	if _loadout != null:
		if _loadout.inventory_changed.is_connected(_on_inventory_changed):
			_loadout.inventory_changed.disconnect(_on_inventory_changed)
		if _loadout.equipped_changed.is_connected(_on_equipped_changed):
			_loadout.equipped_changed.disconnect(_on_equipped_changed)

	_balance = balance
	_loadout = loadout

	if _balance != null:
		_balance.amount_changed.connect(_on_balance_changed)
	if _loadout != null:
		_loadout.inventory_changed.connect(_on_inventory_changed)
		_loadout.equipped_changed.connect(_on_equipped_changed)
	_refresh()


## Opens the shop and focuses the current item for keyboard or mouse use.
func open_shop() -> void:
	show()
	if item_list != null and item_list.item_count > 0:
		item_list.grab_focus()


## Closes the shop and notifies the encounter flow.
func close_shop() -> void:
	hide()
	shop_closed.emit()


## Selects the item whose details and action are displayed.
func _on_item_selected(index: int) -> void:
	if index < 0 or index >= stock.size():
		return
	_selected_index = index
	status_label.text = ""
	_refresh_details()


## Purchases an unowned item or equips an item already in the loadout.
func _on_primary_button_pressed() -> void:
	var definition := _selected_definition()
	if definition == null or _balance == null or _loadout == null:
		return
	if definition.id == &"":
		status_label.text = "This pickaxe is not configured."
		return

	if _loadout.owns(definition):
		equip_requested.emit(definition)
		var equipped := _loadout.equip(definition)
		equip_result.emit(definition, equipped)
		status_label.text = (
			"%s equipped." % definition.display_name
			if equipped
			else "%s could not be equipped." % definition.display_name
		)
		_refresh()
		return

	purchase_requested.emit(definition, definition.cost)
	var purchased := false
	if _balance.try_spend(definition.cost):
		purchased = _loadout.unlock(definition)
		if purchased:
			equip_requested.emit(definition)
			var equipped := _loadout.equip(definition)
			equip_result.emit(definition, equipped)
	purchase_result.emit(definition, purchased, _balance.amount)
	status_label.text = (
		"%s purchased and equipped." % definition.display_name
		if purchased
		else "Not enough balance."
	)
	_refresh()


## Closes the current shop visit.
func _on_close_button_pressed() -> void:
	close_shop()


## Rebuilds visible stock labels when wallet or equipment state changes.
func _refresh() -> void:
	if not _references_are_ready():
		return

	var previous_index := clampi(_selected_index, 0, maxi(0, stock.size() - 1))
	item_list.clear()
	for definition: PickaxeDefinition in stock:
		if definition == null:
			item_list.add_item("Invalid pickaxe")
			continue
		var suffix := ""
		if _loadout != null and _loadout.equipped == definition:
			suffix = " (Equipped)"
		elif _loadout != null and _loadout.owns(definition):
			suffix = " (Owned)"
		item_list.add_item("%s%s" % [definition.display_name, suffix])

	if item_list.item_count > 0:
		_selected_index = mini(previous_index, item_list.item_count - 1)
		item_list.select(_selected_index)
	balance_label.text = "Ore: %d" % (_balance.amount if _balance != null else 0)
	_refresh_details()


## Updates the description and primary action for the selected pickaxe.
func _refresh_details() -> void:
	var definition := _selected_definition()
	if definition == null:
		name_label.text = "No pickaxe selected"
		description_label.text = ""
		stats_label.text = ""
		primary_button.text = "Unavailable"
		primary_button.disabled = true
		return

	name_label.text = definition.display_name
	description_label.text = definition.description
	stats_label.text = (
		"Power x%.2f\nWidth x%.2f\nSwing speed x%.2f\nDebris x%.2f\n%s"
		% [
			definition.power_multiplier,
			definition.width_multiplier,
			definition.swing_speed_multiplier,
			definition.debris_multiplier,
			definition.get_special_effect_summary(),
		]
	)

	if _loadout != null and _loadout.equipped == definition:
		primary_button.text = "Equipped"
		primary_button.disabled = true
	elif _loadout != null and _loadout.owns(definition):
		primary_button.text = "Equip"
		primary_button.disabled = false
	else:
		primary_button.text = "Buy - %d" % definition.cost
		primary_button.disabled = (
			_balance == null
			or _loadout == null
			or not _balance.can_afford(definition.cost)
		)


## Returns the selected authored definition when the index is valid.
func _selected_definition() -> PickaxeDefinition:
	if _selected_index < 0 or _selected_index >= stock.size():
		return null
	return stock[_selected_index]


## Confirms the exported scene references needed to present the shop.
func _references_are_ready() -> bool:
	return (
		balance_label != null
		and item_list != null
		and name_label != null
		and description_label != null
		and stats_label != null
		and status_label != null
		and primary_button != null
		and close_button != null
	)


## Refreshes prices and affordability after the balance changes.
func _on_balance_changed(_amount: int) -> void:
	_refresh()


## Refreshes ownership labels after a purchase.
func _on_inventory_changed(_owned_pickaxes: Array[PickaxeDefinition]) -> void:
	_refresh()


## Refreshes the equipped marker after the active pickaxe changes.
func _on_equipped_changed(_definition: PickaxeDefinition) -> void:
	_refresh()
