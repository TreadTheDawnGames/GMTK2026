class_name GroundWalk
extends RefCounted

## How it works:
## - build_path samples an injected floor function once at fixed X intervals.
## - Valid floor samples own every point, including both endpoints.
## - Invalid samples fall back to the caller's original straight segment.
## - walk_along interpolates the cached polyline and adds a visual step lift.
## - Horizontal travel updates facing without depending on terrain classes.
## - The invariant is that a grounded walk cannot end at an authored off-floor Y.

const DEFAULT_STRIDE_PIXELS: float = 24.0
const DEFAULT_STEP_HEIGHT: float = 4.0


## Samples one bounded path; point growth is traversal width / stride and the
## returned packed array is released with the owning walk.
static func build_path(
	start: Vector2,
	end: Vector2,
	floor_sampler: Callable,
	stride_pixels: float
) -> PackedVector2Array:
	if not floor_sampler.is_valid():
		if start.is_equal_approx(end):
			return PackedVector2Array([start])
		return PackedVector2Array([start, end])

	var horizontal_distance := absf(end.x - start.x)
	if is_zero_approx(horizontal_distance):
		var sample_y: float = floor_sampler.call(end.x)
		if is_nan(sample_y) or is_inf(sample_y):
			if start.is_equal_approx(end):
				return PackedVector2Array([start])
			return PackedVector2Array([start, end])
		return PackedVector2Array([Vector2(end.x, sample_y)])
	var segment_count := maxi(
		ceili(
			horizontal_distance / maxf(stride_pixels, 1.0)
		),
		1
	)
	var sampled_path := PackedVector2Array()
	sampled_path.resize(segment_count + 1)
	for point_index in range(segment_count + 1):
		var progress := float(point_index) / float(segment_count)
		var sample_x := lerpf(start.x, end.x, progress)
		var sample_y: float = floor_sampler.call(sample_x)
		if is_nan(sample_y) or is_inf(sample_y):
			return PackedVector2Array([start, end])
		sampled_path[point_index] = Vector2(sample_x, sample_y)
	return sampled_path


## Walks one cached global-space path without invoking its floor sampler again.
static func walk_along(
	target: Node2D,
	path: PackedVector2Array,
	duration: float,
	step_height: float
) -> Tween:
	if not is_instance_valid(target):
		return null
	var resolved_path := path
	if resolved_path.is_empty():
		resolved_path = PackedVector2Array([target.global_position])

	# Cumulative distances are bounded by the cached path and die with the tween.
	var cumulative_distances := _build_cumulative_distances(resolved_path)
	var total_distance := cumulative_distances[-1]

	var tween := target.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(
		_set_walk_progress.bind(
			target,
			resolved_path,
			cumulative_distances,
			total_distance,
			maxf(step_height, 0.0)
		),
		0.0,
		1.0,
		maxf(duration, 0.01)
	).set_trans(Tween.TRANS_LINEAR)
	return tween


## Returns the exact presentation position used by walk_along at one progress.
static func position_along_path(
	path: PackedVector2Array,
	progress: float,
	step_height: float
) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	if path.size() == 1:
		return path[-1]

	var cumulative_distances := _build_cumulative_distances(path)
	return _resolve_path_position(
		path,
		cumulative_distances,
		cumulative_distances[-1],
		progress,
		step_height
	)


## Resolves one point on an already-measured path. Playback passes the
## distances it measured once when the walk began; only the editor scrubber,
## which has no tween to have measured them, builds them per call.
static func _resolve_path_position(
	path: PackedVector2Array,
	cumulative_distances: PackedFloat32Array,
	total_distance: float,
	progress: float,
	step_height: float
) -> Vector2:
	if is_zero_approx(total_distance):
		return path[-1]

	var traveled_distance := clampf(progress, 0.0, 1.0) * total_distance
	var segment_index := 0
	while (
		segment_index < path.size() - 2
		and cumulative_distances[segment_index + 1] < traveled_distance
	):
		segment_index += 1
	var segment_start_distance := cumulative_distances[segment_index]
	var segment_distance := (
		cumulative_distances[segment_index + 1]
		- segment_start_distance
	)
	var segment_progress := (
		0.0
		if is_zero_approx(segment_distance)
		else clampf(
			(traveled_distance - segment_start_distance) / segment_distance,
			0.0,
			1.0
		)
	)
	var step_count := maxi(path.size() - 1, 1)
	var step_lift := absf(
		sin(clampf(progress, 0.0, 1.0) * PI * float(step_count))
	) * maxf(step_height, 0.0)
	return path[segment_index].lerp(
		path[segment_index + 1],
		segment_progress
	) + Vector2.UP * step_lift


static func _build_cumulative_distances(
	path: PackedVector2Array
) -> PackedFloat32Array:
	var distances := PackedFloat32Array()
	distances.resize(path.size())
	var total_distance := 0.0
	for point_index in range(1, path.size()):
		total_distance += path[point_index - 1].distance_to(path[point_index])
		distances[point_index] = total_distance
	return distances


static func _set_walk_progress(
	progress: float,
	target: Node2D,
	path: PackedVector2Array,
	cumulative_distances: PackedFloat32Array,
	total_distance: float,
	step_height: float
) -> void:
	if not is_instance_valid(target) or path.is_empty():
		return
	if path.size() > 1 and not is_zero_approx(total_distance):
		var segment_index := 0
		var traveled_distance := clampf(progress, 0.0, 1.0) * total_distance
		while (
			segment_index < path.size() - 2
			and cumulative_distances[segment_index + 1] < traveled_distance
		):
			segment_index += 1
		var travel_direction := (
			path[segment_index + 1] - path[segment_index]
		)
		_set_facing_from_travel(target, travel_direction.x)
		# Reuses the distances measured when the walk began. Rebuilding them
		# here would allocate a PackedFloat32Array every frame for every
		# walking actor, on a path the tween already owns.
		target.global_position = _resolve_path_position(
			path,
			cumulative_distances,
			total_distance,
			progress,
			step_height
		)
		return
	target.global_position = path[-1]


static func _set_facing_from_travel(
	target: Node2D,
	horizontal_direction: float
) -> void:
	if is_zero_approx(horizontal_direction):
		return
	var facing_direction := 1 if horizontal_direction > 0.0 else -1
	if target.has_method(&"set_facing_direction"):
		target.call(&"set_facing_direction", facing_direction)
		return
	target.scale.x = absf(target.scale.x) * float(facing_direction)
