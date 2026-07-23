class_name ShipTaskCoordinator
extends Node
## Owns ship-wide task decay escalation from objective failures and the global clock.

signal decay_multiplier_changed(multiplier: float, expired_objective: TaskObjective)

@export var objectives_root: Node
@export_range(1.0, 3.0, 0.05) var expiration_multiplier := 1.25
@export_range(1.0, 600.0, 1.0) var global_timer_interval_seconds := 30.0
@export_range(1.0, 3.0, 0.05) var global_timer_decay_multiplier := 1.25
@export_range(1.0, 10.0, 0.25) var maximum_decay_multiplier := 4.0

var _objectives: Array[TaskObjective] = []
var _current_decay_multiplier := 1.0
var _global_timer: Timer


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

	_global_timer = Timer.new()
	_global_timer.name = "GlobalEscalationTimer"
	_global_timer.wait_time = global_timer_interval_seconds
	_global_timer.timeout.connect(_on_global_timer_timeout)
	add_child(_global_timer)
	_global_timer.start()


func _on_objective_expired(expired_objective: TaskObjective) -> void:
	_apply_decay_multiplier_step(expiration_multiplier, expired_objective)


func _on_global_timer_timeout() -> void:
	_apply_decay_multiplier_step(global_timer_decay_multiplier, null)


func _apply_decay_multiplier_step(
	step_multiplier: float,
	expired_objective: TaskObjective
) -> void:
	_current_decay_multiplier = minf(
		_current_decay_multiplier * step_multiplier,
		maximum_decay_multiplier
	)
	for objective in _objectives:
		objective.set_global_decay_multiplier(_current_decay_multiplier)
	decay_multiplier_changed.emit(_current_decay_multiplier, expired_objective)


func get_seconds_until_global_escalation() -> float:
	if _global_timer == null or _global_timer.is_stopped():
		return global_timer_interval_seconds
	return _global_timer.time_left


func get_current_decay_multiplier() -> float:
	return _current_decay_multiplier
