extends Node
## Selects a playable task scene for ship-room objectives.

@export var task_scenes: Array[PackedScene] = []


func get_task(excluded_scene: PackedScene = null) -> PackedScene:
	var available_tasks: Array[PackedScene] = []
	for task_scene in task_scenes:
		if task_scene != null and (task_scene != excluded_scene or task_scenes.size() == 1):
			available_tasks.append(task_scene)
	return available_tasks.pick_random() if not available_tasks.is_empty() else null
