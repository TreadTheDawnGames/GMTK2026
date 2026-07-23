class_name ShopBalance
extends RefCounted

## Holds spendable currency without depending on a specific collectible type.

signal amount_changed(amount: int)

var amount: int:
	get:
		return _amount

var _amount: int = 0


## Creates a balance that never starts below zero.
func _init(starting_amount: int = 0) -> void:
	_amount = maxi(0, starting_amount)


## Replaces the spendable amount.
func set_amount(value: int) -> void:
	var next_amount := maxi(0, value)
	if _amount == next_amount:
		return
	_amount = next_amount
	amount_changed.emit(_amount)


## Adds earned currency to the balance.
func add(value: int) -> void:
	if value <= 0:
		return
	set_amount(_amount + value)


## Reports whether a non-negative cost can be paid.
func can_afford(cost: int) -> bool:
	return cost >= 0 and _amount >= cost


## Spends currency only when the full cost is available.
func try_spend(cost: int) -> bool:
	if not can_afford(cost):
		return false
	set_amount(_amount - cost)
	return true
