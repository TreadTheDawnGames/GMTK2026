extends TimingTarget
class_name ChaseTarget

@onready var times_hit_label: Label = %TimesHitLabel

@export var required_hits:int = 3
var times_hit : int = 0:
	set(value):
		times_hit = value
		times_hit_label.text = str(required_hits-times_hit)
		

var slider_position : float = 0.0
var slider_direction : float = 0.0
var distance : float = 150.0

func initialize():
	super.initialize()
	times_hit_label = %TimesHitLabel
	times_hit_label.text = str(required_hits)

func hit(_timing_window : SliderTimingWindow = null) -> void:

	times_hit += 1
	slider_position = _timing_window.slider.position.x
	slider_direction = _timing_window.direction
	_timing_window.randomize_target(self)
	if times_hit == required_hits:
		super.hit(_timing_window)
		times_hit = 0
	pass

func unhit():
	super.unhit()
	times_hit = 0

func place(placement_width : float) -> float:
	var placement : float = slider_position + (distance * slider_direction)
	if placement > placement_width:
		placement = placement_width - distance
	if placement < 0.0:
		placement = distance
		
	return placement
