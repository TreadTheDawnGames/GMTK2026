extends Control
class_name RepairTask
## A task used to repair damage systems
@onready var exit_button: Button = %ExitButton
@onready var task_header: Panel = %TaskHeader

signal task_exit(repair_amount : float)

const DEFAULT_REPAIR_SECONDS := 15.0

@export var repair_value: float = DEFAULT_REPAIR_SECONDS

var complete : bool = false

func _ready():
	_task_ready()
	exit_button.pressed.connect(_exit)
	
	task_header.mouse_entered.connect(func(): _hovered = true)
	task_header.mouse_exited.connect(func(): _hovered = false)

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

var grabbed : bool
var _hovered : bool
var _lastMousePos : Vector2
var _grabbedOffset : Vector2

func _process(_delta : float):
	if(_hovered):
		if(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not grabbed):
				_grabbedOffset = global_position - get_global_mouse_position()
				grabbed = true
				
		elif(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and grabbed):
			grabbed = false
		_lastMousePos = get_global_mouse_position()

	if(grabbed):
		global_position = clamp(get_global_mouse_position() + size*0.5, get_viewport_rect().size, get_viewport_rect().size - (size*0.5))


		#global_position = clamp(get_global_mouse_position() + _grabbedOffset, Vector2.ZERO, get_viewport_rect().size)
