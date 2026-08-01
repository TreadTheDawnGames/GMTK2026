extends TimingTarget
class_name FadeTarget

@export var fade_time : float = 2.0
# Called when the node enters the scene tree for the first time.
var t : Tween
func initialize() -> void:
	_fade()
	pass # Replace with function body.

func hit(_timing_window : TimingWindow = null):
	super.hit(_timing_window)
	t.kill()
	modulate.a = 1.0

func unhit() -> void:
	modulate.a = 1.0
	t.kill()
	_fade()
	super.unhit()
	

func _fade():
	if t != null and t.is_running():
		return
	else:
		t = create_tween()
	super.initialize()
	t.tween_property(self, "modulate:a", 0.1, fade_time)
