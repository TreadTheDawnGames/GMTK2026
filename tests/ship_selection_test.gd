extends SceneTree
## Verifies click, drag-box, and additive crew selection against the real level.

const LEVEL_SCENE := preload("res://scenes/game_scene/levels/spaceship_level.tscn")


func _initialize() -> void:
	var level := LEVEL_SCENE.instantiate()
	root.add_child.call_deferred(level)
	await process_frame
	await process_frame

	var controller := level.get_node("ShipCommandController") as ShipCommandController
	var first_crew := level.get_node("CrewContainer/CrewOne") as CrewMember
	var second_crew := level.get_node("CrewContainer/CrewTwo") as CrewMember
	var canvas_transform := level.get_viewport().get_canvas_transform()
	var first_screen := canvas_transform * first_crew.global_position
	var second_screen := canvas_transform * second_crew.global_position

	controller.select_at_world_position(first_crew.global_position)
	if controller.get_selected_crew() != [first_crew]:
		_fail("Click selection did not select only the targeted crew member.")
		return

	var both_rect := Rect2(first_screen, second_screen - first_screen).abs().grow(8.0)
	controller.select_in_screen_rect(both_rect)
	if controller.get_selected_crew().size() != 2:
		_fail("Drag selection did not select both crew members.")
		return

	controller.clear_selection()
	controller.select_at_world_position(first_crew.global_position)
	controller.select_in_screen_rect(Rect2(second_screen - Vector2.ONE, Vector2.ONE * 2.0), true)
	if controller.get_selected_crew().size() != 2:
		_fail("Shift-additive drag selection did not preserve the first crew member.")
		return

	print("Ship crew selection passed: click, drag, and additive selection.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
