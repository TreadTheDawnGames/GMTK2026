extends Node
## Selects a playable task scene for ship-room objectives.

@export var task_scenes: Array[PackedScene] = [
	preload("res://scenes/tasks/typing_task.tscn"),
]

@export var _all_tasks : Array[PackedScene]

func get_task(not_task : RepairTask = null) -> PackedScene:
	var picked_task : PackedScene = _all_tasks.pick_random()
	var rerolls : int = 5
	if not_task:
		while picked_task.get_script() != not_task.get_script() and rerolls > 0:
			picked_task = _all_tasks.pick_random()
			rerolls -= 1
			print("rerolled")
	return picked_task
