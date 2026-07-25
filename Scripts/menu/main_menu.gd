class_name GameMainMenu
extends Control

## Presents the opening menu and enters the current mining scene.

@export_file("*.tscn") var game_scene_path: String

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
@export var start_fade_overlay: ColorRect

@export_category("Intro")
@export_range(0.0, 3.0, 0.1) var section_fade_seconds: float = 0.8

@export_category("Start Transition")
## The menu fades into black here; the mining scene starts fully covered and
## splits that same black apart from the middle, so the handover reads as one
## continuous shot.
@export_range(0.0, 3.0, 0.05) var start_fade_seconds: float = 0.25

var _intro_tween: Tween
var _start_tween: Tween
var _intro_complete: bool = false
var _is_starting: bool = false
var _game_scene_load_requested: bool = false
var _loaded_game_scene: PackedScene


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
	if start_fade_overlay != null:
		start_fade_overlay.modulate.a = 0.0
		start_fade_overlay.hide()
	if OS.has_feature("web"):
		exit_button.hide()
	_play_intro()
	_request_game_scene_load.call_deferred()


## Polls the menu-time load without blocking a rendered frame.
func _process(_delta: float) -> void:
	if not _game_scene_load_requested or _loaded_game_scene != null:
		return
	var load_status := ResourceLoader.load_threaded_get_status(game_scene_path)
	if load_status == ResourceLoader.THREAD_LOAD_LOADED:
		_loaded_game_scene = (
			ResourceLoader.load_threaded_get(game_scene_path) as PackedScene
		)
		set_process(false)
	elif (
		load_status == ResourceLoader.THREAD_LOAD_FAILED
		or load_status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	):
		_game_scene_load_requested = false
		set_process(false)


## Warms the large gameplay scene while the player is reading the menu.
func _request_game_scene_load() -> void:
	if game_scene_path.is_empty() or _game_scene_load_requested:
		return
	var request_error := ResourceLoader.load_threaded_request(game_scene_path)
	if request_error != OK:
		return
	_game_scene_load_requested = true
	set_process(true)


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


## Fades the menu into black, then hands that black to the mining scene.
func _on_start_button_pressed() -> void:
	if _is_starting:
		return
	_is_starting = true
	start_button.disabled = true
	options_button.disabled = true
	exit_button.disabled = true
	status_label.text = ""
	# Clear the persistent run before the fade, so the reset never depends on
	# how long the transition takes.
	var run_state := RunState.get_global(self)
	if run_state != null:
		run_state.reset_run()
	await _fade_to_black()
	await _open_game_scene()


## Covers the menu so the mining scene can open out of the same black.
func _fade_to_black() -> void:
	if start_fade_overlay == null or start_fade_seconds <= 0.0:
		return
	start_fade_overlay.modulate.a = 0.0
	start_fade_overlay.show()
	_start_tween = create_tween()
	_start_tween.tween_property(
		start_fade_overlay,
		"modulate:a",
		1.0,
		start_fade_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _start_tween.finished


## Replaces the menu with the mining game.
func _open_game_scene() -> void:
	var run_state := RunState.get_global(self)
	if run_state != null:
		run_state.reset_run()
	while _game_scene_load_requested and _loaded_game_scene == null:
		var load_status := ResourceLoader.load_threaded_get_status(
			game_scene_path
		)
		if load_status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			break
		await get_tree().process_frame
	var change_error := ERR_CANT_OPEN
	if _loaded_game_scene != null:
		change_error = get_tree().change_scene_to_packed(_loaded_game_scene)
	else:
		change_error = get_tree().change_scene_to_file(game_scene_path)
	if change_error == OK:
		return
	_is_starting = false
	start_button.disabled = false
	options_button.disabled = false
	exit_button.disabled = false
	if start_fade_overlay != null:
		start_fade_overlay.modulate.a = 0.0
		start_fade_overlay.hide()
	status_label.text = "The game scene could not be opened."
	push_error(
		"Main menu could not open '%s': error %d."
		% [game_scene_path, change_error]
	)

## Opens the authored settings screen over the menu.
func _on_options_pressed() -> void:
	var options := options_scene.instantiate() as Control
	if options == null:
		push_error("The configured options scene must instantiate a Control.")
		return
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
