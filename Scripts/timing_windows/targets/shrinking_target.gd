extends TimingTarget
class_name ShrinkingTarget

@export var max_width : float = 64.0
@export var min_width : float = 16.0
@export var shrink_rate : float = 0.9


func initialize():
	my_width = max_width
	Utils.set_control_width(self, my_width)
	

func hit() -> void:
	super.hit()
	var target_size := clampf(
		size.x * shrink_rate,
		min_width,
		max_width
	)
	my_width = target_size
	Utils.set_control_width(self, target_size)
	
