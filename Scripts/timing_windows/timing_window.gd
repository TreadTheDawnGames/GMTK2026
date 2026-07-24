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

signal pressed(success: bool, combo: int, hit_direction: int)
## Reports the combo that actually ended after recovery is exhausted.
signal streak_ended(previous_combo: int)

@export var mining_config: MiningConfig

var combo: int = 0:
	set(value):
		combo = value
		combo_label.text = "Combo: " + str(-combo)

@export var mine_sounds: Array[AudioStream]
@export var combo_saved_color: Color = Color.CYAN
@export var combo_lost_color: Color = Color.RED

@onready var _game_state: RunState = RunState.get_global(self)
var _target_unlocks: Array[PickaxeDefinition] = []

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
	
	_update_depth_label(_game_state.depth)
	if not _game_state.depth_changed.is_connected(_update_depth_label):
		_game_state.depth_changed.connect(_update_depth_label)
	if not _target_unlocks.is_empty():
		_apply_pickaxe_target_unlocks()


## Shows remaining run depth from the shared state.
func _update_depth_label(_depth: int) -> void:
	depth_label.text = Utils.format_number_with_commas(
		_game_state.remaining_depth
	)


## Stores cumulative pickaxes and restores their zero-combo baseline scenes.
func set_pickaxe_target_unlocks(
	definitions: Array[PickaxeDefinition]
) -> void:
	_target_unlocks = definitions.duplicate()
	if is_node_ready():
		_apply_pickaxe_target_unlocks()


## Rebuilds only the zero-combo target baseline after the bar is ready.
func _apply_pickaxe_target_unlocks() -> void:
	var baseline_scenes: Array[PackedScene] = []
	for definition in _target_unlocks:
		if definition == null or definition.target_unlock_combo > 0:
			continue
		baseline_scenes.append_array(definition.target_scenes)
	if not baseline_scenes.is_empty():
		mining_window.set_target_pool(baseline_scenes)


## Updates the combo or opens recovery after the main timing result.
func _mining_window_pressed(
	success: bool,
	hit_direction: int = 0
) -> void:
	if success:
		combo += 1
		pressed.emit(true, combo, clampi(hit_direction, -1, 1))
		mining_window.speed_multiplier = (
			(mining_config.combo_speed_multiplier)
		)
		if not mine_sounds.is_empty():
			hit_sound.stream = mine_sounds[
				clampi(combo - 1, 0, mine_sounds.size() - 1)
			]
			hit_sound.play()

		var unlocked_pickaxe_target := false
		for definition in _target_unlocks:
			if (
				definition == null
				or definition.target_unlock_combo != combo
				or definition.target_scenes.is_empty()
			):
				continue
			mining_window.add_target_from_pool.call_deferred(
				definition.target_scenes
			)
			unlocked_pickaxe_target = true
		if (
			not unlocked_pickaxe_target
			and _target_unlocks.is_empty()
			and combo
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
			var lost_combo := combo
			pressed.emit(false, combo, 0)
			combo = 0
			streak_ended.emit(lost_combo)
			mining_window.remove_all_extra_targets()
			mining_window.speed_multiplier = 1.0
			streak_lost_sound.play()
			mining_window.reset_all_targets()


## Resolves recovery and restarts the main timing bar.
func _recovery_window_pressed(
	success: bool,
	_hit_direction: int = 0
) -> void:
	if not success:
		var lost_combo := combo
		combo = 0
		mining_window.reset_all_targets()
		pressed.emit(false, combo, 0)
		streak_ended.emit(lost_combo)
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
