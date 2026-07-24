class_name TimingTarget
extends Panel

signal freeze(stopped : bool)
## Tracks whether one timing target has already been collected this set.

@export var my_width : float = 16
var is_hit: bool = false

var use_image:bool=true:
	set(value):
		use_image = value
		$TextureRect.visible = value

func initialize():
	Utils.set_control_width(self, my_width)
	pass

## Marks this target collected and hides it until the set resets.
func hit(_timing_window : SliderTimingWindow = null) -> void:
	is_hit = true
	hide()


## Makes this target available for the next set.
func unhit() -> void:
	is_hit = false
	show()

func is_overlapping(_input_rect : Rect2) -> bool:
	return false

## Chooses the target's desired horizontal center inside the timing bar.
func place(placement_width : float) -> float:
	var target_center_x := (randf() * placement_width)
	return target_center_x
