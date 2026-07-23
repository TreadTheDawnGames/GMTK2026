extends Control
class_name TimingWindowTask
## Completes after repeatedly pressing Space while the rotating needle is in the target arc.
@onready var mining_window: SliderTimingWindow = %MiningWindow
@onready var recovery_window: SliderTimingWindow = %RecoveryWindow

signal pressed(success : bool, combo : int)          

var combo : int = 0 :
	set(value):
		combo = value
		combo_label.text = "Combo: " + str(value)
var losing_combo : bool = false

@onready var combo_label: Label = %ComboLabel

@export var recovery_combo_count : int = 5

func _ready():
	mining_window.pressed.connect(_mining_window_pressed)
	recovery_window.pressed.connect(_recovery_window_pressed)
	recovery_window.randomize_target()
	recovery_window.stop()
	#.pressed.connect(
		#func(success : bool): 
			#if not success:
				#combo = 0
				#print("failed")
			#losing_combo = false
				#)
	
func _mining_window_pressed(success : bool):
	if success:
		combo += 1
		pressed.emit(true, combo)
	else:
		if combo >= recovery_combo_count:
			recovery_window.start()
			mining_window.pause()
		else:
			combo = 0
	pass

func _recovery_window_pressed(success : bool):
	if not success:
		combo = 0
		pressed.emit(false, combo)
		recovery_window.stop()
	mining_window.start()
	
	pass
