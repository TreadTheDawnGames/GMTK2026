class_name TimingBridge
extends Node

## Sends Caspian's timing results to the mining controller.

signal attempt_resolved(success: bool, combo: int, hit_direction: int)
## Reports the unique left/center/right outcomes covered by up to five targets.
## The adapter observes Caspian's public target collection and the moving
## target's public motion state without changing his adapt-only timing code.
signal impact_candidates_changed(
	next_combo: int,
	hit_directions: PackedInt32Array
)

@export var timing_window: TimingWindowTask

const MAX_PREDICTED_TARGETS: int = 5

var _last_candidate_combo: int = -1
var _last_candidate_directions := PackedInt32Array()


## Connects Caspian's timing result to mining.
func _ready() -> void:
	if not timing_window.pressed.is_connected(_on_timing_pressed):
		timing_window.pressed.connect(_on_timing_pressed)
	set_process(true)


## Publishes only when the possible impact keys or their urgency changes. Five
## targets collapse to at most three heavy terrain variants because gameplay
## resolves direction from slider position, not from target identity. Ordering
## the variants by the slider's bounce path lets the imminent hit finish first.
func _process(_delta: float) -> void:
	if (
		timing_window == null
		or not timing_window.is_node_ready()
		or timing_window.mining_window == null
	):
		return
	var directions := _get_candidate_hit_directions(
		timing_window.mining_window
	)
	var next_combo := maxi(timing_window.combo + 1, 1)
	if (
		next_combo == _last_candidate_combo
		and directions == _last_candidate_directions
	):
		return
	_last_candidate_combo = next_combo
	_last_candidate_directions = directions
	impact_candidates_changed.emit(next_combo, directions)


## Resolves every possible direction in live time-to-hit order. Stationary
## targets use the slider's bounce path; moving targets use relative velocity
## until either participant bounces, when the next frame recalculates the path.
func _get_candidate_hit_directions(
	window: SliderTimingWindow
) -> PackedInt32Array:
	var midpoint := window.backing_width * 0.5
	var travel_left := window.slider_width * 0.5
	var travel_right := maxf(
		window.backing_width - window.slider_width * 0.5,
		travel_left
	)
	var slider_position := clampf(
		window.slider_position,
		travel_left,
		travel_right
	)
	var moving_right := window.direction >= 0.0
	var slider_speed := absf(window.speed * window.speed_multiplier)
	# Fixed scalars avoid dictionaries, temporary sort arrays, and callables in
	# this per-frame adapter. The output remains bounded to three directions.
	var left_travel := INF
	var center_travel := INF
	var right_travel := INF
	var inspected_targets := 0
	for target: TimingTarget in window.targets:
		if inspected_targets >= MAX_PREDICTED_TARGETS:
			break
		if target == null or target.is_hit or not target.visible:
			continue
		inspected_targets += 1
		var hit_left: float = (
			float(target.get_left_extent()) - window.grace
		)
		var hit_right: float = (
			float(target.get_right_extent()) + window.grace
		)
		hit_left = maxf(hit_left, travel_left)
		hit_right = minf(hit_right, travel_right)
		if hit_left > hit_right:
			continue
		if target is MovingTarget:
			# A moving target can eventually cross every direction. Queue all
			# three, but promote only a collision proven before the next bounce.
			var fallback_travel := (
				(travel_right - travel_left) * 4.0
			)
			left_travel = minf(left_travel, fallback_travel)
			center_travel = minf(
				center_travel,
				fallback_travel + 0.001
			)
			right_travel = minf(
				right_travel,
				fallback_travel + 0.002
			)
			var moving_hit := _get_moving_target_segment_hit(
				window,
				target as MovingTarget,
				slider_position,
				travel_left,
				travel_right,
				slider_speed
			)
			if not is_inf(moving_hit.x):
				var moving_hit_travel := moving_hit.x * slider_speed
				if is_equal_approx(moving_hit.y, midpoint):
					center_travel = minf(
						center_travel,
						moving_hit_travel
					)
				elif moving_hit.y < midpoint:
					left_travel = minf(
						left_travel,
						moving_hit_travel
					)
				else:
					right_travel = minf(
						right_travel,
						moving_hit_travel
					)
			continue
		if hit_left < midpoint:
			left_travel = minf(
				left_travel,
				_get_next_hit_travel(
					slider_position,
					moving_right,
					travel_left,
					travel_right,
					hit_left,
					minf(hit_right, midpoint)
				)
			)
		if hit_left < midpoint and hit_right > midpoint:
			center_travel = minf(
				center_travel,
				_get_next_hit_travel(
					slider_position,
					moving_right,
					travel_left,
					travel_right,
					midpoint,
					midpoint
				)
			)
		if hit_right > midpoint:
			right_travel = minf(
				right_travel,
				_get_next_hit_travel(
					slider_position,
					moving_right,
					travel_left,
					travel_right,
					maxf(hit_left, midpoint),
					hit_right
				)
			)

	var directions := PackedInt32Array()
	for _direction_count in range(3):
		var nearest_travel := INF
		var nearest_direction := 0
		# Center owns exact ties because gameplay resolves the midpoint as zero.
		if center_travel < nearest_travel:
			nearest_travel = center_travel
			nearest_direction = 0
		if left_travel < nearest_travel:
			nearest_travel = left_travel
			nearest_direction = -1
		if right_travel < nearest_travel:
			nearest_travel = right_travel
			nearest_direction = 1
		if is_inf(nearest_travel):
			break
		directions.append(nearest_direction)
		match nearest_direction:
			-1:
				left_travel = INF
			0:
				center_travel = INF
			1:
				right_travel = INF
	return directions


## Predicts a moving target only through the next constant-velocity segment.
func _get_moving_target_segment_hit(
	window: SliderTimingWindow,
	target: MovingTarget,
	slider_position: float,
	travel_left: float,
	travel_right: float,
	slider_speed: float
) -> Vector2:
	var slider_velocity := (
		slider_speed if window.direction >= 0.0 else -slider_speed
	)
	var target_velocity := target.speed * target.direction
	var target_half_width := target.my_width * 0.5
	var target_travel_right := maxf(
		target.track - target_half_width,
		target_half_width
	)
	var target_position := clampf(
		target.target_position,
		target_half_width,
		target_travel_right
	)
	var relative_position := slider_position - target_position
	var hit_radius := target_half_width + window.grace
	if absf(relative_position) <= hit_radius:
		return Vector2(0.0, slider_position)

	var segment_seconds := INF
	if slider_velocity > 0.0:
		segment_seconds = (
			(travel_right - slider_position) / slider_velocity
		)
	elif slider_velocity < 0.0:
		segment_seconds = (
			(slider_position - travel_left) / -slider_velocity
		)
	if target_velocity > 0.0:
		segment_seconds = minf(
			segment_seconds,
			(target_travel_right - target_position) / target_velocity
		)
	elif target_velocity < 0.0:
		segment_seconds = minf(
			segment_seconds,
			(target_position - target_half_width) / -target_velocity
		)

	var relative_velocity := slider_velocity - target_velocity
	var hit_seconds := INF
	if relative_position < -hit_radius and relative_velocity > 0.0:
		hit_seconds = (
			(-hit_radius - relative_position) / relative_velocity
		)
	elif relative_position > hit_radius and relative_velocity < 0.0:
		hit_seconds = (
			(hit_radius - relative_position) / relative_velocity
		)
	if hit_seconds < 0.0 or hit_seconds > segment_seconds:
		return Vector2(INF, 0.0)
	return Vector2(
		hit_seconds,
		slider_position + slider_velocity * hit_seconds
	)


## Measures the next intersection with one hit interval along a bouncing bar.
func _get_next_hit_travel(
	slider_position: float,
	moving_right: bool,
	travel_left: float,
	travel_right: float,
	hit_left: float,
	hit_right: float
) -> float:
	if slider_position >= hit_left and slider_position <= hit_right:
		return 0.0
	if moving_right:
		if slider_position < hit_left:
			return hit_left - slider_position
		return (
			travel_right - slider_position
			+ travel_right - hit_right
		)
	if slider_position > hit_right:
		return slider_position - hit_right
	return slider_position - travel_left + hit_left - travel_left


## Sends a timing-bar result to mining.
func _on_timing_pressed(
	success: bool,
	combo: int,
	hit_direction: int
) -> void:
	attempt_resolved.emit(success, combo, hit_direction)
