extends PanelContainer
class_name SliderTimingWindow

## Moves the timing slider and tracks targets until every target is hit.

signal pressed(success: bool)

const TARGET = preload("uid://16edwc1adi0x")

@onready var slider: Panel = %Slider
@onready var backing: Control = %Backing
@onready var bounce_sound: AudioStreamPlayer2D = %BounceSound


@export var speed: float = 500.0
@export var speed_multiplier: float = 1.0

@export var grace: float = 7.0
@export var max_target_size: float = 128.0
@export var min_target_size: float = 16.0
@export var target_shrink_rate: float = 0.9
@export var targets_use_image: bool = true

@export var slider_size: float = 5.0

@export var one_shot: bool = false
@export var fixed_window: float = -1.0
@export var animation_repeats: int = 3
@export var animation_color : Color = Color.RED

var direction: float = 1.0
var targets: Array[TimingTarget] = []


## Creates the first target and prepares one-shot recovery bars.
func _ready() -> void:
	add_target()
	_set_control_width(slider, slider_size)
	await get_tree().process_frame
	for target in targets:
		randomize_target(target)
	if one_shot:
		stop()


## Returns the slider edge area including input grace.
func slider_half_width() -> float:
	return slider.size.x * 0.5 + grace


## Shows the bar and prepares a fresh target for one-shot recovery.
func start() -> void:
	if one_shot:
		slider.position.x = 0.0
		direction = 1.0
		reset_all_targets()
	show()
	set_process(true)


## Freezes the slider and optionally flashes its recovery warning.
func pause(animate: bool) -> void:
	set_process(false)
	if not animate:
		return
	var tween: Tween = create_tween()
	for _repeat_index in range(animation_repeats):
		tween.tween_property(slider, "modulate", animation_color, 0.1)
		tween.tween_property(slider, "modulate", Color.WHITE, 0.1)
	await tween.finished


## Hides the timing bar and stops its slider.
func stop() -> void:
	hide()
	set_process(false)


## Adds and positions one valid hit target.
func add_target() -> void:
	var new_target := TARGET.instantiate() as TimingTarget
	if new_target == null:
		push_error("The timing target scene must create a TimingTarget.")
		return
	new_target.use_image = targets_use_image
	_set_control_width(new_target, max_target_size)
	backing.add_child(new_target)
	backing.move_child(new_target, 0)
	targets.append(new_target)
	if is_node_ready():
		randomize_target(new_target)


## Restores the timing bar to its original single target.
func remove_all_extra_targets() -> void:
	while targets.size() > 1:
		remove_target()
	if targets.size() < 1:
		printerr("Removed all targets instead of all but one.")
		return
	var primary_target := targets[0]
	_set_control_width(primary_target, max_target_size)
	primary_target.position.x = clampf(
		primary_target.position.x,
		max_target_size * 0.5,
		backing.size.x - max_target_size * 0.5
	)


## Removes the most recently added target.
func remove_target() -> void:
	if not targets.is_empty():
		targets.pop_back().queue_free()


## Shows and rerolls every target after a completed set or lost streak.
func reset_all_targets() -> void:
	for target in targets:
		target.unhit()
		randomize_target(target)

## Moves the slider and resolves one press against every visible target.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"Space"):
		var hit_targets: Array[TimingTarget] = targets.filter(
			func(target: TimingTarget) -> bool:
				var hit_distance := (
					target.size.x * 0.5
					+ slider.size.x * 0.5
					+ grace
				)
				return (
					not target.is_hit
					and absf(slider.position.x - target.position.x)
						<= hit_distance
				)
		)
		for target: TimingTarget in hit_targets:
			target.hit()

		pressed.emit(not hit_targets.is_empty())
		var all_targets_hit := targets.all(
			func(target: TimingTarget) -> bool:
				return target.is_hit
		)
		if all_targets_hit and not one_shot:
			reset_all_targets()

		if one_shot:
			await pause(true)
			stop()
	var beat_in_measure : float = wrap(Conductor.current_beat/Conductor.beats_per_measure,0,1)
	print(beat_in_measure)
	slider.position.x = backing.size.x * (float(beat_in_measure)) #* delta * speed #speed_multiplier#  * delta 
	
	#print("slider pos: ", slider.position)
	#var left_edge := slider_half_width()
	#var right_edge := backing.size.x - slider_half_width()
	#var hit_left_edge := slider.position.x <= left_edge and direction < 0.0
	#var hit_right_edge := (
		#slider.position.x >= right_edge
		#and direction > 0.0
	#)
	#if hit_left_edge or hit_right_edge:
		#direction *= -1
		#bounce_sound.play()
		#if one_shot:
			#pressed.emit(false)
			#stop()


## Moves one target to a valid position inside its backing bar.
func randomize_target(target: TimingTarget) -> void:
	var target_size := clampf(
		target.size.x * target_shrink_rate,
		min_target_size,
		max_target_size
	)
	_set_control_width(target, target_size)
	
	var what_beat : float = 1.0/float((randi() % 4))
	
	var target_center_x := (
		(what_beat if fixed_window < 0 else fixed_window) * backing.size.x
	)
	
	
	target.position.x = clampf(
		target_center_x,
		target_size * 0.5,
		backing.size.x - target_size * 0.5
	)
	
	
	
	#var rerolls : int = 5
	#var do_again:bool =true
	#while do_again and rerolls > 0:
		#for _target in targets:
			#if _target == target:
				#continue
			#if target.get_rect().intersects(_target.get_rect()):
				#
				#target.position.x = target.position.x + clampf(
				#target_center_x + target_size + 25 * (randf() - randf()),
				#target_size ,#* 0.5,
				#backing.size.x - target_size,# * 0.5
				#)
				#do_again = true
				#target.position.x = clampf(
				#target_center_x,
				#target_size ,#* 0.5,
				#backing.size.x - target_size,# * 0.5
				#)
#
				#break
			#else:
				#do_again = false
		#rerolls -= 1
				#


## Changes horizontal size without overriding vertically stretched anchors.
func _set_control_width(control: Control, width: float) -> void:
	control.offset_right = control.offset_left + width
