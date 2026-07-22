class_name TaskObjective
extends Area2D
## A placeable ship objective that opens an authored repair-task scene.

signal task_opened(objective: TaskObjective)
signal task_completed(objective: TaskObjective, repair_amount: float)
signal task_cancelled(objective: TaskObjective)

@export var task_scene: PackedScene = preload("res://scenes/tasks/typing_task.tscn")
## Durability decay multiplier while one or more crew members occupy this room.
@export_range(0.0, 1.0, 0.05) var crew_present_decay_multiplier := 0.35

@onready var damage: SystemDamage = %Damage
@onready var artwork: Sprite2D = %Artwork
@onready var task_overlay: CanvasLayer = %TaskOverlay
@onready var _task_picker: Variant = get_node("/root/TaskPicker")

var _active_task: RepairTask
var _room: ShipSection
var _last_task_scene: PackedScene


func _ready() -> void:
	var ancestor := get_parent()
	while ancestor != null and not ancestor is ShipSection:
		ancestor = ancestor.get_parent()
	_room = ancestor as ShipSection


func _physics_process(_delta: float) -> void:
	damage.set_decay_rate_scale(
		crew_present_decay_multiplier if has_crew_in_room() else 1.0
	)


func _input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	open_task()


func open_task() -> void:
	# Reuse an unfinished task instead of creating stacked modal overlays.
	if _active_task != null:
		_active_task.show()
		return
	var selected_task_scene: PackedScene = _task_picker.get_task(_last_task_scene)
	if selected_task_scene == null:
		selected_task_scene = task_scene
	if selected_task_scene == null:
		push_error("TaskObjective requires a task scene.")
		return
	var task := selected_task_scene.instantiate() as RepairTask
	if task == null:
		push_error("TaskObjective task scene root must be a RepairTask.")
		return
	if not task.has_signal("task_exit"):
		push_error("TaskObjective task scene must define a task_exit signal.")
		task.queue_free()
		return
	_last_task_scene = selected_task_scene
	_active_task = task
	_active_task.connect("task_exit", _on_task_exit)
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


func has_crew_in_room() -> bool:
	if _room == null:
		return false
	for node in get_tree().get_nodes_in_group("crew_members"):
		var crew_member := node as CrewMember
		if crew_member != null and _room.contains_world_point(crew_member.global_position):
			return true
	return false


func has_active_task() -> bool:
	return _active_task != null
