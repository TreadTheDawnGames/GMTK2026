class_name RunState
extends Node

## Stores gameplay depth, combo, and hit counts for one run.

signal depth_changed(depth: int)
signal bottom_reached
signal run_reset

@export var config: MiningConfig

var depth: int = 0 # Gameplay depth descended from the starting surface.
var mining_y: int = 0 # Authoritative terrain row beneath the player's feet.
var combo: int = 0
var successful_hits: int = 0
var failed_hits: int = 0
var has_reached_bottom: bool = false

var remaining_depth: int:
	get:
		return maxi(config.total_run_depth - depth, 0)


## Starts a new run when the node loads.
func _ready() -> void:
	reset_run()


## Resets depth, combo, and hit counts.
func reset_run() -> void:
	depth = 0
	mining_y = config.initial_surface_row
	combo = 0
	successful_hits = 0
	failed_hits = 0
	has_reached_bottom = false
	depth_changed.emit(depth)
	run_reset.emit()


## Records a successful hit and the player's new depth.
func record_success(
	depth_gained: int,
	new_mining_y: int,
	resolved_combo: int,
	count_as_timing_success: bool = true
) -> void:
	combo = resolved_combo
	if count_as_timing_success:
		successful_hits += 1
	depth = mini(
		depth + maxi(depth_gained, 0),
		config.total_run_depth
	)
	mining_y = clampi(
		maxi(new_mining_y, mining_y),
		config.initial_surface_row,
		config.get_bottom_surface_row()
	)
	depth_changed.emit(depth)
	if depth >= config.total_run_depth and not has_reached_bottom:
		has_reached_bottom = true
		bottom_reached.emit()


## Adopts the resolved combo and records one failed hit.
func record_failure(resolved_combo: int) -> void:
	combo = resolved_combo
	failed_hits += 1
