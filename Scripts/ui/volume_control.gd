extends HBoxContainer
class_name VolumeControl

@onready var slider: HSlider = $HSlider2
@onready var check_box: CheckBox = $CheckBox

@export var bus_name: StringName

var _bus_index: int = -1


## Connects the authored controls to their configured audio bus.
func _ready() -> void:
	if bus_name.is_empty():
		push_error("%s does not have a bus_name." % name)
		return
	_bus_index = AudioServer.get_bus_index(bus_name)
	if _bus_index < 0:
		push_error("%s targets missing audio bus '%s'." % [name, bus_name])
		return
	load_bus_setting(
		AudioServer.get_bus_volume_linear(_bus_index),
		AudioServer.is_bus_mute(_bus_index)
	)
	check_box.text = "- " + bus_name
	if not slider.value_changed.is_connected(set_bus_volume):
		slider.value_changed.connect(set_bus_volume)
	if not check_box.pressed.is_connected(set_bus_mute):
		check_box.pressed.connect(set_bus_mute)


## Loads one complete saved setting without emitting user-change signals.
func load_bus_setting(volume: float, is_muted: bool) -> void:
	slider.set_value_no_signal(volume)
	check_box.set_pressed_no_signal(is_muted)
	if _bus_index < 0:
		return
	AudioServer.set_bus_volume_linear(_bus_index, volume)
	AudioServer.set_bus_mute(_bus_index, is_muted)


## Applies a live slider change to the configured bus.
func set_bus_volume(wanted_volume: float) -> void:
	if _bus_index >= 0:
		AudioServer.set_bus_volume_linear(_bus_index, wanted_volume)


## Applies a live checkbox change to the configured bus.
func set_bus_mute() -> void:
	if _bus_index >= 0:
		AudioServer.set_bus_mute(_bus_index, check_box.button_pressed)

	
