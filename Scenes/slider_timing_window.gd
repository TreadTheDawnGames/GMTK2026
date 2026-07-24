extends PanelContainer
class_name SliderTimingWindow

## Moves the timing slider and tracks targets until every target is hit.

## Reports whether the press hit and which half of the bar received the hit.
signal pressed(success: bool, hit_direction: int)

@export var target_packed_scenes : Array[PackedScene] = [preload("uid://16edwc1adi0x")]

@onready var slider: Panel = %Slider
@onready var backing: Control = %Backing
@onready var bounce_sound: AudioStreamPlayer2D = %BounceSound


@export var speed: float = 500.0
@export var speed_multiplier: float = 1.0

@export var grace: float = 7.0
@export var targets_use_image: bool = true

@export var slider_size: float = 5.0

@export var one_shot: bool = false
@export var fixed_window: float = -1.0
@export var animation_repeats: int = 3
@export var animation_color : Color = Color.RED

@export var desired_target_heirarchy_index : int = 1

var direction: float = 1.0
# Growth is bounded by the configured baseline plus nine authored pickaxe
# unlocks; a lost streak prunes the collection back to its baseline.
var targets: Array[TimingTarget] = []
var _starting_target_count: int = 1


## Creates the configured target baseline and prepares one-shot recovery bars.
func _ready() -> void:
	while targets.size() < _starting_target_count:
		add_target()
	Utils.set_control_width(slider, slider_size)
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
	if target_packed_scenes.size() == 0:
		push_error(name, " does not have any target scenes.")
		return
	#print(name, " ", target_packed_scenes)
	var new_target := target_packed_scenes.pick_random().instantiate() as TimingTarget
	if new_target == null:
		push_error("The timing target scene must create a TimingTarget.")
		return
	new_target.initialize()
	new_target.freeze.connect(on_freeze)
	backing.add_child(new_target)
	backing.move_child(new_target, desired_target_heirarchy_index)
	targets.append(new_target)
	
	if is_node_ready():
		randomize_target(new_target)
		clamp_target(new_target)


## Sets the target baseline restored whenever a streak ends.
func set_starting_target_count(target_count: int) -> void:
	_starting_target_count = maxi(target_count, 1)
	if is_node_ready():
		remove_all_extra_targets()


## Rebuilds the active targets from a cumulative pickaxe scene pool.
func set_target_pool(new_target_scenes: Array[PackedScene]) -> void:
	if new_target_scenes.is_empty():
		push_warning("The timing target pool cannot be empty.")
		return
	target_packed_scenes = new_target_scenes.duplicate()
	if not is_node_ready():
		return
	for target in targets:
		target.queue_free()
	targets.clear()
	while targets.size() < _starting_target_count:
		add_target()


## Adds one earned target from a specific pickaxe's authored collection.
func add_target_from_pool(new_target_scenes: Array[PackedScene]) -> void:
	if new_target_scenes.is_empty():
		return
	target_packed_scenes = new_target_scenes.duplicate()
	add_target()


## Restores the timing bar to its configured starting target count.
func remove_all_extra_targets() -> void:
	while targets.size() > _starting_target_count:
		remove_target()
	while targets.size() < _starting_target_count:
		add_target()
	for baseline_target in targets:
		baseline_target.initialize()
		clamp_target(baseline_target)


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
			target.hit(self)

		var success: bool = not hit_targets.is_empty()
		var hit_direction: int = 0
		if success:
			hit_direction = _get_slider_hit_direction()
		pressed.emit(success, hit_direction)
		var all_targets_hit := targets.all(
			func(target: TimingTarget) -> bool:
				return target.is_hit
		)
		if all_targets_hit and not one_shot:
			reset_all_targets()

		if one_shot:
			await pause(true)
			stop()

	slider.position.x += speed * direction * delta * speed_multiplier

	var left_edge := slider_half_width()
	var right_edge := backing.size.x - slider_half_width()
	var hit_left_edge := slider.position.x <= left_edge and direction < 0.0
	var hit_right_edge := (
		slider.position.x >= right_edge
		and direction > 0.0
	)
	if hit_left_edge or hit_right_edge:
		direction *= -1
		bounce_sound.play()
		if one_shot:
			pressed.emit(false, 0)
			stop()


## Maps a successful slider position to left, center-neutral, or right.
func _get_slider_hit_direction() -> int:
	var hit_offset_from_center: float = (
		slider.position.x - backing.size.x * 0.5
	)
	if is_zero_approx(hit_offset_from_center):
		return 0
	return -1 if hit_offset_from_center < 0.0 else 1


## Moves one target to a valid position inside its backing bar.
func randomize_target(target: TimingTarget) -> void:
	var target_touple : Array[float] = target.place(backing.size.x)
	var target_center_x = target_touple[0] if fixed_window < 0.0 else fixed_window*backing.size.x
	
	target_center_x = clampf(
		target_center_x,
		target_touple[1] * 0.5,
		backing.size.x - target_touple[1] * 0.5
	)
	var rerolls : int = 5
	var do_again:bool =true
	while do_again and rerolls > 0:
		for _target in targets:
			if _target == target:
				continue
			if target.get_rect().intersects(_target.get_rect()):
				
				target_center_x = target_center_x + clampf(
				target_center_x + target_touple[1] + 25 * (randf() - randf()),
				target_touple[1],#* 0.5,
				backing.size.x - target_touple[1],# * 0.5
				)
				do_again = true
				target_center_x = clampf(
				target_center_x,
				target_touple[1] ,#* 0.5,
				backing.size.x - target_touple[1],# * 0.5
				)

				break
			else:
				do_again = false
		rerolls -= 1
	
	target.position.x = target_center_x
		
func on_freeze(stopped:bool):
	if stopped:
		pause(false)
	else:
		start()
	pass

func clamp_target(target : TimingTarget):
	target.position.x = clampf(
		target.position.x,
		target.size.x * 0.5,
		backing.size.x - target.size.x * 0.5
	)
