extends Node
## Selects a playable task scene for ship-room objectives.

@export var task_scenes: Array[PackedScene] = [
	preload("res://scenes/tasks/typing_task.tscn"),
]


func pick_scene() -> PackedScene:
	var available_tasks: Array[PackedScene] = []
	for task_scene in task_scenes:
		if task_scene != null:
			available_tasks.append(task_scene)
	return available_tasks.pick_random() if not available_tasks.is_empty() else null
