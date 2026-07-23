extends Control
class_name TimingWindowTask
## Resolves timing attempts from Space or left click.
@onready var mining_window: SliderTimingWindow = %MiningWindow
@onready var recovery_window: SliderTimingWindow = %RecoveryWindow
@onready var streak_lost_sound: AudioStreamPlayer2D = %StreakLostSound
@onready var combo_label: Label = %ComboLabel
@onready var hit_sound: AudioStreamPlayer2D = %HitSound
@onready var streak_saved_sound: AudioStreamPlayer2D = %StreakSavedSound
@onready var warning_sound: AudioStreamPlayer2D = %WarningSound
@onready var save_bwah_sound: AudioStreamPlayer2D = %SaveBwahSound

signal pressed(success : bool, combo : int)          

var combo : int = 0 :
	set(value):
		combo = value
		combo_label.text = "Next bar in: " + str(wrapi(combo_count_for_additional_target - value,1, combo_count_for_additional_target+1))

@export var recovery_combo_count : int = 5
@export var combo_count_for_additional_target : int = 10
@export var combo_speed_multiplier : float = 0.1
@export var mine_sounds : Array[AudioStream]

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
		if not mine_sounds.is_empty():
			hit_sound.stream = mine_sounds[
				clampi(combo - 1, 0, mine_sounds.size() - 1)
			]
			hit_sound.play()

		if combo % combo_count_for_additional_target == 0:
			mining_window.add_target.call_deferred()
	else:
		if combo >= recovery_combo_count:
			warning_sound.play()
			await mining_window.pause(true)
			recovery_window.start()
			save_bwah_sound.play()
		else:
			pressed.emit(false, combo)
			combo = 0
			mining_window.remove_all_extra_targets()
			mining_window.speed_multiplier = 1.0+(combo_speed_multiplier*combo)
			streak_lost_sound.play()
			mining_window.reset_all_targets()


## Resolves recovery and restarts the main timing bar.
func _recovery_window_pressed(success : bool):
	if not success:
		combo = 0
		mining_window.reset_all_targets()
		pressed.emit(false, combo)
		recovery_window.stop()
		mining_window.speed_multiplier = 1.0
		mining_window.remove_all_extra_targets()
		streak_lost_sound.play()
	else:
		streak_saved_sound.play()

	mining_window.start()
