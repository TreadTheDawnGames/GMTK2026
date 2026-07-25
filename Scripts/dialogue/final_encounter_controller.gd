class_name FinalEncounterController
extends CanvasLayer

## How it works:
## - The bottom encounter keeps the shared cinematic gate and frame open.
## - This overlay supplies the production consumer for the final encounter.
## - Authored UI closes the run without reopening mining at maximum depth.
## - Returning to title resets the global run before the scene changes.
## The invariant is that reaching the thief always has a visible endpoint.

const MAIN_MENU_SCENE := "res://Scenes/menu/main_menu.tscn"

@export var final_encounter_id: StringName = &"thief_finale"
@export var dialogue_director: DialogueDirector
@export var ending_root: Control
@export var return_to_title_button: Button

var _is_finale_visible: bool = false


## Connects the authored terminal action and hides it before the thief.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ending_root.hide()
	if not return_to_title_button.pressed.is_connected(
		_on_return_to_title_pressed
	):
		return_to_title_button.pressed.connect(
			_on_return_to_title_pressed
		)


## Frames the thief and reveals the terminal authored message.
func show_finale(encounter_id: StringName) -> void:
	if (
		_is_finale_visible
		or encounter_id != final_encounter_id
		or dialogue_director == null
	):
		return
	_is_finale_visible = true
	dialogue_director.open_cinematic_frame()
	await dialogue_director.wait_until_frame_open()
	ending_root.show()
	return_to_title_button.grab_focus()


## Starts the next run from a clean autoload state.
func _on_return_to_title_pressed() -> void:
	var run_state := RunState.get_global(self)
	if run_state != null:
		run_state.reset_run()
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
