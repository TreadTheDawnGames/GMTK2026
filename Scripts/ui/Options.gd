extends Control
class_name OptionsMenu

## How it works:
## - Its opener supplies the active SaveGame before this node enters the tree.
## - Controls edit that resource and apply it when the menu closes.
## - Owned state is limited to the currently displayed option values.
## - The invariant is that this screen never locates global run state itself.

@onready var v_sync_options: OptionButton = %VSyncOptions
@onready var mute_bounce: CheckBox = %MuteBounce
@onready var reduce_motion: CheckBox = %ReduceMotion
@onready var master_volume: VolumeControl = %MasterVolume
@onready var music: VolumeControl = %Music
@onready var sfx: VolumeControl = %SFX
@onready var back_button: Button = %BackButton
var _save_game: SaveGame


## Supplies the save resource owned by the current run.
func set_save_game(save_game: SaveGame) -> void:
	_save_game = save_game


## Loads options, connects their consumers, and pauses the game behind the menu.
func _ready() -> void:
	get_tree().paused = true
	if _save_game == null:
		push_error("Options cannot load without an active SaveGame.")
		return
	_connect_controls()
	_load_controls_from_save(_save_game)
	mute_bounce.grab_focus()


## Copies every visible option back to the active save and closes the menu.
func _on_back_button_pressed() -> void:
	if _save_game == null:
		push_error("Options cannot save without an active SaveGame.")
		return
	save_settings()
	queue_free()
	get_tree().paused = false

## Applies VSync immediately; Close persists the selected menu index.
func _on_v_sync_options_item_selected(index: int) -> void:
	SaveGame.apply_vsync_mode(index)


## Owns every authored child-signal subscription used by this screen.
func _connect_controls() -> void:
	if not v_sync_options:
		v_sync_options = %VSyncOptions
	if not back_button:
		back_button = %BackButton

	if not v_sync_options.item_selected.is_connected(
		_on_v_sync_options_item_selected
	):
		v_sync_options.item_selected.connect(
			_on_v_sync_options_item_selected
		)
	if not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)


## Maps the saved domain values to their matching controls and audio buses.
func _load_controls_from_save(save_game: SaveGame) -> void:
	mute_bounce.set_pressed_no_signal(save_game.mute_bounce)
	reduce_motion.set_pressed_no_signal(save_game.reduce_motion)
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
	save_game.reduce_motion = reduce_motion.button_pressed
	save_game.vsync_mode = v_sync_options.selected
	save_game.master_volume = master_volume.slider.value
	save_game.master_mute = master_volume.check_box.button_pressed
	save_game.music_volume = music.slider.value
	save_game.music_mute = music.check_box.button_pressed
	save_game.sfx_volume = sfx.slider.value
	save_game.sfx_mute = sfx.check_box.button_pressed

func _exit_tree() -> void:
	if _save_game != null:
		save_settings()

func save_settings() -> void:
	_copy_controls_to_save(_save_game)
	_save_game.apply_runtime_settings()
	_save_game.write_savegame()
