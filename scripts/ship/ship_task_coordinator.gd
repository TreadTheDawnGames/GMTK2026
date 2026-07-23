class_name ShipTaskCoordinator
extends Node
## Escalates every ship task's decay rate when an objective expires.

signal decay_multiplier_changed(multiplier: float, expired_objective: TaskObjective)

@export var objectives_root: Node
@export_range(1.0, 3.0, 0.05) var expiration_multiplier := 1.25
@export_range(1.0, 10.0, 0.25) var maximum_decay_multiplier := 4.0

var _objectives: Array[TaskObjective] = []
var _current_decay_multiplier := 1.0


func _ready() -> void:
	if objectives_root == null:
		push_error("ShipTaskCoordinator requires an objectives root.")
		return
	for descendant in objectives_root.find_children("*", "TaskObjective", true, false):
		var objective := descendant as TaskObjective
		if objective == null:
			continue
		_objectives.append(objective)
		objective.durability_expired.connect(_on_objective_expired)


func _on_objective_expired(expired_objective: TaskObjective) -> void:
	_current_decay_multiplier = minf(
		_current_decay_multiplier * expiration_multiplier,
		maximum_decay_multiplier
	)
	# Updating the expired objective is harmless while it is at zero and ensures
	# it inherits the current pressure if a later repair brings it back online.
	for objective in _objectives:
		objective.set_global_decay_multiplier(_current_decay_multiplier)
	decay_multiplier_changed.emit(_current_decay_multiplier, expired_objective)
