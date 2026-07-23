class_name TimingWindowTask
extends RepairTask
## Completes after repeatedly pressing Space while the rotating needle is in the target arc.

@export_range(0.25, 5.0, 0.05) var rotations_per_second := 0.75
@export_range(10.0, 120.0, 1.0) var target_window_degrees := 35.0
@export_range(1, 10, 1) var required_hits := 3

@onready var _timing_dial: TimingDial = %TimingDial
@onready var _status_label: Label = %StatusLabel

var _needle_angle := 0.0
var _target_angle := 0.0
var _completed_hits := 0
var _rotation_direction := 1.0
var _hit_armed := true


func _task_ready() -> void:
	_completed_hits = 0
	_rotation_direction = 1.0
	_hit_armed = true
	_target_angle = randf_range(0.0, TAU)
	_needle_angle = wrapf(_target_angle + PI, 0.0, TAU)
	_status_label.text = "0 / %d LOCKS" % required_hits
	_update_dial()


func _process(delta: float) -> void:
	super._process(delta)
	if complete:
		return
	_needle_angle = wrapf(
		_needle_angle + TAU * rotations_per_second * _rotation_direction * delta,
		0.0,
		TAU
	)
	_timing_dial.needle_angle = _needle_angle
	# A hit cannot be counted again until the reversed needle leaves the target window.
	if not _hit_armed and not _is_needle_in_target_window():
		_hit_armed = true


func _input(event: InputEvent) -> void:
	super._input(event)
	var key_event := event as InputEventKey
	if (
		key_event == null
		or not key_event.pressed
		or key_event.echo
		or key_event.keycode != KEY_SPACE
		or complete
	):
		return
	get_viewport().set_input_as_handled()
	if _hit_armed and _is_needle_in_target_window():
		_completed_hits += 1
		_rotation_direction *= -1.0
		_hit_armed = false
		if _completed_hits >= required_hits:
			_status_label.text = "%d / %d LOCKED" % [_completed_hits, required_hits]
			_succeed()
		else:
			_status_label.text = "%d / %d LOCKS - REVERSED" % [_completed_hits, required_hits]
	else:
		_status_label.text = "MISSED - TRY AGAIN"


func _is_needle_in_target_window() -> bool:
	var distance_to_target := absf(wrapf(_needle_angle - _target_angle, -PI, PI))
	return distance_to_target <= deg_to_rad(target_window_degrees) * 0.5


func _update_dial() -> void:
	if _timing_dial == null:
		return
	_timing_dial.target_angle = _target_angle
	_timing_dial.target_window_radians = deg_to_rad(target_window_degrees)
	_timing_dial.needle_angle = _needle_angle
