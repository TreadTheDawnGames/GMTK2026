extends TimingTarget
class_name MovingTarget

@onready var bounce_sound: AudioStreamPlayer2D = %BounceSound

var track : float = 700
var initial_position : float
var direction : float = 1.0

@export var speed : float = 250

func initialize():
	super.initialize()
	direction = clamp((randf()-randf())*2.0, -1.5, 1.5)
	if abs(direction) < 0.5:
		direction *= (1.5 / direction )
		print(direction)

func hit(_timing_window : SliderTimingWindow = null) -> void:
	super.hit(_timing_window)
	direction = (randf()-randf())*2.0


func place(_placement_width : float) -> float:
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
		if not _bounce_muted:
			AudioHandler.play_sound(AudioLibrary.BOUNCE)

func slider_half_width() -> float:
	return size.x * 0.5
