class_name GameMainMenu
extends Control

## Presents the opening menu and enters the current mining scene.

@export_file("*.tscn") var game_scene_path: String

@export_category("References")
@export var title_group: CanvasItem
@export var subtitle_group: CanvasItem
@export var button_group: CanvasItem
@export var start_button: Button
@export var exit_button: Button
@export var exit_confirmation: ConfirmationDialog
@export var status_label: Label

@export_category("Intro")
@export_range(0.0, 3.0, 0.1) var section_fade_seconds: float = 0.8

var _intro_tween: Tween
var _intro_complete: bool = false


## Connects menu actions and starts the staged interface reveal.
func _ready() -> void:
	if not start_button.pressed.is_connected(
		_on_start_button_pressed
	):
		start_button.pressed.connect(_on_start_button_pressed)
	if not exit_button.pressed.is_connected(
		_on_exit_button_pressed
	):
		exit_button.pressed.connect(_on_exit_button_pressed)
	if not exit_confirmation.confirmed.is_connected(
		_on_exit_confirmation_confirmed
	):
		exit_confirmation.confirmed.connect(
			_on_exit_confirmation_confirmed
		)
	title_group.modulate.a = 0.0
	subtitle_group.modulate.a = 0.0
	button_group.modulate.a = 0.0
	start_button.disabled = true
	if OS.has_feature("web"):
		exit_button.hide()
	_play_intro()


## Lets any deliberate input skip the remaining menu reveal.
func _unhandled_input(event: InputEvent) -> void:
	if _intro_complete or not event.is_pressed():
		return
	get_viewport().set_input_as_handled()
	_finish_intro()


## Fades each menu section in using the archived menu's cadence.
func _play_intro() -> void:
	_intro_tween = create_tween()
	_intro_tween.set_parallel(true)
	_intro_tween.tween_property(
		title_group,
		"modulate:a",
		1.0,
		section_fade_seconds
	)
	_intro_tween.tween_property(
		subtitle_group,
		"modulate:a",
		1.0,
		section_fade_seconds
	).set_delay(section_fade_seconds)
	_intro_tween.tween_property(
		button_group,
		"modulate:a",
		1.0,
		section_fade_seconds
	).set_delay(section_fade_seconds * 2.0)
	_intro_tween.finished.connect(_finish_intro)


## Shows the complete menu and enables its default action.
func _finish_intro() -> void:
	if _intro_complete:
		return
	_intro_complete = true
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	title_group.modulate.a = 1.0
	subtitle_group.modulate.a = 1.0
	button_group.modulate.a = 1.0
	start_button.disabled = false
	start_button.grab_focus()


## Replaces the menu with the mining game.
func _on_start_button_pressed() -> void:
	start_button.disabled = true
	status_label.text = ""
	var change_error := get_tree().change_scene_to_file(game_scene_path)
	if change_error == OK:
		return
	start_button.disabled = false
	status_label.text = "The game scene could not be opened."
	push_error(
		"Main menu could not open '%s': error %d."
		% [game_scene_path, change_error]
	)


## Asks for confirmation before closing a desktop build.
func _on_exit_button_pressed() -> void:
	exit_confirmation.popup_centered()


## Closes the application after exit confirmation.
func _on_exit_confirmation_confirmed() -> void:
	get_tree().quit()
