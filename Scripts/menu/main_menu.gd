class_name GameMainMenu
extends Control

## How it works:
## - The menu is an overlay inside the live mining scene, not a scene of its
##   own, so the world behind it is the game already staged at the surface.
## - Start therefore never loads or changes a scene. It asks the composition
##   root to clear the run, fades off, and starts the opening sequence.
## - Owned state: the staged reveal's completion and the one-shot start guard.
## The invariant is that this node only ever writes to its own interface.

signal start_requested

const OptionsMenuType := preload("res://Scripts/ui/Options.gd")

@export_category("References")
@export var title_group: CanvasItem
@export var subtitle_group: CanvasItem
@export var button_group: CanvasItem
@export var start_button: Button
@export var options_button: Button
@export var exit_button: Button
@export var exit_confirmation: ConfirmationDialog
@export var status_label: Label
@export var options_scene: PackedScene

@export_category("Intro")
@export_range(0.0, 3.0, 0.1) var section_fade_seconds: float = 0.8

@export_category("Start Transition")
## The interface leaves the shot over this long. The world behind it is already
## the game, so nothing fades to black: only the menu goes, and the bus drives
## into the frame it leaves behind.
@export_range(0.0, 3.0, 0.05) var start_fade_seconds: float = 0.35

var _intro_tween: Tween
var _start_tween: Tween
var _intro_complete: bool = false
var _is_starting: bool = false
var _save_game: SaveGame


## Supplies the save resource passed to settings screens opened by this menu.
func set_save_game(save_game: SaveGame) -> void:
	_save_game = save_game


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
	if not options_button.pressed.is_connected(_on_options_pressed):
		options_button.pressed.connect(_on_options_pressed)
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


## Clears the run, takes the interface off the shot, and asks for the opening.
func _on_start_button_pressed() -> void:
	if _is_starting:
		return

	_is_starting = true
	start_button.disabled = true
	options_button.disabled = true
	exit_button.disabled = true
	status_label.text = ""
	# The shot is asked for first and the interface leaves over the top of it,
	# so the bus is already driving in while the buttons dissolve. Fading out
	# first and asking afterwards leaves a beat of empty world in between,
	# which is the join that reads as two separate moments instead of one.
	start_requested.emit()
	# Nothing here owns the shot from this point, so it stops taking input as
	# well as clicks even while it is still visible.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_unhandled_input(false)
	await _fade_interface_out()
	queue_free()

	


## Takes every menu element off the live shot without touching the world.
func _fade_interface_out() -> void:
	if start_fade_seconds <= 0.0:
		modulate.a = 0.0
		return
	_start_tween = create_tween()
	_start_tween.tween_property(
		self,
		"modulate:a",
		0.0,
		start_fade_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _start_tween.finished


## Opens the authored settings screen over the menu.
func _on_options_pressed() -> void:
	var options := options_scene.instantiate() as OptionsMenuType
	if options == null:
		push_error(
			"The configured options scene must instantiate an OptionsMenu."
		)
		return
	options.set_save_game(_save_game)
	options.tree_exited.connect(
		options_button.grab_focus,
		CONNECT_ONE_SHOT
	)
	add_child(options)


## Asks for confirmation before closing a desktop build.
func _on_exit_button_pressed() -> void:
	exit_confirmation.popup_centered()


## Closes the application after exit confirmation.
func _on_exit_confirmation_confirmed() -> void:
	get_tree().quit()
