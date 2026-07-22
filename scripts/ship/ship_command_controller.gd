class_name ShipCommandController
extends Node
## Converts mouse input into crew selection and movement orders.

signal selection_changed(selected_crew: Array[CrewMember])
signal move_order_issued(destination: Vector2, crew_count: int)

@export var crew_container: Node2D
@export_range(0.0, 32.0, 1.0) var formation_spacing := 10.0

var _selected_crew: Array[CrewMember] = []


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var mouse_event := event as InputEventMouseButton
	var world_position := get_viewport().get_canvas_transform().affine_inverse() * mouse_event.position
	match mouse_event.button_index:
		MOUSE_BUTTON_LEFT:
			select_at_world_position(world_position, mouse_event.shift_pressed)
		MOUSE_BUTTON_RIGHT:
			issue_move_order(world_position)


func select_at_world_position(world_position: Vector2, additive := false) -> void:
	var selected_target := _find_crew_at(world_position)
	if not additive:
		clear_selection()
	if selected_target != null:
		if additive and _selected_crew.has(selected_target):
			_selected_crew.erase(selected_target)
			selected_target.set_selected(false)
		else:
			_selected_crew.append(selected_target)
			selected_target.set_selected(true)
	selection_changed.emit(get_selected_crew())


func issue_move_order(world_destination: Vector2) -> void:
	if _selected_crew.is_empty():
		return
	var center_index := (_selected_crew.size() - 1) * 0.5
	for index in range(_selected_crew.size()):
		var offset := Vector2.RIGHT * (index - center_index) * formation_spacing
		_selected_crew[index].move_to(world_destination + offset)
	move_order_issued.emit(world_destination, _selected_crew.size())


func clear_selection() -> void:
	for crew_member in _selected_crew:
		crew_member.set_selected(false)
	_selected_crew.clear()


func get_selected_crew() -> Array[CrewMember]:
	return _selected_crew.duplicate()


func _find_crew_at(world_position: Vector2) -> CrewMember:
	if crew_container == null:
		return null
	var closest_crew: CrewMember
	var closest_distance := INF
	for child in crew_container.get_children():
		var crew_member := child as CrewMember
		if crew_member == null or not crew_member.is_world_point_selectable(world_position):
			continue
		var distance := crew_member.global_position.distance_squared_to(world_position)
		if distance < closest_distance:
			closest_crew = crew_member
			closest_distance = distance
	return closest_crew
