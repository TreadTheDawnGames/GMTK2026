extends Control
@onready var color_slider: HSlider = $Panel/VBoxContainer/ColorSliderContainer/ColorSlider
@onready var example_ship: Sprite2D = $Panel/VBoxContainer/ExampleShipContainer/ExampleShip
@onready var player_audio_handler: PlayerAudioHandler = $PlayerAudioHandler
@onready var use_aim_arrow_toggle: CheckBox = $Panel/VBoxContainer/HBoxContainer2/CheckBox2
@onready var tab_container: TabContainer = $TabContainer
@onready var v_sync_options: OptionButton = $TabContainer/Panel/VBoxContainer/HBoxContainer2/Control/VSyncOptions
# Called when the node enters the scene tree for the first time.

func _ready():
	tab_container.current_tab = 0

# Called when Back button is pressed
func _on_back_button_pressed() -> void:
	get_tree().paused = false
	# Return to main menu
	queue_free()

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
