extends Control
class_name TimingWindowTask
## Completes after repeatedly pressing Space while the rotating needle is in the target arc.

signal pressed(success : bool, combo : int)          

@export var speed : float = 500.0
@export var grace : float = 10.0
var direction : float = 1.0
var combo : int = 0 :
	set(value):
		combo = value
		combo_label.text = "Combo: " + str(value)
var losing_combo : bool = false

@onready var backing: Panel = %Backing
@onready var target: Panel = %Target
@onready var slider: Panel = %Slider
@onready var combo_label: Label = $Backing/ComboLabel
@onready var timing_dial: TimingDial = %TimingDial

func target_half_width() -> float:
	return target.size.x*0.5 + grace

func slider_half_width() -> float:
	return slider.size.x*0.5 + grace

func _ready():
	randomize_target()
	timing_dial.pressed.connect(
		func(success : bool): 
			if not success:
				combo = 0
				print("failed")
			losing_combo = false
				)
	
func _process(delta: float) -> void:
	if losing_combo:
		return
	
	if Input.is_action_just_pressed("Space"):
		if slider.position.x < target.position.x + target_half_width() and slider.position.x > target.position.x - target_half_width():
			randomize_target()
			combo += 1
			pressed.emit(true, combo)
		else:
			losing_combo = true
			timing_dial.start()
			#pressed.emit(false, combo)
			#combo = 0
	
	if not losing_combo:
		slider.position.x += speed * direction * delta
		if (slider.position.x <= 0.0+slider_half_width() and direction < 0) or (slider.position.x >= backing.size.x-slider_half_width() and direction > 0):
			direction *= -1

func randomize_target():
	target.position.x = clamp(randf() * backing.size.x, target_half_width(), backing.size.x - target_half_width())
	
