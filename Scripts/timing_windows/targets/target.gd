class_name TimingTarget
extends Panel

signal freeze(stopped : bool)
signal ready_to_die()
signal bounce_requested()
## Tracks whether one timing target has already been collected this set.

@export var my_width : float = 16
var is_hit: bool = false
##Whether this target is removed from the pool of active targets after use
@export var single_use : bool = false

var target_position : float = 0
var _bounce_muted: bool = false
var is_initialized : bool = false

var use_image:bool=true:
	set(value):
		use_image = value
		$TextureRect.visible = value


func set_target_position(pos : float, set_physical_pos : bool = false):
	target_position = pos
	if set_physical_pos:
		position.x = pos
	pass

func get_left_extent() -> float:
	return (target_position)
	
func get_right_extent():
	return target_position + my_width

func initialize() :
	Utils.set_control_width(self, my_width)
	is_initialized = true
	return 

func reset():
	pass

## Receives the owning timing bar's saved bounce preference.
func set_bounce_muted(is_muted: bool) -> void:
	_bounce_muted = is_muted

func is_point_within_bounds(left_extent : float, right_extent : float, grace : float = 0) -> bool:
	return  (left_extent <= get_right_extent() + grace) and (right_extent >= get_left_extent() - grace)

## Marks this target collected and hides it until the set resets.
func hit(_timing_window : SliderTimingWindow = null) -> void:
	is_hit = true
	hide()

## Makes this target available for the next set.
func unhit() -> void:
	if single_use:
		return
	is_hit = false
	show()

func is_overlapping(_input_rect : Rect2) -> bool:
	return false

## Chooses the target's desired horizontal center inside the timing bar.
func place(placement_width : float) -> float:
	var target_center_x := (randf() * placement_width)
	return target_center_x

## Called when the recovery bar successfully saves the streak
func recovery_action():
	pass
