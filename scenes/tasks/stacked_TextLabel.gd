extends Control
class_name TextTaskVisual
@onready var bottom_lbl: RichTextLabel = $BottomLbl
@onready var top_lbl: RichTextLabel = $TopLbl

var goal_text : String = "" :
	set(value):
		goal_text = value
		bottom_lbl.text = goal_text
		top_lbl.text = goal_text

func set_successful_letters(letters_to_show : int):
	top_lbl.visible_characters = letters_to_show
