extends TimingTarget
class_name LaLaLandTarget
@onready var timing_window: SliderTimingWindow = %TimingWindow
@onready var timing_window2: SliderTimingWindow = %TimingWindow2
@onready var timing_window3: SliderTimingWindow = %TimingWindow3

func initialize():
	timing_window = %TimingWindow
	timing_window2 = %TimingWindow2
	timing_window3 = %TimingWindow3
	timing_window.pressed.connect(timing_hit)
	timing_window2.pressed.connect(timing_hit2)
	timing_window3.pressed.connect(timing_hit3)

func hit(_timing_window : SliderTimingWindow = null):
	super.hit(_timing_window)
	freeze.emit(true)
	timing_window.show()
	await get_tree().create_timer(0.2).timeout
	timing_window.start()
	pass

func timing_hit(success : bool):
	if success:
		timing_window.pause(false)
		timing_window2.start()
	else:
		exit()
	pass

func timing_hit2(success : bool):
	if success:
		timing_window2.pause(false)
		timing_window3.start()
	else:
		exit()
	pass
	
func timing_hit3(success : bool):
	if success:
		timing_window3.pause(true)
		freeze.emit(false)
	else:
		exit()
	
	pass

func exit():
	timing_window.stop()
	freeze.emit(false)
