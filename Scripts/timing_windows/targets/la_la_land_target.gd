extends TimingTarget
class_name LaLaLandTarget
@onready var timing_window: SliderTimingWindow = %TimingWindow
@onready var timing_window2: SliderTimingWindow = %TimingWindow2
@onready var timing_window3: SliderTimingWindow = %TimingWindow3

@export var combo_override : int = 100

var main_timing_window : WeakRef

func initialize():
	super.initialize()
	ensure_components()

func ensure_components():
	if not timing_window:
		timing_window = %TimingWindow
	if not timing_window2:
		timing_window2 =  %TimingWindow2
	if not timing_window3:
		timing_window3 =  %TimingWindow3
	
	if not timing_window.pressed.is_connected(timing_hit):
		timing_window.pressed.connect(timing_hit)
	if not timing_window2.pressed.is_connected(timing_hit2):
		timing_window2.pressed.connect(timing_hit2)
	if not timing_window3.pressed.is_connected(timing_hit3):
		timing_window3.pressed.connect(timing_hit3)

func hit(_timing_window : SliderTimingWindow = null):
	main_timing_window = weakref(_timing_window)
	#super.hit(_timing_window)
	freeze.emit(true)
	timing_window.show()
	hide()
	await get_tree().create_timer(0.2).timeout
	timing_window.start()
	pass

func timing_hit(
	success: bool,
	_hit_direction: int = 0,
	_consecutive: int = 0
) -> void:
	if success:
		timing_window.pause(false)
		timing_window2.start()
	else:
		exit()
	pass

func timing_hit2(
	success: bool,
	_hit_direction: int = 0,
	_consecutive: int = 0
) -> void:
	if success:
		timing_window2.pause(false)
		timing_window3.start()
	else:
		exit()
	pass
	
func timing_hit3(
	success: bool,
	_hit_direction: int = 0,
	_consecutive: int = 0
) -> void:
	if success:
		succeed()
	else:
		exit()

func exit():
	timing_window.stop()
	timing_window2.stop()
	timing_window3.stop()
	ready_to_die.emit()
	is_hit = true
	freeze.emit(false)

func succeed():
	timing_window.pause(true)
	timing_window2.pause(true)
	await timing_window3.pause(true)
	
	timing_window.stop()
	timing_window2.stop()
	var window : SliderTimingWindow = main_timing_window.get_ref() as SliderTimingWindow
	window.pressed.emit(true, 0, -combo_override)
	exit()
	#window.pressed.emit(true, 0, combo_override)
	pass

func _exit_tree() -> void:
	main_timing_window = null
