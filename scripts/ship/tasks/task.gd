extends Control
class_name RepairTask
## A task used to repair damage systems
@onready var exit_button: Button = $PanelContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/ExitButton

signal task_exit(repair_amount : float)

@export var repair_value : float = 1.0

var complete : bool = false

func _ready():
	_task_ready()
	exit_button.pressed.connect(_exit)

## Called when the task is opened
func _task_ready():
	pass

## Call this when a task is succeeded. Emits the repair value for the task.
func _succeed():
	task_exit.emit(repair_value)
	complete = true

## Call this when a task is exited (not succeeded). Emits -1 as the repair value for the task.
func _exit():
	task_exit.emit(-1)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event : InputEventKey = event as InputEventKey
		if key_event.keycode == Key.KEY_ESCAPE:
			_exit()
