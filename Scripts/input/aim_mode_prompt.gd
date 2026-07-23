class_name AimModePrompt
extends CanvasLayer

## Asks whether A/D should supplement mouse-directed mining.

signal mode_selected(keyboard_aim_enabled: bool)

@export var prompt_root: Control
@export var mouse_aim_button: Button
@export var keyboard_aim_button: Button

var _tree_was_paused: bool = false


## Pauses gameplay until the player chooses an aiming mode.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tree_was_paused = get_tree().paused
	get_tree().paused = true
	prompt_root.show()
	mouse_aim_button.pressed.connect(_choose_mouse_aim)
	keyboard_aim_button.pressed.connect(_choose_keyboard_aim)
	mouse_aim_button.grab_focus()


## Starts with right-click directional aiming.
func _choose_mouse_aim() -> void:
	_finish_selection(false)


## Adds held A/D directional aiming.
func _choose_keyboard_aim() -> void:
	_finish_selection(true)


## Closes the prompt and restores the previous pause state.
func _finish_selection(keyboard_aim_enabled: bool) -> void:
	prompt_root.hide()
	get_tree().paused = _tree_was_paused
	mode_selected.emit(keyboard_aim_enabled)
