class_name DepartureChoice
extends CanvasLayer

## Presents the one story choice between leaving and continuing alone.

signal keep_digging_selected

const MAIN_MENU_SCENE := "res://Scenes/menu/main_menu.tscn"

@export var choice_root: Control
@export var ending_root: Control
@export var leave_button: Button
@export var keep_digging_button: Button
@export var return_to_title_button: Button


## Connects the three fixed actions and hides the overlay until requested.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not leave_button.pressed.is_connected(_on_leave_pressed):
		leave_button.pressed.connect(_on_leave_pressed)
	if not keep_digging_button.pressed.is_connected(
		_on_keep_digging_pressed
	):
		keep_digging_button.pressed.connect(_on_keep_digging_pressed)
	if not return_to_title_button.pressed.is_connected(
		_on_return_to_title_pressed
	):
		return_to_title_button.pressed.connect(
			_on_return_to_title_pressed
		)
	choice_root.hide()
	ending_root.hide()


## Opens the decision after the final warm-act conversation.
func show_choice() -> void:
	ending_root.hide()
	choice_root.show()
	keep_digging_button.grab_focus()


## Ends the short route with a complete closing message.
func _on_leave_pressed() -> void:
	choice_root.hide()
	ending_root.show()
	return_to_title_button.grab_focus()


## Closes the choice and lets the solitary descent begin.
func _on_keep_digging_pressed() -> void:
	choice_root.hide()
	keep_digging_selected.emit()


## Returns the completed short route to the main menu.
func _on_return_to_title_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
