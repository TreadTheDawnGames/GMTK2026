extends SceneTree
## Verifies the repeating global timer and cumulative task-decay escalation.

const SHIP_SCENE := preload("res://scenes/ship/ship_builder.tscn")
const TEST_INTERVAL_SECONDS := 0.2
const TEST_STEP_MULTIPLIER := 1.25


func _initialize() -> void:
	var ship := SHIP_SCENE.instantiate()
	var coordinator := ship.get_node("TaskCoordinator") as ShipTaskCoordinator
	coordinator.global_timer_interval_seconds = TEST_INTERVAL_SECONDS
	coordinator.global_timer_decay_multiplier = TEST_STEP_MULTIPLIER
	coordinator.maximum_decay_multiplier = 10.0
	root.add_child.call_deferred(ship)
	await process_frame

	await create_timer(TEST_INTERVAL_SECONDS + 0.05).timeout
	_assert_multiplier(coordinator, TEST_STEP_MULTIPLIER, "first")
	_assert_objective_multipliers(ship, TEST_STEP_MULTIPLIER)
	var seconds_after_reset := coordinator.get_seconds_until_global_escalation()
	if seconds_after_reset <= 0.0 or seconds_after_reset > TEST_INTERVAL_SECONDS:
		_fail("Global escalation timer did not reset after reaching zero.")
		return

	await create_timer(TEST_INTERVAL_SECONDS).timeout
	var expected_second_multiplier := TEST_STEP_MULTIPLIER * TEST_STEP_MULTIPLIER
	_assert_multiplier(coordinator, expected_second_multiplier, "second")
	_assert_objective_multipliers(ship, expected_second_multiplier)

	var clock_label := ship.get_node("TaskClock/TaskClockPanel/CountdownLabel") as Label
	if "DECAY SPEED 1.56x" not in clock_label.text:
		_fail("Top-right task clock did not display the current decay speed.")
		return

	print("Ship task timer passed: reset, cumulative escalation, objectives, and HUD.")
	quit(0)


func _assert_multiplier(
	coordinator: ShipTaskCoordinator,
	expected: float,
	step_name: String
) -> void:
	if not is_equal_approx(coordinator.get_current_decay_multiplier(), expected):
		_fail("The %s global timer step did not apply %.2fx decay." % [step_name, expected])


func _assert_objective_multipliers(ship: Node, expected: float) -> void:
	for descendant in ship.find_children("*", "TaskObjective", true, false):
		var objective := descendant as TaskObjective
		if objective != null and not is_equal_approx(objective.get("_global_decay_multiplier"), expected):
			_fail("Global timer multiplier did not reach objective %s." % objective.name)
			return


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
