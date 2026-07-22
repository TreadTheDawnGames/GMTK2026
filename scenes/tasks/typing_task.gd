extends "res://scripts/task.gd"
@export var path_to_task_words : String = "res://resources/word_library.txt"

@onready var text_area: TextTaskVisual = %TextArea

@export var total_words_to_type : int = 3
@export var words_typed : int = 0

var goal_word : String = ""
var num_correct_letters : int = 0

func _task_ready() -> void:
	words_typed = 0
	goal_word = ""
	set_goal_word()
	pass # Replace with function body.

func set_goal_word():
	goal_word = _pick_word().to_upper()
	text_area.goal_text = goal_word
	num_correct_letters = 0
	update_visual()
	pass

func _pick_word() -> String:
	var file_contents : String = FileAccess.open(path_to_task_words, FileAccess.READ).get_as_text().to_upper()
	var words := file_contents.split("\n")
	var valid_words: Array[String] = []
	for word in words:
		var stripped_word := word.strip_edges()
		if not stripped_word.is_empty() and not stripped_word.begins_with("#"):
			valid_words.append(stripped_word)
	return valid_words.pick_random() if not valid_words.is_empty() else ""

func submit_letter(letter : String) -> bool:
	if letter.length() > 1:
		return false
	
	if goal_word[num_correct_letters] == letter:
		update_visual()
		return true
	return false

func update_visual():
	text_area.set_successful_letters(num_correct_letters)
	if num_correct_letters != goal_word.length():
		return
	words_typed += 1
	if words_typed < total_words_to_type:
		set_goal_word()
	else:
		_succeed()
		

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var keyvent : InputEventKey = event as InputEventKey
		if not keyvent.pressed:
			return
		if submit_letter(OS.get_keycode_string(keyvent.keycode)):
			num_correct_letters += 1
			update_visual()
		
		
		pass
	pass
