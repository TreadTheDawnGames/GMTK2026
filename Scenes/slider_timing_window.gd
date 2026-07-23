extends PanelContainer
class_name SliderTimingWindow


signal pressed(success:bool)

const TARGET = preload("uid://16edwc1adi0x")

@onready var targets: Array[Panel]
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
	add_target()
	slider.offset_right = slider.offset_left + slider_size
	slider.offset_transform_position.x = -slider.size.x * 0.5
	await get_tree().process_frame
	for target in targets:
		randomize_target(target)
	if one_shot:
		stop()


## Returns the target hit area including input grace.
func target_half_width() -> float:
	return target_size * 0.5 + grace


## Returns the slider edge area including input grace.
func slider_half_width() -> float:
	return slider.size.x*0.5 + grace


## Shows the bar and prepares every target for a new attempt.
func start():
	if one_shot:
		slider.position.x = 0.0
		direction = 1.0
	for target in targets:
		randomize_target(target)
	show()
	set_process(true)


## Freezes the slider without hiding the timing bar.
func pause():
	set_process(false)


## Hides the timing bar and stops its slider.
func stop():
	hide()
	set_process(false)


## Adds and positions one valid hit target.
func add_target():
	var new_target = TARGET.instantiate()
	new_target.offset_right = new_target.offset_left + target_size
	new_target.offset_transform_position.x = -new_target.size.x * 0.5
	backing.add_child(new_target)
	backing.move_child(new_target, 0)
	targets.append(new_target)
	if is_node_ready():
		randomize_target(new_target)


## Restores the timing bar to its original single target.
func remove_all_extra_targets():
	while targets.size() > 1:
		remove_target()


## Removes the most recently added target.
func remove_target():
	if targets.size() > 0:
		targets.pop_back().queue_free()


## Moves the slider and resolves one press against every visible target.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("Space"):
		var hit_targets : Array[Panel] = targets.filter(func(target:Panel): return slider.position.x < target.position.x + target_half_width() and slider.position.x > target.position.x - target_half_width())
		for target : Panel in hit_targets:
			randomize_target(target)
		if hit_targets.size() > 0:
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


## Moves one target to a valid position inside its backing bar.
func randomize_target(target_panel : Panel):
	target_panel.position.x = clamp((randf() if fixed_window < 0 else fixed_window)* backing.size.x, target_half_width(), backing.size.x - target_half_width())
