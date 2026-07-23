class_name RunState
extends Node

## Stores depth, combo, and hit counts for one run.

signal depth_changed(depth_px: int)

@export var config: MiningConfig

var depth_px: int = 0 # Rendered pixels descended from the starting surface.
var mining_y: int = 0 # Authoritative terrain row beneath the player's feet.
var combo: int = 0
var successful_hits: int = 0
var failed_hits: int = 0


## Starts a new run when the node loads.
func _ready() -> void:
	reset_run()


## Resets depth, combo, and hit counts.
func reset_run() -> void:
	depth_px = 0
	mining_y = config.initial_surface_row
	combo = 0
	successful_hits = 0
	failed_hits = 0
	depth_changed.emit(depth_px)


## Records a successful hit and the player's new depth.
func record_success(
	depth_advanced_px: int,
	new_mining_y: int,
	resolved_combo: int
) -> void:
	depth_px += maxi(depth_advanced_px, 0)
	mining_y = maxi(new_mining_y, mining_y)
	combo = resolved_combo
	successful_hits += 1
	depth_changed.emit(depth_px)


## Records a missed hit without changing depth.
func record_failure(resolved_combo: int) -> void:
	combo = resolved_combo
	failed_hits += 1
