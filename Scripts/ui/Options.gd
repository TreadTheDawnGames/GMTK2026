extends Control

@onready var tab_container: TabContainer = $TabContainer
@onready var v_sync_options: OptionButton = (
	$TabContainer/Panel/VBoxContainer/HBoxContainer2/Control/VSyncOptions
)
@onready var mute_bounce: CheckBox = %MuteBounce
@onready var master_volume: VolumeControl = %MasterVolume
@onready var music: VolumeControl = %Music
@onready var sfx: VolumeControl = %SFX
@onready var credits_button: Button = (
	$TabContainer/Panel/VBoxContainer/HBoxContainer/CreditsButton
)
@onready var back_button: Button = (
	$TabContainer/Panel/VBoxContainer/HBoxContainer/BackButton
)
@onready var return_to_settings_button: Button = (
	$TabContainer/PanelContainer/VBoxContainer/ReturnToSettings
)
@onready var _game_state: RunState = RunState.get_global(self)


## Loads options, connects their consumers, and pauses the game behind the menu.
func _ready() -> void:
	get_tree().paused = true
	tab_container.current_tab = 0
	if _game_state == null or _game_state.save_game == null:
		push_error("Options cannot load without an active SaveGame.")
		return
	_connect_controls()
	_load_controls_from_save(_game_state.save_game)
	mute_bounce.grab_focus()


## Copies every visible option back to the active save and closes the menu.
func _on_back_button_pressed() -> void:
	_copy_controls_to_save(_game_state.save_game)
	_game_state.save_game.apply_runtime_settings()
	_game_state.save_game.write_savegame()
	queue_free()
	get_tree().paused = false


## Shows credits within the same modal menu.
func _on_credits_button_pressed() -> void:
	tab_container.current_tab = 1
	return_to_settings_button.grab_focus()


## Returns to settings without discarding the edited control values.
func _on_return_to_settings_pressed() -> void:
	tab_container.current_tab = 0
	mute_bounce.grab_focus()


## Applies VSync immediately; Close persists the selected menu index.
func _on_v_sync_options_item_selected(index: int) -> void:
	SaveGame.apply_vsync_mode(index)


## Owns every authored child-signal subscription used by this screen.
func _connect_controls() -> void:
	if not v_sync_options.item_selected.is_connected(
		_on_v_sync_options_item_selected
	):
		v_sync_options.item_selected.connect(
			_on_v_sync_options_item_selected
		)
	if not credits_button.pressed.is_connected(
		_on_credits_button_pressed
	):
		credits_button.pressed.connect(_on_credits_button_pressed)
	if not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)
	if not return_to_settings_button.pressed.is_connected(
		_on_return_to_settings_pressed
	):
		return_to_settings_button.pressed.connect(
			_on_return_to_settings_pressed
		)


## Maps the saved domain values to their matching controls and audio buses.
func _load_controls_from_save(save_game: SaveGame) -> void:
	mute_bounce.set_pressed_no_signal(save_game.mute_bounce)
	v_sync_options.select(save_game.vsync_mode)
	master_volume.load_bus_setting(
		save_game.master_volume,
		save_game.master_mute
	)
	music.load_bus_setting(save_game.music_volume, save_game.music_mute)
	sfx.load_bus_setting(save_game.sfx_volume, save_game.sfx_mute)


## Maps controls back to the matching saved fields without crossing buses.
func _copy_controls_to_save(save_game: SaveGame) -> void:
	save_game.mute_bounce = mute_bounce.button_pressed
	save_game.vsync_mode = v_sync_options.selected
	save_game.master_volume = master_volume.slider.value
	save_game.master_mute = master_volume.check_box.button_pressed
	save_game.music_volume = music.slider.value
	save_game.music_mute = music.check_box.button_pressed
	save_game.sfx_volume = sfx.slider.value
	save_game.sfx_mute = sfx.check_box.button_pressed
