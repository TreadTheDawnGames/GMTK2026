extends Control
class_name RepairTask
## A task used to repair damage systems
@onready var exit_button: Button = %ExitButton

signal task_exit(repair_amount : float)

const DEFAULT_REPAIR_SECONDS := 15.0

@export var repair_value: float = DEFAULT_REPAIR_SECONDS

var complete : bool = false

func _ready():
	_task_ready()
	exit_button.pressed.connect(_exit)

## Called when the task is opened
func _task_ready():
	pass

## Call this when a task is succeeded. Emits the repair value for the task.
func _succeed():
	complete = true
	task_exit.emit(repair_value)

## Call this when a task is exited (not succeeded). Emits -1 as the repair value for the task.
func _exit():
	task_exit.emit(-1)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event : InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == Key.KEY_ESCAPE:
			_exit()
			get_viewport().set_input_as_handled()
