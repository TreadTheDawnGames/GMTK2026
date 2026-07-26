extends Control
class_name TimingWindowTask

## Resolves timing attempts through the project's primary input action.

@onready var mining_window: SliderTimingWindow = %MiningWindow
@onready var recovery_window: SliderTimingWindow = %RecoveryWindow
@onready var recovery_window2: SliderTimingWindow = %RecoveryWindow2
@onready var combo_label: Label = %ComboLabel
@onready var depth_label: Label = %DepthLabel

signal pressed(success: bool, combo: int, hit_direction: int)
## Reports the combo that actually ended after recovery is exhausted.
signal streak_ended(previous_combo: int)

@export var mining_config: MiningConfig

var combo: int = 0:
	set(value):
		combo = value
		combo_label.text = "Combo: " + str(-combo)
var stored_combo : int = 0

@export var combo_saved_color: Color = Color.CYAN
@export var combo_lost_color: Color = Color.RED

var _audio_handler: PlayerAudioHandler
var _target_unlocks: Array[PickaxeDefinition] = []
var _progression_target_scenes: Array[PackedScene] = []
var _progression_bonus_target_combos := PackedInt32Array()
var _uses_encounter_progression: bool = false
var _bounce_muted: bool = false
var _displayed_distance: int = 0

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
	if not recovery_window2.pressed.is_connected(
		_additional_recovery_window_pressed
	):
		recovery_window2.pressed.connect(_additional_recovery_window_pressed)
		
	#_update_depth_label(_game_state.depth)
	#if not _game_state.depth_changed.is_connected(_update_depth_label):
		#_game_state.depth_changed.connect(_update_depth_label)
	if not _target_unlocks.is_empty():
		_apply_pickaxe_target_unlocks()
	set_bounce_muted(_bounce_muted)
	show_displayed_distance(_displayed_distance)


## Supplies the cross-scene audio service at the composition boundary.
func set_audio_handler(audio_handler: PlayerAudioHandler) -> void:
	_audio_handler = audio_handler


## Plays optional feedback when this reusable timing scene has an audio owner.
func _play_sound(
	sound: AudioStream,
	bus_name: String = "SFX",
	do_pitch_scale: bool = false,
	pitch_scale: float = 1.0
) -> void:
	if _audio_handler == null:
		return
	_audio_handler.play_sound(
		sound,
		bus_name,
		do_pitch_scale,
		pitch_scale
	)


## Applies the saved bounce preference to both authored timing bars.
func set_bounce_muted(is_muted: bool) -> void:
	_bounce_muted = is_muted
	if not is_node_ready():
		return
	mining_window.set_bounce_muted(is_muted)
	recovery_window.set_bounce_muted(is_muted)


## Shows distance to the Thief, then distance travelled beyond the Thief.
func show_displayed_distance(displayed_distance: int) -> void:
	_displayed_distance = maxi(displayed_distance, 0)
	if not is_node_ready():
		return
	depth_label.text = Utils.format_number_with_commas(_displayed_distance)


## Stores cumulative pickaxes and restores their zero-combo baseline scenes.
func set_pickaxe_target_unlocks(
	definitions: Array[PickaxeDefinition]
) -> void:
	_target_unlocks = definitions.duplicate()
	if is_node_ready():
		_apply_pickaxe_target_unlocks()


## Applies the timing portion of one complete encounter-progression level.
## New level-owned timing rules are added to this explicit contract and passed
## by EncounterProgression.apply_level(), as documented in pickaxe_authoring.md.
func set_progression_target_rules(
	target_scenes: Array[PackedScene],
	slider_speed: float,
	starting_target_count: int,
	bonus_target_combos: PackedInt32Array
) -> void:
	if target_scenes.is_empty():
		push_warning("Encounter progression requires timing target scenes.")
		return
	_uses_encounter_progression = true
	_progression_target_scenes = target_scenes.duplicate()
	_progression_bonus_target_combos = bonus_target_combos.duplicate()
	mining_window.speed = slider_speed
	mining_window.set_starting_target_count(starting_target_count)
	mining_window.set_target_pool(_progression_target_scenes)


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
	hit_direction: int = 0,
	consecutive_hits: int = 0
) -> void:
	if success:
		if consecutive_hits > 0:
			combo = consecutive_hits + stored_combo
		else:
			combo += 1
		pressed.emit(
			true,
			combo,
			clampi(hit_direction, -1, 1)
		)
		mining_window.speed_multiplier = (
			(mining_config.combo_speed_multiplier)
		)
		if not AudioLibrary.MINE_SOUNDS.is_empty():
			# The sample ladder runs out at MINE_SOUNDS.size(); past that the
			# pitch keeps climbing so a long streak still sounds like it is
			# going somewhere instead of flattening out.
			
			# Those tones are all the notes in a scale, so it sounds good if they're together
			_audio_handler.play_sound(
				AudioLibrary.MINE_SOUNDS[
					clampi(combo - 1, 0, AudioLibrary.MINE_SOUNDS.size() - 1)
				],
				"SFX"
			)

		var unlocked_target_scenes: Array[PackedScene] = []
		if (
			_uses_encounter_progression
			and combo in _progression_bonus_target_combos
		):
			unlocked_target_scenes = (
				_progression_target_scenes.duplicate()
			)
		elif not _uses_encounter_progression:
			for definition in _target_unlocks:
				if (
					definition == null
					or definition.target_unlock_combo != combo
					or definition.target_scenes.is_empty()
				):
					continue
				for target_scene: PackedScene in definition.target_scenes:
					if (
						target_scene != null
						and target_scene not in unlocked_target_scenes
					):
						unlocked_target_scenes.append(target_scene)
		if not unlocked_target_scenes.is_empty():
			mining_window.add_target_from_pool.call_deferred(
				unlocked_target_scenes
			)
		if (
			not _uses_encounter_progression
			and unlocked_target_scenes.is_empty()
			and _target_unlocks.is_empty()
			and combo
				% mining_config.combo_hits_for_additional_target == 0
		):
			mining_window.add_target.call_deferred()
	else:
		stored_combo = combo
		if combo >= mining_config.recovery_combo_threshold:
			_play_sound(AudioLibrary.MISS_WITH_SAVE)
			await mining_window.pause(true)
			recovery_window.start()
			_play_sound(AudioLibrary.SAVE_BUILDUP)
		else:
			fail_combo()
			mining_window.remove_all_extra_targets()
			mining_window.play_animation(Color.RED)

var failed_recovery : bool = false

## Resolves recovery and restarts the main timing bar.
func _recovery_window_pressed(
	success: bool,
	_hit_direction: int = 0,
	_consecutive_hits = 0
) -> void:
	## If successfully recovered
	if success:
		# Increase the recovery slider speed
		recovery_window.speed_multiplier *= (
			(mining_config.recovery_speed_multiplier)
		)
		#play audio
		_audio_handler.play_sound(AudioLibrary.SAVE)
		#set animation color
		recovery_window.animation_color = combo_saved_color
	else:
		#if failed
		# we want one shot at additional recovery
		if not failed_recovery and mining_config.use_secondary_recovery:
			#This is our first failure
			failed_recovery = true
			_audio_handler.play_sound(AudioLibrary.MISS_WITH_SAVE)
			print("first failure")
			recovery_window.animation_repeats = 2
			#all we want to do is open the secondary save, so do nothing
		else:
			#We've failed this track once already
			#reset combo
			fail_combo()
			#reset window speeds
			mining_window.speed_multiplier = 1.0
			recovery_window.speed_multiplier = 1.0
			recovery_window2.speed_multiplier = 1.0
			#reset targets
			recovery_window.animation_repeats = 3
			
			mining_window.remove_all_extra_targets()
			#Set animation color
			recovery_window.animation_color = combo_lost_color
			failed_recovery = false
	
	#Wait for the animation to play
	await recovery_window.pause(true)
	
	#after the animation, if it was a success
	if success:
		print("Option 1")
		#targets call themselves and we clamp them to make sure they're within the allowed area
		mining_window.recovery_action()
		mining_window.clamp_all_targets()
		recovery_window.stop()
		mining_window.start()
	elif failed_recovery:
		print("Option 2")
		#Check if this is the first failure and if so,Start the secondary recovery process
		recovery_window2.start()
		_audio_handler.play_sound(AudioLibrary.SAVE_BUILDUP)
	else:
		print("Option 3")
		#this is the second time failing. Reset the main window, our visibility, and the recovery state
		recovery_window.stop()
		mining_window.start()
		failed_recovery = false
		
	
	#Regardless of whether we succeeded or failed, start the mining window

## Resolves recovery and restarts the first recovery timing bar.
func _additional_recovery_window_pressed(
	success: bool,
	_hit_direction: int = 0,
	_consecutive_hits = 0
) -> void:
	# If successfully recovered, we want to return to the main recovery
	if success:
		# Increase the recovery slider speed
		recovery_window2.speed_multiplier *= (
			(mining_config.recovery_speed_multiplier)
		)
		#play audio
		_audio_handler.play_sound(AudioLibrary.SAVE)
		#set animation color
		recovery_window2.animation_color = combo_saved_color
	else:
		#if failed
		#reset combo
		fail_combo()
		#reset window speeds
		mining_window.speed_multiplier = 1.0
		recovery_window.speed_multiplier = 1.0
		recovery_window2.speed_multiplier = 1.0
		#reset targets
		mining_window.remove_all_extra_targets()
		#Set animation color
		recovery_window2.animation_color = combo_lost_color
		#reset recovery state
		failed_recovery = false
	
	#Wait our animation to play
	await recovery_window2.pause(true)
	
	#after the animation, if it was a success
	if success:
		#targets call themselves and we clamp them to make sure they're within the allowed area
		mining_window.recovery_action()
		mining_window.clamp_all_targets()
		recovery_window.start()
	#Regardless of whether we succeeded or failed, start the mining window
	else:
		recovery_window.stop()
		mining_window.recovery_action()
		mining_window.clamp_all_targets()
		mining_window.start()


func fail_combo():
	var lost_combo := combo
	pressed.emit(false, combo, 0)
	combo = 0
	stored_combo = 0
	streak_ended.emit(lost_combo)
	mining_window.speed_multiplier = 1.0
	_audio_handler.play_sound(AudioLibrary.STREAK_LOST)
