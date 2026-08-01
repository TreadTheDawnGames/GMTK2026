extends TimingTarget
class_name MultiHitTarget

@onready var times_hit_label: Label = %TimesHitLabel

@export var required_hits:int = 3
var times_hit : int = 0

func initialize():
	super.initialize()
	if not times_hit_label:
		times_hit_label = %TimesHitLabel
	_reset_hit_progress()
	Utils.set_control_width(self, my_width)

func hit(_timing_window : TimingWindow = null) -> void:
	times_hit += 1
	if times_hit == required_hits:
		times_hit = 0
		super.hit(_timing_window)
	times_hit_label.text = str(required_hits-times_hit)

func reset():
	_reset_hit_progress()

func _reset_hit_progress() -> void:
	times_hit = 0
	times_hit_label.text = str(required_hits)
