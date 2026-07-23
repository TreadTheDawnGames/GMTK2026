extends Control
class_name TimingWindowTask
## Resolves timing attempts from Space or left click.
@onready var mining_window: SliderTimingWindow = %MiningWindow
@onready var recovery_window: SliderTimingWindow = %RecoveryWindow

signal pressed(success : bool, combo : int)          

var combo : int = 0 :
	set(value):
		combo = value
		combo_label.text = "Next bar in: " + str(wrapi(combo_count_for_additional_target - value,1, combo_count_for_additional_target+1))

@onready var combo_label: Label = %ComboLabel

@export var recovery_combo_count : int = 5
@export var combo_count_for_additional_target : int = 10
@export var combo_speed_multiplier : float = 0.1


## Connects both timing bars to the combo flow.
func _ready():
	combo_label.text = "Next bar in: " + str(combo_count_for_additional_target - combo)
	mining_window.pressed.connect(_mining_window_pressed)
	recovery_window.pressed.connect(_recovery_window_pressed)


## Updates the combo or opens recovery after the main timing result.
func _mining_window_pressed(success : bool):
	if success:
		combo += 1
		pressed.emit(true, combo)
		mining_window.speed_multiplier = 1.0+(combo_speed_multiplier*combo)
		if combo % combo_count_for_additional_target == 0:
			mining_window.add_target.call_deferred()
	else:
		if combo >= recovery_combo_count:
			recovery_window.start()
			mining_window.pause()
		else:
			pressed.emit(false, combo)
			combo = 0
			mining_window.remove_all_extra_targets()
			mining_window.speed_multiplier = 1.0+(combo_speed_multiplier*combo)


## Resolves recovery and restarts the main timing bar.
func _recovery_window_pressed(success : bool):
	if not success:
		combo = 0
		pressed.emit(false, combo)
		recovery_window.stop()
		mining_window.speed_multiplier = 1.0
		mining_window.remove_all_extra_targets()

	mining_window.start()
