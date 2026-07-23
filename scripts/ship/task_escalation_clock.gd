class_name TaskEscalationClock
extends PanelContainer
## Displays the ship coordinator's global task escalation countdown.

@export var coordinator: ShipTaskCoordinator

@onready var _countdown_label: Label = %CountdownLabel


func _ready() -> void:
	if coordinator == null:
		push_error("TaskEscalationClock requires a ShipTaskCoordinator.")
		set_process(false)


func _process(_delta: float) -> void:
	var total_seconds := maxi(ceili(coordinator.get_seconds_until_global_escalation()), 0)
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	_countdown_label.text = "TASK SPEEDUP IN %02d:%02d\nDECAY SPEED %.2fx" % [
		minutes,
		seconds,
		coordinator.get_current_decay_multiplier(),
	]
