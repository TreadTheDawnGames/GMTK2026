extends Task

@export var path_to_task_words : String = "res://resources/word_library.txt"

func _task_ready() -> void:
	print(_pick_word())
	pass # Replace with function body.

func _pick_word() -> String:
	var file_contents : String = FileAccess.open(path_to_task_words, FileAccess.READ).get_as_text()
	var words := file_contents.split("\n")
	var valid_words: Array[String] = []
	for word in words:
		var stripped_word := word.strip_edges()
		if not stripped_word.is_empty() and not stripped_word.begins_with("#"):
			valid_words.append(stripped_word)
	return valid_words.pick_random() if not valid_words.is_empty() else ""
