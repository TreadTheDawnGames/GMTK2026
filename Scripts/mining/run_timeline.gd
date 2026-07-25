class_name RunTimeline
extends Node

## How it works:
## - The run-intro flow completion starts one controllable-play clock.
## - Run reset clears and stops the clock until the next intro completion.
## - A cinematic-flow owner pauses accumulation without discarding fractions.
## - Whole-second changes are emitted for presentation consumers.
## - The invariant is that every run-time consumer receives the same second.

signal run_time_changed(elapsed_seconds: int)

@export_category("References")
@export var cinematic_flow: MiningCinematicFlow

var elapsed_seconds: int:
	get:
		return _elapsed_seconds

var _elapsed_seconds: int = 0
var _subsecond_progress: float = 0.0
var _is_running: bool = false


## Keeps the clock alive while the tree is paused; flow ownership still gates it.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


## Accumulates only controllable run time and emits once per changed whole second.
func _process(delta: float) -> void:
	if (
		not _is_running
		or cinematic_flow == null
		or cinematic_flow.is_busy()
		or delta <= 0.0
		or is_nan(delta)
		or is_inf(delta)
	):
		return
	_subsecond_progress += delta
	var completed_seconds := floori(_subsecond_progress)
	if completed_seconds <= 0:
		return
	_subsecond_progress -= float(completed_seconds)
	_elapsed_seconds += completed_seconds
	run_time_changed.emit(_elapsed_seconds)


## Starts after the named opening flow has completely released its gate.
func _on_cinematic_flow_finished(owner: StringName) -> void:
	if owner == RunIntroController.FLOW_OWNER:
		_is_running = true
		set_process(true)


## Clears and stops the canonical clock before a new opening sequence.
func _on_run_reset() -> void:
	_is_running = false
	_elapsed_seconds = 0
	_subsecond_progress = 0.0
	set_process(false)
	run_time_changed.emit(_elapsed_seconds)
