class_name TaskObjective
extends Area2D
## A placeable ship objective that opens an authored repair-task scene.

signal task_opened(objective: TaskObjective)
signal task_completed(objective: TaskObjective, repair_amount: float)
signal task_cancelled(objective: TaskObjective)

@export var task_scene: PackedScene = preload("res://scenes/tasks/typing_task.tscn")
@export var disable_after_completion := true

@onready var artwork: Sprite2D = %Artwork
@onready var task_overlay: CanvasLayer = %TaskOverlay

var is_completed := false
var _active_task: Control
var _was_tree_paused := false


func _input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	open_task()


func open_task() -> void:
	if _active_task != null or (is_completed and disable_after_completion):
		return
	if task_scene == null:
		push_error("TaskObjective requires a task scene.")
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
	_active_task.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_active_task.connect("task_exit", _on_task_exit)
	task_overlay.add_child(_active_task)
	_was_tree_paused = get_tree().paused
	get_tree().paused = true
	task_opened.emit(self)


func _on_task_exit(repair_amount: float) -> void:
	if _active_task == null:
		return
	_active_task.queue_free()
	_active_task = null
	get_tree().paused = _was_tree_paused
	if repair_amount < 0.0:
		task_cancelled.emit(self)
		return
	is_completed = true
	if disable_after_completion:
		input_pickable = false
		artwork.modulate = Color(0.35, 0.65, 0.35, 1.0)
	task_completed.emit(self, repair_amount)


func _exit_tree() -> void:
	if _active_task != null and get_tree() != null:
		get_tree().paused = _was_tree_paused
