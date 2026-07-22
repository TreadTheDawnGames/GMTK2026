class_name ShipCommandController
extends Node
## Converts mouse input into crew selection and movement orders.

signal selection_changed(selected_crew: Array[CrewMember])
signal move_order_issued(destination: Vector2, crew_count: int)
signal room_selected(room: ShipSection)

@export var crew_container: Node2D
@export var ship_builder: ShipBuilder
@export var selection_box: Control
@export_range(0.0, 32.0, 1.0) var formation_spacing := 10.0
## Pointer movement required before a left click becomes a drag selection.
@export_range(2.0, 32.0, 1.0) var drag_threshold := 6.0

var _selected_crew: Array[CrewMember] = []
var _is_drag_selecting := false
var _drag_additive := false
var _drag_start_screen := Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT:
				if mouse_event.pressed:
					_begin_drag_selection(mouse_event.position, mouse_event.shift_pressed)
				else:
					_finish_drag_selection(mouse_event.position)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				if mouse_event.pressed:
					var world_position := (
						get_viewport().get_canvas_transform().affine_inverse()
						* mouse_event.position
					)
					issue_move_order(world_position)
	elif event is InputEventMouseMotion and _is_drag_selecting:
		_update_selection_box((event as InputEventMouseMotion).position)


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
	if selected_target == null and not additive:
		select_room_at_world_position(world_position)


func select_room_at_world_position(world_position: Vector2) -> ShipSection:
	if ship_builder == null:
		return null
	var room := ship_builder.get_room_at_world_position(world_position)
	if room != null and room.select_room():
		room_selected.emit(room)
		return room
	return null


func select_in_screen_rect(screen_rect: Rect2, additive := false) -> void:
	if not additive:
		clear_selection()
	if crew_container == null:
		selection_changed.emit(get_selected_crew())
		return
	var canvas_transform := get_viewport().get_canvas_transform()
	for child in crew_container.get_children():
		var crew_member := child as CrewMember
		if crew_member == null:
			continue
		var crew_screen_position := canvas_transform * crew_member.global_position
		if screen_rect.has_point(crew_screen_position) and not _selected_crew.has(crew_member):
			_selected_crew.append(crew_member)
			crew_member.set_selected(true)
	selection_changed.emit(get_selected_crew())


func issue_move_order(world_destination: Vector2) -> void:
	if _selected_crew.is_empty():
		return
	# Center a small horizontal formation around the clicked destination.
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


func _begin_drag_selection(screen_position: Vector2, additive: bool) -> void:
	_is_drag_selecting = true
	_drag_additive = additive
	_drag_start_screen = screen_position
	if selection_box != null:
		selection_box.visible = false


func _finish_drag_selection(screen_position: Vector2) -> void:
	if not _is_drag_selecting:
		return
	_is_drag_selecting = false
	if selection_box != null:
		selection_box.visible = false
	if _drag_start_screen.distance_to(screen_position) >= drag_threshold:
		select_in_screen_rect(_get_drag_rect(screen_position), _drag_additive)
		return
	var world_position := (
		get_viewport().get_canvas_transform().affine_inverse() * screen_position
	)
	select_at_world_position(world_position, _drag_additive)


func _update_selection_box(screen_position: Vector2) -> void:
	if selection_box == null:
		return
	var drag_rect := _get_drag_rect(screen_position)
	selection_box.position = drag_rect.position
	selection_box.size = drag_rect.size
	selection_box.visible = drag_rect.size.length() >= drag_threshold


func _get_drag_rect(screen_position: Vector2) -> Rect2:
	# Rect2.abs() normalizes drags made in any screen direction.
	return Rect2(_drag_start_screen, screen_position - _drag_start_screen).abs()
