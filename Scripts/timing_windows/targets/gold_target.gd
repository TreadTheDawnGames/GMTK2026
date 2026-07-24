extends TimingTarget
class_name MovingTarget

@onready var bounce_sound: AudioStreamPlayer2D = %BounceSound

var track : float = 700
var initial_position : float
var curr_pos : float
var direction : float = 1.0

@export var speed : float = 250

func place(_placement_width : float) -> float:
	initial_position = randf()*_placement_width
	curr_pos = initial_position
	
	return initial_position

func _process(delta: float) -> void:
	position.x += speed * direction * delta
	curr_pos = position.x
	var left_edge := slider_half_width()
	var right_edge := track - slider_half_width()
	var hit_left_edge := curr_pos <= left_edge and direction < 0.0
	var hit_right_edge := (
		curr_pos >= right_edge
		and direction > 0.0
	)
	if hit_left_edge or hit_right_edge:
		direction *= -1
		bounce_sound.play()

func slider_half_width() -> float:
	return size.x * 0.5
