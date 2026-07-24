extends TimingTarget
class_name MultiTarget

@onready var times_hit_label: Label = %TimesHitLabel

@export var required_hits:int = 3
var times_hit : int = 0

var slider_position : float = 0.0
var slider_direction : float = 0.0

func initialize():
	times_hit_label.text = str(times_hit_label)

func hit(_timing_window : SliderTimingWindow = null) -> void:
	if times_hit == required_hits:
		super.hit(_timing_window)
		return
	times_hit += 1
	slider_position = _timing_window.slider.position.x
	slider_direction = _timing_window.direction
	#place(_timing_window.backing.size.x)
	pass
	

func place(placement_width : float) -> float:
	
	
	
	return 0.0
