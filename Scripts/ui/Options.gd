extends Control
@onready var player_audio_handler: PlayerAudioHandler = $PlayerAudioHandler
@onready var tab_container: TabContainer = $TabContainer
@onready var v_sync_options: OptionButton = $TabContainer/Panel/VBoxContainer/HBoxContainer2/Control/VSyncOptions
@onready var mute_bounce: CheckBox = %MuteBounce
@onready var master_volume: VolumeControl = %MasterVolume
@onready var music: VolumeControl = %Music
@onready var sfx: VolumeControl = %SFX
# Called when the node enters the scene tree for the first time.

func _ready():
	get_tree().paused = true
	tab_container.current_tab = 0
	mute_bounce.set_pressed_no_signal(GameState.save_game.mute_bounce)
	v_sync_options.selected = GameState.save_game.vsync_mode
	
	master_volume.set_bus_volume(GameState.save_game.master_volume)
	music.set_bus_volume(GameState.save_game.sfx_volume)
	sfx.set_bus_volume(GameState.save_game.music_volume)

# Called when Back button is pressed
func _on_back_button_pressed() -> void:
	GameState.save_game.mute_bounce = mute_bounce.button_pressed
	GameState.save_game.vsync_mode = v_sync_options.selected
	GameState.save_game.master_volume = master_volume.slider.value
	GameState.save_game.sfx_volume = music.slider.value
	GameState.save_game.music_volume = sfx.slider.value
	GameState.save_game.write_savegame()
	
	# Return to main menu
	queue_free()
	get_tree().paused = false

var instantiated_credits
func _on_credits_button_pressed() -> void:
	tab_container.current_tab = 1

func _on_return_to_settings_pressed() -> void:
	tab_container.current_tab = 0
	pass # Replace with function body.

func _on_v_sync_options_item_selected(index: int) -> void:
	if index == 0: # Disabled (default)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	elif index == 1: # Adaptive
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
	elif index == 2: # Enabled
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
