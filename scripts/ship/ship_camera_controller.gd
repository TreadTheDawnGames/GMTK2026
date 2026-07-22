class_name ShipCameraController
extends Camera2D
## Starts with the complete ship framed, then allows manual inspection.

@export var framing_target: ShipBuilder
@export_range(0.0, 160.0, 1.0) var screen_margin := 56.0
@export_range(50.0, 1200.0, 10.0) var pan_speed := 420.0
@export_range(0.05, 1.0, 0.05) var zoom_step := 0.15
@export_range(0.1, 1.0, 0.05) var minimum_zoom := 0.4
@export_range(1.0, 5.0, 0.05) var maximum_zoom := 2.5

var _is_dragging := false


func _ready() -> void:
	get_viewport().size_changed.connect(frame_ship)
	frame_ship.call_deferred()


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


func frame_ship() -> void:
	if framing_target == null:
		return
	var ship_bounds := framing_target.get_ship_bounds()
	if not ship_bounds.has_area():
		return
	var available_size := get_viewport_rect().size - Vector2.ONE * screen_margin * 2.0
	if available_size.x <= 0.0 or available_size.y <= 0.0:
		return
	var fit_zoom := minf(
		available_size.x / ship_bounds.size.x,
		available_size.y / ship_bounds.size.y
	)
	zoom = Vector2.ONE * clampf(fit_zoom, minimum_zoom, maximum_zoom)
	global_position = framing_target.to_global(ship_bounds.get_center())


func pan_by(offset: Vector2) -> void:
	position += offset


func set_zoom_level(value: float) -> void:
	zoom = Vector2.ONE * clampf(value, minimum_zoom, maximum_zoom)
