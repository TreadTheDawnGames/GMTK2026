extends Task

@export var path_to_task_words : String = "res://Resources/WordLibrary.txt"

func _task_ready() -> void:
	print(_pick_word())
	pass # Replace with function body.

func _pick_word() -> String:
	var file_contents : String = FileAccess.open(path_to_task_words, FileAccess.READ).get_as_text()
	var words : Array[String] = file_contents.split("\n")
	var chosen_word : String = ""
	while not chosen_word.contains("#") and chosen_word.length() > 0:
		chosen_word = words.pick_random()
	return chosen_word
