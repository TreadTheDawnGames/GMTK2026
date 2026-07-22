extends Node

@export var _all_tasks : Array[PackedScene]

func get_task(not_task : RepairTask = null) -> PackedScene:
	var picked_task : PackedScene = _all_tasks.pick_random()
	var rerolls : int = 5
	if not_task:
		while picked_task.get_script() != not_task.get_script() and rerolls > 0:
			picked_task = _all_tasks.pick_random()
			rerolls -= 1
	return picked_task
