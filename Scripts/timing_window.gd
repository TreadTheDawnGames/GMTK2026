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

signal pressed(success: bool, combo: int)

var combo: int = 0:
	set(value):
		combo = value
		combo_label.text = "Combo: " + str(-combo)

@export_range(1, 100, 1) var recovery_combo_count: int = 5
@export_range(1, 100, 1) var combo_count_for_additional_target: int = 10
@export var combo_speed_multiplier: float = 1.1
@export var mine_sounds: Array[AudioStream]
@export var combo_saved_color: Color = Color.CYAN
@export var combo_lost_color: Color = Color.RED

## Connects both timing bars to the combo flow.
func _ready() -> void:
	combo_label.text = (
		"Combo: "
		+ str(-combo)
	)
	if not mining_window.pressed.is_connected(
		_mining_window_pressed
	):
		mining_window.pressed.connect(_mining_window_pressed)
	if not recovery_window.pressed.is_connected(
		_recovery_window_pressed
	):
		recovery_window.pressed.connect(_recovery_window_pressed)


## Updates the combo or opens recovery after the main timing result.
func _mining_window_pressed(success: bool) -> void:
	if success:
		combo += 1
		pressed.emit(true, combo)
		mining_window.speed_multiplier = (
			(combo_speed_multiplier)
		)
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
			mining_window.speed_multiplier = 1.0
			streak_lost_sound.play()
			mining_window.reset_all_targets()


## Resolves recovery and restarts the main timing bar.
func _recovery_window_pressed(success: bool) -> void:
	if not success:
		combo = 0
		mining_window.reset_all_targets()
		pressed.emit(false, combo)
		streak_lost_sound.play()
		#recovery_window.stop()

		mining_window.speed_multiplier = 1.0
		mining_window.remove_all_extra_targets()
		recovery_window.animation_color = combo_lost_color
	else:
		streak_saved_sound.play()
		recovery_window.animation_color = combo_saved_color
		mining_window.speed_multiplier *=2
	await recovery_window.pause(true)
	mining_window.start()
