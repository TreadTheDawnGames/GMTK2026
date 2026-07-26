class_name TimingBridge
extends Node

## Sends Caspian's timing results to the mining controller.

signal attempt_resolved(success: bool, combo: int, hit_direction: int)
## Reports the unique left/center/right outcomes covered by up to five targets.
## The adapter observes Caspian's public target collection without changing his
## timing scene or making terrain code depend on target implementations.
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


## Publishes only when the possible impact keys change. Five targets collapse
## to at most three heavy terrain variants because gameplay resolves direction
## from the slider's left/center/right position, not from target identity.
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


## Resolves every direction a valid press may produce for the visible targets.
func _get_candidate_hit_directions(
	window: SliderTimingWindow
) -> PackedInt32Array:
	var includes_left := false
	var includes_center := false
	var includes_right := false
	var midpoint := window.backing.size.x * 0.5
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
		includes_left = includes_left or hit_left < midpoint
		includes_center = (
			includes_center
			or (hit_left < midpoint and hit_right > midpoint)
		)
		includes_right = includes_right or hit_right > midpoint
	var directions := PackedInt32Array()
	if includes_left:
		directions.append(-1)
	if includes_center:
		directions.append(0)
	if includes_right:
		directions.append(1)
	return directions


## Sends a timing-bar result to mining.
func _on_timing_pressed(
	success: bool,
	combo: int,
	hit_direction: int
) -> void:
	attempt_resolved.emit(success, combo, hit_direction)
