class_name SwitchMatchTask
extends RepairTask
## Completes when all four switches match their displayed target states.

@onready var _switches: Array[CheckButton] = [
	%SwitchOne,
	%SwitchTwo,
	%SwitchThree,
	%SwitchFour,
]
@onready var _target_labels: Array[Label] = [
	%TargetOne,
	%TargetTwo,
	%TargetThree,
	%TargetFour,
]

var _target_states: Array[bool] = []


func _ready() -> void:
	super._ready()
	for index in range(_switches.size()):
		_switches[index].toggled.connect(_on_switch_toggled.bind(index))


func _task_ready() -> void:
	_target_states.clear()
	for index in range(_switches.size()):
		var target_state := randf() >= 0.5
		_target_states.append(target_state)
		_switches[index].button_pressed = randf() >= 0.5
		_update_switch_text(index)
	if _all_switches_match():
		_switches[0].button_pressed = not _target_states[0]
		_update_switch_text(0)


func _on_switch_toggled(_is_pressed: bool, index: int) -> void:
	_update_switch_text(index)
	if not complete and _all_switches_match():
		_succeed()


func _update_switch_text(index: int) -> void:
	_target_labels[index].text = "TARGET: %s" % ("ON" if _target_states[index] else "OFF")
	_switches[index].text = "ON" if _switches[index].button_pressed else "OFF"


func _all_switches_match() -> bool:
	for index in range(_switches.size()):
		if _switches[index].button_pressed != _target_states[index]:
			return false
	return true
