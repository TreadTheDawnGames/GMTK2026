extends SceneTree
## Verifies selectable task rooms and crew-assisted durability decay.

const LEVEL_SCENE := preload("res://scenes/game_scene/levels/spaceship_level.tscn")


func _initialize() -> void:
	var level := LEVEL_SCENE.instantiate()
	root.add_child.call_deferred(level)
	await process_frame
	await physics_frame

	var ship := level.get_node("BaseShip") as ShipBuilder
	var controller := level.get_node("ShipCommandController") as ShipCommandController
	var crew := level.get_node("CrewContainer/CrewOne") as CrewMember
	var second_crew := level.get_node("CrewContainer/CrewTwo") as CrewMember
	var cargo_room := ship.get_node("CargoRoom") as ShipSection
	var objective := cargo_room.get_task_objective()
	if objective == null:
		_fail("CargoRoom does not contain a selectable task objective.")
		return

	# Exercise the same press/release path used by a real mouse click, away from
	# the smaller objective icon so the room itself is the input target.
	var room_click_world := cargo_room.global_transform * Vector2(48.0, 40.0)
	var room_click_screen := level.get_viewport().get_canvas_transform() * room_click_world
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = room_click_screen
	press.pressed = true
	controller._unhandled_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = room_click_screen
	release.pressed = false
	controller._unhandled_input(release)
	if not objective.has_active_task():
		_fail("Clicking CargoRoom did not ask TaskPicker to open a task.")
		return

	objective.damage.set_process(false)
	second_crew.global_position = Vector2(5000.0, 5000.0)
	crew.move_to(cargo_room.global_position)
	for _frame in range(480):
		await physics_frame
		if objective.has_crew_in_room():
			break
	if not objective.has_crew_in_room():
		_fail("Crew navigation reached its timeout before entering CargoRoom.")
		return
	await physics_frame
	if not is_equal_approx(
		objective.damage.decay_rate_scale,
		objective.crew_present_decay_multiplier
	):
		_fail("A crew member in the task room did not slow durability decay.")
		return

	objective.damage.durability = 5.0
	objective.damage._process(1.0)
	var assisted_loss := 5.0 - objective.damage.durability
	crew.global_position = Vector2(5000.0, 5000.0)
	await physics_frame
	var durability_before_unassisted_decay := objective.damage.durability
	objective.damage._process(1.0)
	var unassisted_loss := durability_before_unassisted_decay - objective.damage.durability
	if assisted_loss >= unassisted_loss:
		_fail("Crew-assisted durability did not decay more slowly than unattended durability.")
		return

	print("Ship room tasks passed: room selection, TaskPicker, and crew-assisted durability.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
