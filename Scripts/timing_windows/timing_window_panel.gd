# File:timing_window_panel.gd
# Date:2026-07-31
# Author: Caspian Tyler

extends Panel
class_name TimingWindowSliderVisualHandler

@export var timing_window : TimingWindow
@onready var slider: Panel = %Slider

func _ready():
	size = Vector2(timing_window.backing_width, size.y)
	slider.size.x = timing_window.slider_width

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	slider.position.x = timing_window.slider_position
	pass
