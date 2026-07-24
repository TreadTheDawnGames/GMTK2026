class_name MiningHud
extends CanvasLayer

## Displays remaining depth and a pace-based estimate to the run bottom.

@export var depth_label: Label
@export var bottom_eta_label: Label
@export var fps_label: Label
@export_range(0.1, 2.0, 0.1) var eta_refresh_seconds: float = 0.25

@onready var _game_state: RunState = RunState.get_global(self)
var _elapsed_run_seconds: float = 0.0
var _eta_refresh_remaining: float = 0.0


## Displays the starting state and counts total time spent in the run.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_update_remaining_depth(_game_state.remaining_depth)
	_update_bottom_eta()


## Refreshes the pace estimate without rebuilding UI every rendered frame.
func _process(delta: float) -> void:
	_elapsed_run_seconds += delta
	_eta_refresh_remaining -= delta
	if _eta_refresh_remaining > 0.0:
		return
	_eta_refresh_remaining = eta_refresh_seconds
	_update_bottom_eta()
	fps_label.text = str("FPS: ", Engine.get_frames_per_second())


## Refreshes both labels immediately when the player gains depth.
func _on_depth_changed(_depth: int) -> void:
	_update_remaining_depth(_game_state.remaining_depth)
	_update_bottom_eta()


## Clears elapsed pace data when a new run begins.
func _on_run_reset() -> void:
	_elapsed_run_seconds = 0.0
	_eta_refresh_remaining = 0.0
	_update_remaining_depth(_game_state.remaining_depth)
	_update_bottom_eta()


## Shows how much gameplay depth remains before the run bottom.
func _update_remaining_depth(remaining_depth: int) -> void:
	depth_label.text = (
		"DEPTH  %s"
		% _format_number(remaining_depth)
	)


## Projects the current average descent pace across all remaining depth.
func _update_bottom_eta() -> void:
	if _game_state.depth <= 0:
		bottom_eta_label.text = "BOTTOM ETA  --:--"
		return
	var estimated_seconds := ceili(
		_elapsed_run_seconds
			* float(_game_state.remaining_depth)
			/ float(_game_state.depth)
	)
	var estimated_hours := floori(
		float(estimated_seconds) / 3_600.0
	)
	var estimated_minutes := floori(
		float(estimated_seconds % 3_600) / 60.0
	)
	var estimated_remaining_seconds := estimated_seconds % 60
	var formatted_eta := (
		"%d:%02d:%02d"
		% [
			estimated_hours,
			estimated_minutes,
			estimated_remaining_seconds,
		]
		if estimated_hours > 0
		else "%02d:%02d"
			% [estimated_minutes, estimated_remaining_seconds]
	)
	bottom_eta_label.text = "BOTTOM ETA  %s" % formatted_eta


## Adds commas to a whole number.
func _format_number(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result
