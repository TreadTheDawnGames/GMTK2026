extends TimingTarget
class_name MovingTarget

var track : float = 700
var initial_position : float
var direction : float = 1.0

@export var speed : float = 250

func initialize():
	super.initialize()
	direction = _random_direction()

func hit(_timing_window : TimingWindow = null) -> void:
	super.hit(_timing_window)
	direction = _random_direction()


func place(_placement_width : float) -> float:
	track = _placement_width
	initial_position = randf()*_placement_width
	target_position = initial_position
	
	return initial_position

func _process(delta: float) -> void:
	target_position += speed * direction * delta
	position.x = target_position
	var left_edge := slider_half_width()
	var right_edge := track - slider_half_width()
	var hit_left_edge := target_position <= left_edge and direction < 0.0
	var hit_right_edge := (
		target_position >= right_edge
		and direction > 0.0
	)
	if hit_left_edge or hit_right_edge:
		direction *= -1
		bounce_requested.emit()

func slider_half_width() -> float:
	return size.x * 0.5

func _random_direction() -> float:
	var random_direction := randf_range(-1.5, 1.5)
	if absf(random_direction) >= 0.5:
		return random_direction
	if is_zero_approx(random_direction):
		return -0.5 if randf() < 0.5 else 0.5
	return signf(random_direction) * 0.5
