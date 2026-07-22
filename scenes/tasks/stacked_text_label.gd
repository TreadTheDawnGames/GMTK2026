extends Control
class_name TextTaskVisual

@onready var _bottom_label: RichTextLabel = $BottomLbl
@onready var _top_label: RichTextLabel = $TopLbl

var goal_text := "":
	set(value):
		goal_text = value
		_bottom_label.text = goal_text
		_top_label.text = goal_text


func set_successful_letters(letters_to_show: int) -> void:
	_top_label.visible_characters = letters_to_show
