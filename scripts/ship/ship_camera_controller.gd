class_name ShipCameraController
extends Camera2D
## Keyboard, middle-mouse, and wheel controls for inspecting the ship.

@export_range(50.0, 1200.0, 10.0) var pan_speed := 420.0
@export_range(0.05, 1.0, 0.05) var zoom_step := 0.15
@export_range(0.25, 1.0, 0.05) var minimum_zoom := 0.75
@export_range(1.0, 5.0, 0.05) var maximum_zoom := 2.5
@export var pan_bounds := Rect2(320, -80, 640, 880)

var _is_dragging := false


func _process(delta: float) -> void:
	var focused_control := get_viewport().gui_get_focus_owner()
	if focused_control is LineEdit or focused_control is TextEdit:
		return
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	)
	if not direction.is_zero_approx():
		pan_by(direction.normalized() * pan_speed * delta / zoom.x)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		match mouse_event.button_index:
			MOUSE_BUTTON_MIDDLE:
				_is_dragging = mouse_event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mouse_event.pressed:
					set_zoom_level(zoom.x + zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mouse_event.pressed:
					set_zoom_level(zoom.x - zoom_step)
	elif event is InputEventMouseMotion and _is_dragging:
		pan_by(-(event as InputEventMouseMotion).relative / zoom.x)


func pan_by(offset: Vector2) -> void:
	position += offset
	position.x = clampf(position.x, pan_bounds.position.x, pan_bounds.end.x)
	position.y = clampf(position.y, pan_bounds.position.y, pan_bounds.end.y)


func set_zoom_level(value: float) -> void:
	var clamped_zoom := clampf(value, minimum_zoom, maximum_zoom)
	zoom = Vector2.ONE * clamped_zoom
