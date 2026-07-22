extends Control
class_name Task
## A task used to repair damage systems

signal task_exit(repair_amount : float)

@export var repair_value : float = 1.0

func _ready():
	_task_ready()

## Called when the task is opened
func _task_ready():
	pass

## Call this when a task is succeeded. Emits the repair value for the task.
func _task_succeeded():
	task_exit.emit(repair_value)

## Call this when a task is exited (not succeeded). Emits -1 as the repair value for the task.
func _task_exited():
	task_exit.emit(-1)
