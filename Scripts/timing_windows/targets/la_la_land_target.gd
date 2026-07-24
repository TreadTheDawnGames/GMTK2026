extends TimingTarget
class_name LaLaLandTarget
@onready var timing_window: SliderTimingWindow = %TimingWindow

func initialize():
	if not timing_window:
		timing_window = %TimingWindow
	timing_window.stop()
	timing_window.pressed.connect(timing_hit)

func hit():
	super.hit()
	freeze.emit(true)
	timing_window.show()
	await get_tree().create_timer(0.2).timeout
	timing_window.start()
	pass

func timing_hit(success : bool):
	timing_window.stop()
	freeze.emit(false)
	pass
