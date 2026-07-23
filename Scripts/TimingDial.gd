extends Control
class_name TimingDial
## Draws the timing target arc and rotating needle for TimingWindowTask.

signal pressed(success : bool)

@export var circle_color := Color(0.25, 0.3, 0.38, 1.0)
@export var target_color := Color(0.2, 0.95, 0.55, 1.0)
@export var needle_color := Color(1.0, 0.85, 0.25, 1.0)
@export_range(2.0, 12.0, 1.0) var line_width := 5.0

@export var needle_speed = 5.0

var needle_angle := 0.0:
	set(value):
		needle_angle = value
		queue_redraw()
var target_angle := 0.0:
	set(value):
		target_angle = value
		queue_redraw()
var target_window_radians := deg_to_rad(90.0):#deg_to_rad(35.0):
	set(value):
		target_window_radians = value
		queue_redraw()

var active : bool = false
var fail_angle : float = 0

func _draw() -> void:
		
	var center := size * 0.5
	var radius := maxf(minf(size.x, size.y) * 0.38, 12.0)
	draw_arc(center, radius, 0.0, TAU, 96, circle_color, line_width, true)
	draw_arc(
		center,
		radius,
		target_angle - target_window_radians * 0.5,
		target_angle + target_window_radians * 0.5,
		24,
		target_color,
		line_width * 2.0,
		true
	)
	var needle_end := center + Vector2.from_angle(needle_angle) * (radius - line_width)
	draw_line(center, needle_end, needle_color, line_width, true)
	draw_circle(center, line_width * 1.2, needle_color)

func start():
	await get_tree().process_frame
	active = true
	needle_angle = randf_range(0, TAU)
	target_angle = needle_angle + randf_range(PI, TAU)
	fail_angle = target_angle+(target_window_radians*0.5)
	show()
	pass

func stop():
	hide()
	active = false
	fail_angle = 0
	pressed.emit(false)
	
	pass

func _is_needle_in_target_window() -> bool:
	var distance_to_target := absf(wrapf(needle_angle - target_angle, -PI, PI))
	return distance_to_target <= target_window_radians * 0.5

func _process(delta):
	if not active:
		return
	if Input.is_action_just_pressed("Space"):
		if _is_needle_in_target_window():
			pressed.emit(true)
		else:
			pressed.emit(false)
		stop()
		return

	needle_angle += needle_speed * delta
	
	if needle_angle >= fail_angle:
		DisplayServer.beep()
		stop()
