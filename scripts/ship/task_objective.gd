class_name TaskObjective
extends Area2D
## A placeable ship objective that opens an authored repair-task scene.

signal task_opened(objective: TaskObjective)
signal task_completed(objective: TaskObjective, repair_amount: float)
signal task_cancelled(objective: TaskObjective)

@export var task_scene: PackedScene = preload("res://scenes/tasks/typing_task.tscn")

@onready var damage: SystemDamage = %Damage
@onready var artwork: Sprite2D = %Artwork
@onready var task_overlay: CanvasLayer = %TaskOverlay

var _active_task: RepairTask
var _next_task_scene : PackedScene

func _input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	open_task()


func open_task() -> void:
	if _active_task != null:
		_active_task.show()
		return
	
		
	var task := task_scene.instantiate() as Control
	if task == null:
		push_error("TaskObjective task scene root must be a Control.")
		return
	if not task.has_signal("task_exit"):
		push_error("TaskObjective task scene must define a task_exit signal.")
		task.queue_free()
		return
	_active_task = task
	task_scene = TaskPicker.get_task(_active_task)
	
	_active_task.task_exit.connect(_on_task_exit)
	task_overlay.add_child(_active_task)
	task_opened.emit(self)
	

func _on_task_exit(repair_amount: float) -> void:
	if _active_task == null:
		return
	_active_task.hide()
	if repair_amount < 0.0:
		task_cancelled.emit(self)
		return
	damage.repair_damage(repair_amount)
	task_completed.emit(self, repair_amount)
	_active_task.queue_free()
	_active_task = null


func _exit_tree() -> void:
	pass
