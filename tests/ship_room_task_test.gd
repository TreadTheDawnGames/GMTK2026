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

	var selected_room := controller.select_room_at_world_position(cargo_room.global_position)
	if selected_room != cargo_room or not objective.has_active_task():
		_fail("Selecting CargoRoom did not ask TaskPicker to open a task.")
		return

	objective.set_physics_process(false)
	objective.damage.set_process(false)
	crew.global_position = cargo_room.global_position
	second_crew.global_position = Vector2(5000.0, 5000.0)
	objective._physics_process(0.0)
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
	objective._physics_process(0.0)
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
