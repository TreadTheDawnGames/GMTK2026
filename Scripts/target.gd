class_name TimingTarget
extends Panel

## Tracks whether one timing target has already been collected this set.

var is_hit: bool = false


## Marks this target collected and hides it until the set resets.
func hit() -> void:
	is_hit = true
	hide()


## Makes this target available for the next set.
func unhit() -> void:
	is_hit = false
	show()
