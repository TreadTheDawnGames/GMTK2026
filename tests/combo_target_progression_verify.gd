extends SceneTree

## How it works:
## - Loads the production combo groups and encounter progression levels.
## - Drives the real EncounterProgression-to-TimingWindow contract.
## - Checks Zephan's entry breakpoints and reward-aligned progression caps.
## - Checks loss reset and deferred replacement of a partially resolved set.
## - Confirms reward levels change target availability, not old mining rules.
## - The invariant is that combo never selects a group progression has locked.

const TIMING_WINDOW_SCENE := preload("res://Scenes/TimingWindow.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := load(
		"res://resources/mining/mining_config.tres"
	) as MiningConfig
	_expect(
		config != null and config.has_valid_combo_target_groups(),
		"Production combo target groups must load as valid."
	)
	if config == null or not config.has_valid_combo_target_groups():
		_finish()
		return
	_verify_authored_progression(config)

	var timing_window := (
		TIMING_WINDOW_SCENE.instantiate() as TimingWindowTask
	)
	timing_window.mining_config = config
	root.add_child(timing_window)
	await process_frame
	await process_frame
	var mining_controller := MiningController.new()
	var progression := EncounterProgression.new()
	progression.config = config
	progression.mining_controller = mining_controller
	progression.timing_window = timing_window

	timing_window.combo = 20
	var reward_levels := PackedInt32Array([3, 4, 6, 7, 8])
	for expected_group_index in range(reward_levels.size()):
		var level_index := reward_levels[expected_group_index]
		_expect(
			progression.apply_level(level_index),
			"Could not apply progression level %d." % level_index
		)
		_expect_active_group(
			timing_window,
			config,
			expected_group_index,
			"level %d at combo 20" % level_index
		)

	var band_combos := PackedInt32Array([3, 4, 7, 8, 14, 15, 19, 20])
	var band_groups := PackedInt32Array([0, 1, 1, 2, 2, 3, 3, 4])
	for band_index in range(band_combos.size()):
		timing_window.combo = band_combos[band_index]
		progression.apply_level(8)
		_expect_active_group(
			timing_window,
			config,
			band_groups[band_index],
			"combo %d with every group unlocked" % band_combos[band_index]
		)

	# Crossing a threshold cannot throw away a partially resolved target set.
	# The new pool becomes active after the remainder of that set is collected.
	timing_window.combo = 14
	progression.apply_level(8)
	timing_window.mining_window.targets[0].is_hit = true
	timing_window._mining_window_pressed(true)
	await process_frame
	_expect_active_group(
		timing_window,
		config,
		2,
		"partial target set crossing combo 15"
	)
	_expect(
		timing_window.mining_window.targets.size() == 3,
		"Combo 15 did not add its authored bounded bonus target."
	)
	for target: TimingTarget in timing_window.mining_window.targets:
		target.is_hit = true
	timing_window._mining_window_pressed(true)
	await process_frame
	_expect_active_group(
		timing_window,
		config,
		3,
		"completed target set after crossing combo 15"
	)

	timing_window.fail_combo()
	await process_frame
	_expect_active_group(
		timing_window,
		config,
		0,
		"combo loss"
	)

	timing_window.queue_free()
	mining_controller.free()
	progression.free()
	await process_frame
	_finish()


func _verify_authored_progression(config: MiningConfig) -> void:
	var expected_caps := PackedInt32Array([0, 0, 0, 0, 1, 1, 2, 3, 4, 4])
	_expect(
		config.progression_levels.size() == expected_caps.size(),
		"Production progression must author levels zero through nine."
	)
	if config.progression_levels.size() != expected_caps.size():
		return
	for level_index in range(config.progression_levels.size()):
		_expect(
			config.progression_levels[level_index]
				.highest_unlocked_combo_target_group_index
				== expected_caps[level_index],
			"Progression level %d has the wrong combo-group cap." % level_index
		)

	# Reward transitions only change target availability. The surrounding
	# levels retain equivalent values for every old mechanical rule.
	var neutral_reward_transitions: Array[Vector2i] = [
		Vector2i(3, 4),
		Vector2i(5, 6),
		Vector2i(6, 7),
		Vector2i(7, 8),
	]
	for transition: Vector2i in neutral_reward_transitions:
		var before := config.progression_levels[transition.x]
		var after := config.progression_levels[transition.y]
		_expect(
			before.impact_size == after.impact_size
				and before.double_hit == after.double_hit
				and before.mine_animation_speed
					== after.mine_animation_speed
				and is_equal_approx(
					before.combo_impact_scale,
					after.combo_impact_scale
				)
				and is_equal_approx(
					before.slider_speed,
					after.slider_speed
				)
				and before.starting_target_count
					== after.starting_target_count
				and before.bonus_target_combos
					== after.bonus_target_combos,
			"Reward transition %d -> %d still stacks an old mechanical bonus."
				% [transition.x, transition.y]
		)

	var coffee_encounter := load(
		"res://resources/encounters/coffee_cat_first_encounter.tres"
	) as DepthCharacterEncounter
	var rat_encounter := load(
		"res://resources/encounters/rutini_second_encounter.tres"
	) as DepthCharacterEncounter
	var first_pickaxe_encounter := load(
		"res://resources/encounters/treasure_hunter_first_encounter.tres"
	) as DepthCharacterEncounter
	var second_pickaxe_encounter := load(
		"res://resources/encounters/treasure_hunter_treasure_encounter.tres"
	) as DepthCharacterEncounter
	_expect(
		coffee_encounter != null
			and not coffee_encounter.grants_coffee_speed_boost,
		"Quibble's target unlock must not also apply the old speed boost."
	)
	_expect(
		rat_encounter != null and rat_encounter.starts_rat_colony_support,
		"Rotini's persistent visual colony presentation must remain authored."
	)
	_expect(
		first_pickaxe_encounter != null
			and first_pickaxe_encounter.pickaxe_reward != null
			and second_pickaxe_encounter != null
			and second_pickaxe_encounter.pickaxe_reward != null,
		"Treasure Hunter's visible collectible pickaxe rewards must remain."
	)


func _expect_active_group(
	timing_window: TimingWindowTask,
	config: MiningConfig,
	expected_group_index: int,
	context: String
) -> void:
	var expected_paths: Array[String] = []
	for target_scene: PackedScene in (
		config.combo_target_groups[expected_group_index].target_scenes
	):
		expected_paths.append(target_scene.resource_path)
	var actual_paths: Array[String] = []
	for target_scene: PackedScene in (
		timing_window.mining_window.target_packed_scenes
	):
		actual_paths.append(target_scene.resource_path)
	_expect(
		actual_paths == expected_paths,
		"Wrong target group for %s: %s." % [context, actual_paths]
	)


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("COMBO_TARGET_PROGRESSION_PASS")
		quit()
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
