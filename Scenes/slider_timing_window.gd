extends Control
class_name SliderTimingWindow

## Moves the timing slider and tracks targets until every target is hit.

## Reports whether the press hit and which half of the bar received the hit.
signal pressed(success: bool, hit_direction: int, combo : int)
#@onready var slider: Panel = %Slider
#@onready var backing: Control = %Backing

@export var target_packed_scenes : Array[PackedScene] = [preload("uid://16edwc1adi0x")]
@export var speed: float = 500.0
@export var speed_multiplier: float = 1.0
@export var grace: float = 7.0
@export var targets_use_image: bool = true
@export var slider_width: float = 15.0
@export var one_shot: bool = false
@export var stop_one_shot_when_done: bool = true
@export var fixed_window: float = -1.0
@export var space_between_targets : float = 5.0
@export var animation_repeats: int = 3
@export var animation_color : Color = Color.RED


## The size of the target spawn area
@export var backing_width : float = 700
@export var desired_target_heirarchy_index : int = 1


var direction: float = 1.0
# Growth is bounded by two starting targets plus four authored combo bonuses;
# a lost streak prunes the collection back to its current level's baseline.
var targets: Array[TimingTarget] = []
var consecutive_hits : int = 0
var _starting_target_count: int = 1
var _bounce_muted: bool = false
var _audio_handler: PlayerAudioHandler
@export_range(-1, 1, 1) var preferred_side : int = 0

@export_category("Debug")
@export var DEBUG_run_debug : bool = false :
	set(value):
		DEBUG_run_debug = value
		queue_redraw()
@export var DEBUG_bar_height : float = 81.0
@export var DEBUG_slow_speed : float = 5.0
@export var DEBUG_debug_bar_offset : Vector2 = Vector2.ZERO
@export var DEBUG_backing_color : Color = Color(0.0, 0.0, 0.0, 0.25)
@export var DEBUG_slider_color : Color = Color(1.0, 1.0, 1.0, 1.0)
@export var DEBUG_grace_color : Color = Color(1.0, 0.647, 0.114, 0.686)
@export var DEBUG_target_color : Color = Color(0.0, 0.427, 0.0, 0.25)

var slider_position : float = 0.0:
	set(value):
		slider_position = value
		#slider.position.x = slider_position

## Which position in the tree heirarchy to spawn targets.

## Creates the configured target baseline and prepares one-shot recovery bars.
func _ready() -> void:
	set_process(false)
	#preferred_side = 0
	while targets.size() < _starting_target_count:
		add_target()
	#Utils.set_control_width(slider, slider_width)
	#if not backing.resized.is_connected(on_backing_resized):
		#backing.resized.connect(on_backing_resized)
	await get_tree().process_frame
	#randomize_all_targets()
	#for target in targets:
		#randomize_target(target)
	
	if not one_shot:
		randomize_all_targets()
	reset_one_shot()
	if one_shot:
		stop()
	else:
		set_process(true)
	#backing_width = backing.size.x
	
## Moves the slider and resolves one press against every visible target.
func _process(delta: float) -> void:
	
	if get_tree().paused:
		print("paused")
		return
	
	#Detect a button press (Space, enter, left-click, etc.)
	if Input.is_action_just_pressed(&"primary_action"):
		#assemble an array of targets that we are within bounds of.
		# Also detect if they are already hit, because we can't hit the same one twice.
		var hit_targets: Array = targets.filter(
			func(target: TimingTarget) -> bool:
				return target.is_point_within_bounds(slider_position, slider_position + slider_width, grace) and not target.is_hit) 
		
		#For each target we validly hit, tell the target we hit it.
		for target: TimingTarget in hit_targets:
			target.hit(self)

		# check if we hit anything. if we did, update how many consecutive hits we've gotten.
		# (And update the hit direction for the mining visual)
		var success: bool = not hit_targets.is_empty()
		var hit_direction: int = 0
		if success:
			hit_direction = _get_slider_hit_direction()
			consecutive_hits += 1
			print("success")
			#AudioHandler.play_sound(AudioLibrary.MINE_SOUNDS.pick_random())
		else:
			print("fail")
			consecutive_hits = 0
		
		#Regardless of whether we hit or not, report that we were pressed.
		pressed.emit(success, hit_direction, consecutive_hits)
		
		#If all of our targets have been hit and we are not a one-shot, reset all our targets.
		if is_all_targets_hit() and not one_shot:
			reset_all_targets(false)
		
		# Handle one-shot ending
		if stop_one_shot_when_done:
			if one_shot:
				await pause(true)
				stop()
	
	#update our slider position. (This is what is actually used to detect if we hit a target)
	
	if DEBUG_run_debug:
		if Input.is_action_pressed("DEBUG_left"):
			direction = -1
		if Input.is_action_pressed("DEBUG_right"):
			direction = 1
	
	var mv_spd : float = DEBUG_slow_speed if Input.is_action_pressed("Shift") and DEBUG_run_debug else speed
	var movement_amount : float = mv_spd * direction * speed_multiplier * delta
		
	slider_position = clamp_within_bounds(slider_position + movement_amount, slider_width)
	
	# Detect if we need to bounce
	var left_edge : float = 0.0
	var right_edge : float = backing_width - slider_width
	var hit_left_edge := slider_position <= left_edge and direction < 0.0
	var hit_right_edge := (
		slider_position >= right_edge
		and direction > 0.0
	)
	#if we do need to bounce
	if hit_left_edge or hit_right_edge:
		#reverse our direction and play the sound
		direction *= -1
		play_bounce_sound()
		# and handle the one-shot stuff
		if one_shot:
			pressed.emit(false, 0, consecutive_hits)
			if stop_one_shot_when_done:
				stop()
	
	#slider.position.x = slider_position
	#queue_redraw()
	if DEBUG_run_debug:
		queue_redraw()

func _draw():
	if not DEBUG_run_debug:
		return
	# Draw backing
	draw_rect(Rect2(DEBUG_debug_bar_offset, Vector2(backing_width, DEBUG_bar_height)), DEBUG_backing_color, true)
	
	
	#Draw targets
	for target : TimingTarget in targets:
		draw_rect(Rect2(DEBUG_debug_bar_offset + Vector2(target.target_position - grace, 0), Vector2(target.my_width+(grace*2), DEBUG_bar_height)), DEBUG_grace_color, true)
		draw_rect(Rect2(DEBUG_debug_bar_offset + Vector2(target.target_position, 0), Vector2(target.my_width, DEBUG_bar_height)), DEBUG_target_color, true)
		if target.is_hit:
			draw_rect(Rect2(DEBUG_debug_bar_offset + Vector2(target.target_position, 0), Vector2(target.my_width, 3)), Color.RED, true)
			

	#Draw slider
	draw_rect(Rect2(DEBUG_debug_bar_offset + Vector2(slider_position, 0), Vector2(slider_width, DEBUG_bar_height)), DEBUG_slider_color, true)

	pass

## Shows the bar and prepares a fresh target for one-shot recovery.
func start() -> void:
	#backing.size.x = size.x
	#backing_width = size.x
	reset_one_shot()
	show()
	_set_timing_process(true)

## Resets this timing window to the state it is before a one-shot is fired
func reset_one_shot():
	if one_shot:
		slider_position = 0.0
		direction = 1.0
		reset_all_targets()
	pass

## Freezes the slider and optionally flashes its recovery warning.
func pause(animate: bool) -> void:
	_set_timing_process(false)
	if not animate:
		return
	await play_animation(animation_color, animation_repeats, 0.1)

## Plays a flashing animation on the slider that happens a number of times equal to [repetitions].
func play_animation(color : Color, repetitions : int = 1,  duration : float = 0.1):
	#var tween: Tween = create_tween()
	#for _repeat_index in range(repetitions):
		#tween.tween_property(slider, "modulate", color, duration)
		#tween.tween_property(slider, "modulate", Color.WHITE, duration)
	#await tween.finished

	pass

## Hides the timing bar and stops its slider.
func stop() -> void:
	hide()
	_set_timing_process(false)

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
	new_target.set_bounce_muted(_bounce_muted)
	new_target.freeze.connect(on_freeze)
	if not new_target.bounce_requested.is_connected(play_bounce_sound):
		new_target.bounce_requested.connect(play_bounce_sound)
	#backing.add_child(new_target)
	add_child(new_target)
	#backing.move_child(new_target, desired_target_heirarchy_index)
	move_child(new_target, desired_target_heirarchy_index)
	targets.append(new_target)
	new_target.set_process(is_processing())
	
	if is_node_ready():
		#randomize_all_targets
		#randomize_target(new_target)
		new_target.set_target_position(clamp_within_bounds(new_target.position.x, new_target.size.x))

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
		baseline_target.position.x = clamp_within_bounds(baseline_target.position.x, baseline_target.size.x)
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
func reset_all_targets(full_reset : bool = true) -> void:
	# make an array of targets that need to be removed (one shots)
	var targets_to_remove : Array[TimingTarget] = []
	for target : TimingTarget in targets:
		target.unhit()
		#randomize_target(target)
		if target.single_use:
			targets_to_remove.append(target)
	
	if full_reset:
		#then make sure we have no extra targets
		remove_all_extra_targets()
		for target in targets:
			target.reset()
			
	#then replace any targets we removed
	for target in targets_to_remove:
		remove_target(target)
		## Replace teh target we just removed since it was a single_use
		add_target.call_deferred()
	
	# finally, randomize the targets.
	randomize_all_targets.call_deferred()

## Applies the saved preference to this bar and every dynamic target it owns.
func set_bounce_muted(is_muted: bool) -> void:
	_bounce_muted = is_muted
	for target: TimingTarget in targets:
		target.set_bounce_muted(is_muted)

## Plays the bar's authored bounce sound unless the saved preference mutes it.
func set_audio_handler(audio_handler: PlayerAudioHandler) -> void:
	_audio_handler = audio_handler

## Plays the bar's authored bounce sound unless the saved preference mutes it.
func play_bounce_sound() -> void:
	if _bounce_muted or _audio_handler == null:
		return
	_audio_handler.play_sound(AudioLibrary.BOUNCE)

## Keeps dynamic target motion in lockstep with its owning slider.
func _set_timing_process(is_active: bool) -> void:
	set_process(is_active)
	for target: TimingTarget in targets:
		target.set_process(is_active)

## Maps a successful slider position to left, center-neutral, or right.
func _get_slider_hit_direction() -> int:
	var hit_offset_from_center: float = (
		slider_position - backing_width * 0.5
	)
	if is_zero_approx(hit_offset_from_center):
		return 0
	return -1 if hit_offset_from_center < 0.0 else 1

func randomize_all_targets():
	var need_reroll : bool = true
	var total_rerolls : int = 0
	while need_reroll:
		#assume safe until told otherwise
		need_reroll = false
		var placed_targs : Array = []
		for target in targets:
			var requested_position = target.place(backing_width) if fixed_window < 0.0 else fixed_window * backing_width
			
			if abs(preferred_side) > 0:
				var left_bounds : float = 0
				var right_bounds : float = backing_width
				if preferred_side < 0:
					right_bounds = backing_width * 0.66
				elif preferred_side > 0:
					left_bounds = backing_width * 0.33
				requested_position = remap(requested_position, 0, backing_width, left_bounds, right_bounds)
			target.set_target_position(requested_position, false  )
			var extents = [target.get_left_extent() , target.get_right_extent() , requested_position, target]
		#if extents overlap
			for pt in placed_targs:
				if pt[3] == target:
					continue
				var left_overlap : bool = (extents[0] - space_between_targets > pt[0] and extents[0] - space_between_targets < pt[1])
				var right_overlap : bool = (extents[1] + space_between_targets> pt[0] and extents[1] + space_between_targets< pt[1])
				var center_overlap : bool = (requested_position > pt[0] and requested_position < pt[1])

				if (left_overlap or right_overlap or center_overlap):
					need_reroll = true
					break
		#else
			placed_targs.append(extents)
			var minimum_center_x: float = target.my_width
			var maximum_center_x: float = maxf(
				backing_width - minimum_center_x,
				minimum_center_x
			)
			target.set_target_position(clampf(
				extents[2],
				minimum_center_x,
				maximum_center_x), true)
			clamp_target_within_bounds(target)
				
		if total_rerolls > 5:
			printerr("Not an error: Rerolls = ", total_rerolls)
			break
		total_rerolls += 1
	
	pass

## Targets anchor to the backing's center, so a position placed before the
## backing has its real width re-resolves half a bar away once it lays out,
## which leaves the drawn target outside its own hit bounds. Re-place them the
## moment that width actually arrives.
func on_backing_resized() -> void:
	if is_node_ready():
		randomize_all_targets()

## Called when a target causes this bar to freeze
## Should be in extended class (FreezableTimingBar)
func on_freeze(stopped:bool):
	if stopped:
		pause(false)
	else:
		start()
		if is_all_targets_hit() and not one_shot:
			reset_all_targets()

## Clamps [to_clamp] into a number between zero and [backing_width], and returns the clamped number making sure the width does not extend outside the bounds.
func clamp_within_bounds(to_clamp : float, item_width : float) -> float:
	return clampf(
		to_clamp,
		0.0,
		backing_width - item_width
	)

## Clamps a target withing backing_width's bounds and returns the resulting position.
func clamp_target_within_bounds(target : TimingTarget) -> float:
	var return_me = clamp_within_bounds(target.target_position, target.my_width)
	target.set_target_position(return_me, true)
	return return_me

## Clamps all targets within bounds.
func clamp_all_targets():
	for target in targets:
		clamp_target_within_bounds(target)

## Checks if all active targets are [is_hit].
func is_all_targets_hit() -> bool:
	var all_targets_hit := targets.all(
	func(target: TimingTarget) -> bool:
		return target.is_hit)
	return all_targets_hit

## Called when TimingWindow saves a failed click. 
## This should be in an extended class.
func recovery_action():
	for target in targets:
		target.recovery_action()

## Sets whether this bar's targets should appear everywhere, in the left 2/3, or the right 2/3. 
## This should be in an extended class.
func set_preferred_side(side : int = 0):
	preferred_side = side
