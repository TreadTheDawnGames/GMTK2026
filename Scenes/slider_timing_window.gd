extends PanelContainer
class_name SliderTimingWindow

## Moves the timing slider and tracks targets until every target is hit.

## Reports whether the press hit and which half of the bar received the hit.
signal pressed(success: bool, hit_direction: int, combo : int)
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
@export var stop_one_shot_when_done: bool = true
@export var fixed_window: float = -1.0
@export var space_between_targets : float = 5.0
@export var animation_repeats: int = 3
@export var animation_color : Color = Color.RED

@export var desired_target_heirarchy_index : int = 1

var direction: float = 1.0
# Growth is bounded by the configured baseline plus nine authored pickaxe
# unlocks; a lost streak prunes the collection back to its baseline.
var targets: Array[TimingTarget] = []
var consecutive_hits : int = 0
var _starting_target_count: int = 1


## Creates the configured target baseline and prepares one-shot recovery bars.
func _ready() -> void:
	while targets.size() < _starting_target_count:
		add_target()
	Utils.set_control_width(slider, slider_size)
	await get_tree().process_frame
	randomize_all_targets()
	#for target in targets:
		#randomize_target(target)
	
	reset_one_shot()
	if one_shot:
		stop()


## Returns the slider edge area including input grace.
func slider_half_width() -> float:
	return slider.size.x * 0.5 + grace


## Shows the bar and prepares a fresh target for one-shot recovery.
func start() -> void:
	backing.size.x = size.x
	reset_one_shot()
	show()
	set_process(true)

func reset_one_shot():
	if one_shot:
		slider.position.x = 0.0
		direction = 1.0
		reset_all_targets()
	pass

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
		#randomize_all_targets
		#randomize_target(new_target)
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
	randomize_all_targets()


## Adds one earned target from a specific pickaxe's authored collection.
func add_target_from_pool(new_target_scenes: Array[PackedScene]) -> void:
	if new_target_scenes.is_empty():
		return
	target_packed_scenes = new_target_scenes.duplicate()
	add_target()
	randomize_all_targets()


## Restores the timing bar to its configured starting target count.
func remove_all_extra_targets() -> void:
	while targets.size() > _starting_target_count:
		remove_target()
	while targets.size() < _starting_target_count:
		add_target()
	for baseline_target in targets:
		baseline_target.initialize()
		clamp_target(baseline_target)
	randomize_all_targets()

## Removes the specified target or the most recently added target.
func remove_target(specific_target : TimingTarget = null) -> void:
	if not targets.is_empty():
		if specific_target:
			targets.erase(specific_target)
			specific_target.ready_to_die.connect(specific_target.queue_free, CONNECT_ONE_SHOT)
		else:
			targets.pop_back().queue_free()


## Shows and rerolls every target after a completed set or lost streak.
func reset_all_targets() -> void:
	var targets_to_remove : Array[TimingTarget] = []
	for target : TimingTarget in targets:
		target.unhit()
		#randomize_target(target)
		if target.single_use:
			targets_to_remove.append(target)
	randomize_all_targets()
	for target in targets_to_remove:
		remove_target(target)
		add_target.call_deferred()
		randomize_all_targets.call_deferred()
	#remove_all_extra_targets()

## Moves the slider and resolves one press against every visible target.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"Space"):
		var hit_targets: Array = targets.filter(
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
			consecutive_hits += 1
		else:
			consecutive_hits = 0
		pressed.emit(success, hit_direction, consecutive_hits)
		if is_all_targets_hit() and not one_shot:
			reset_all_targets()
		if stop_one_shot_when_done:
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
			pressed.emit(false, 0, consecutive_hits)
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
	# Target sets reset on successful hits, so use the authored width directly
	# instead of allocating a temporary position/width array on the hot path.
	var target_width: float = maxf(target.my_width, 1.0)
	var minimum_center_x: float = target_width * 0.5
	var maximum_center_x: float = maxf(
		backing.size.x - minimum_center_x,
		minimum_center_x
	)
	var requested_center_x: float = target.place(backing.size.x)
	if fixed_window >= 0.0:
		requested_center_x = fixed_window * backing.size.x
	target.position.x = clampf(
		requested_center_x,
		minimum_center_x,
		maximum_center_x
	)

	##The direction to shift if there are overlaps. Always towards the center of the board
	#var shift_direction : float = 0
	#if requested_center_x > backing.size.x / 2.0:
		#shift_direction = -1.0
	#elif requested_center_x < backing.size.x / 2.0:
		#shift_direction = 1.0

	##For edge cases when overlap is guaranteed (due to too many targets on the board)
	#var remaining_rerolls : int = 5
	##init to true to ensure the loop runs at least once
	#var overlaps_existing_target: bool = true
	#while overlaps_existing_target and remaining_rerolls > 0:
		#overlaps_existing_target = false
		#for existing_target: TimingTarget in targets:
			#if existing_target == target:
				#continue
			#if requested_center_x + (target_width*0.5) > existing_target.get_rect().position.x and requested_center_x < existing_target.get_rect().position.x + existing_target.get_rect().size.x \
				#or requested_center_x - (target_width*0.5) > existing_target.get_rect().position.x and requested_center_x < existing_target.get_rect().position.x + existing_target.get_rect().size.x:
				#overlaps_existing_target = true
				#print("gonna reroll")
				#print("Targ width: ", target_width)
			#
			#print("requested center: ", requested_center_x)
			#
			#if shift_direction == 0:
				#target.position.x = randf_range(
				#minimum_center_x,
				#maximum_center_x
				#)
			#else:
				#requested_center_x += (target_width*2) * shift_direction
				#pass
		#remaining_rerolls -= 1

	## Placement work stays bounded: at most five rerolls per target reset.
	var rerolls_remaining: int = 5
	while rerolls_remaining > 0:
		var overlaps_existing_target1: bool = false
		for existing_target: TimingTarget in targets:
			if existing_target == target:
				continue
			if target.get_rect().intersects(existing_target.get_rect()):
				overlaps_existing_target1 = true
				break
		if not overlaps_existing_target1:
			break
		target.position.x = randf_range(
			minimum_center_x,
			maximum_center_x
		)
		rerolls_remaining -= 1

func randomize_all_targets():
	var need_reroll : bool = true
	var total_rerolls : int = 0
	while need_reroll:
		#assume safe until told otherwise
		need_reroll = false
		var placed_targs : Array = []
		for target in targets:
			var requested_position = target.place(backing.size.x) if fixed_window < 0.0 else fixed_window * backing.size.x
			target.set_target_position(requested_position, false  )
			var extents = [target.get_left_extent() , target.get_right_extent() , requested_position, target]
		#if extents overlap
			for pt in placed_targs:
				if pt[3] == target:
					continue
				print("extents: ", extents)
				var left_overlap : bool = (extents[0] - space_between_targets > pt[0] and extents[0] - space_between_targets < pt[1])
				var right_overlap : bool = (extents[1] + space_between_targets> pt[0] and extents[1] + space_between_targets< pt[1])
				var center_overlap : bool = (requested_position > pt[0] and requested_position < pt[1])

				if (left_overlap or right_overlap or center_overlap):
					need_reroll = true
					print("yes overlap. Left of: ", left_overlap, " Right of: ", right_overlap)
					break
			print("placed targs: ", placed_targs.size())
		#else
			placed_targs.append(extents)
			var minimum_center_x: float = target.my_width * 0.5
			var maximum_center_x: float = maxf(
				backing.size.x - minimum_center_x,
				minimum_center_x
			)
		

			target.set_target_position(clampf(
				extents[2],
				minimum_center_x,
				maximum_center_x), true)
		if total_rerolls > 24:
			printerr("Not an error: Rerolls = ", total_rerolls)
			break
		total_rerolls += 1
	
	pass

func on_freeze(stopped:bool):
	if stopped:
		pause(false)
	else:
		start()
		if is_all_targets_hit() and not one_shot:
			reset_all_targets()

func clamp_target(target : TimingTarget):
	target.position.x = clampf(
		target.position.x,
		target.size.x * 0.5,
		backing.size.x - target.size.x * 0.5
	)

func is_all_targets_hit() -> bool:
	var all_targets_hit := targets.all(
	func(target: TimingTarget) -> bool:
		return target.is_hit)
	return all_targets_hit
