extends PanelContainer
class_name SliderTimingWindow

signal pressed(success:bool)

@onready var target: Panel = %Target
@onready var slider: Panel = %Slider
@onready var backing: Control = %Backing

@export var speed : float = 500.0
@export var speed_multiplier : float = 1.0

@export var grace : float = 10.0
@export var target_size : float = 32.0
@export var slider_size : float = 9.0

@export var one_shot : bool = false
@export var fixed_window : float = -1

var direction : float = 1.0


func _ready():
	target.offset_right = target.offset_left + target_size
	target.offset_transform_position.x = -target.size.x * 0.5
	
	slider.offset_right = slider.offset_left + slider_size
	slider.offset_transform_position.x = -slider.size.x * 0.5
	await get_tree().process_frame
	randomize_target()
	if one_shot:
		stop()

func target_half_width() -> float:
	return target.size.x*0.5 + grace

func slider_half_width() -> float:
	return slider.size.x*0.5 + grace

func start():
	if one_shot:
		slider.position.x = 0.0
		direction = 1.0
	randomize_target()
	show()
	set_process(true)

func pause():
	set_process(false)

func stop():
	hide()
	set_process(false)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("Space"):
		if slider.position.x < target.position.x + target_half_width() and slider.position.x > target.position.x - target_half_width():
			randomize_target()
			pressed.emit(true)
		else:
			pressed.emit(false)
		if one_shot:
			stop()
		
	
	slider.position.x += speed * direction * delta * speed_multiplier
	if (slider.position.x <= 0.0+slider_half_width() and direction < 0) or (slider.position.x >= backing.size.x-slider_half_width() and direction > 0):
		direction *= -1
		if one_shot:
			pressed.emit(false)
			stop()
	

func randomize_target():
	target.position.x = clamp((randf() if fixed_window < 0 else fixed_window)* backing.size.x, target_half_width(), backing.size.x - target_half_width())
	
