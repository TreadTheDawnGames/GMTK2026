#meta-default: true
# File: radial_timing_menu.gd
# Date:2026-08-01
# Author: Caspian Tyler

extends TextureRect
class_name RadialTimingWindowTest
@onready var backing: RadialTimingWindowTest = %backing
@onready var pointer: TextureRect = %pointer
@export var timing_window : TimingWindow

func _ready() -> void:
	pass


func _process(delta: float) -> void:
	pointer.rotation = remap(timing_window.slider_position, 0, timing_window.backing_width-timing_window.slider_width, 0, 2*PI)
	pass
