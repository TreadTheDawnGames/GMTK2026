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
@onready var depth_label: Label = %DepthLabel

signal pressed(success: bool, combo: int)

@export var mining_config: MiningConfig

var combo: int = 0:
	set(value):
		combo = value
		combo_label.text = "Combo: " + str(-combo)

@export var mine_sounds: Array[AudioStream]
@export var combo_saved_color: Color = Color.CYAN
@export var combo_lost_color: Color = Color.RED

## Connects both timing bars to the combo flow.
func _ready() -> void:
	if mining_config == null:
		push_error("TimingWindowTask requires a MiningConfig.")
		return
	mining_window.speed = mining_config.mining_bar_speed
	recovery_window.speed = mining_config.recovery_bar_speed
	mining_window.set_starting_target_count(
		mining_config.starting_mining_target_count
	)
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
	
	depth_label.text = str(Utils.format_number_with_commas(GameState.config.total_run_depth))
	GameState.depth_changed.connect(func(depth): depth_label.text = Utils.format_number_with_commas(GameState.config.total_run_depth - GameState.depth))


## Updates the combo or opens recovery after the main timing result.
func _mining_window_pressed(success: bool) -> void:
	if success:
		combo += 1
		pressed.emit(true, combo)
		mining_window.speed_multiplier = (
			(mining_config.combo_speed_multiplier)
		)
		if not mine_sounds.is_empty():
			hit_sound.stream = mine_sounds[
				clampi(combo - 1, 0, mine_sounds.size() - 1)
			]
			hit_sound.play()

		if (
			combo
			% mining_config.combo_hits_for_additional_target == 0
		):
			mining_window.add_target.call_deferred()
	else:
		if combo >= mining_config.recovery_combo_threshold:
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
		recovery_window.speed_multiplier = 1.0

	else:
		recovery_window.speed_multiplier *= (
			(mining_config.recovery_speed_multiplier)
		)

		streak_saved_sound.play()
		recovery_window.animation_color = combo_saved_color
	await recovery_window.pause(true)
	mining_window.start()
