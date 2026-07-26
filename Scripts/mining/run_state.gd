class_name RunState
extends Node

## Stores gameplay position, combo, and hit counts for one run.

signal depth_changed(depth: int)
signal thief_reached
signal run_reset

@export var config: MiningConfig

var save_game : SaveGame

var depth: int = 0 # Gameplay depth descended from the starting surface.
var mining_x: int = 0 # Authoritative terrain column beneath the player.
var mining_y: int = 0 # Authoritative terrain row beneath the player's feet.
var combo: int = 0
var successful_hits: int = 0
var failed_hits: int = 0
var has_reached_thief: bool = false

var times_pressed : int = 0

# Backward-compatible name for callers that still treat reaching the thief as
# reaching the run bottom. Keep both names backed by the same state.
var has_reached_bottom: bool:
	get:
		return has_reached_thief
	set(value):
		has_reached_thief = value

var remaining_depth: int:
	get:
		return maxi(config.total_run_depth - depth, 0)

var distance_since_thief: int:
	get:
		return maxi(depth - config.total_run_depth, 0)

var displayed_distance: int:
	get:
		return (
			distance_since_thief
			if has_reached_thief
			else remaining_depth
		)


## Starts a new run when the node loads.
func _ready() -> void:
	save_game = SaveGame.load_savegame()
	# Loading the autoload initializes runtime counters without erasing saved
	# map presentation. An explicit New Run still clears that presentation.
	reset_run(false)


## Resets depth, combo, and hit counts.
func reset_run(clear_saved_run: bool = true) -> void:
	if (
		clear_saved_run
		and save_game != null
		and not save_game.gem_outcrops.is_empty()
	):
		save_game.gem_outcrops.clear()
		save_game.write_savegame()
	depth = 0
	mining_x = config.terrain_width_cells / 2
	mining_y = config.initial_surface_row
	combo = 0
	successful_hits = 0
	failed_hits = 0
	has_reached_thief = false
	depth_changed.emit(depth)
	run_reset.emit()


## Records a successful hit and the player's new depth.
func record_success(
	depth_gained: int,
	new_mining_position: Vector2i,
	resolved_combo: int,
	count_as_timing_success: bool = true
) -> void:
	combo = resolved_combo
	if count_as_timing_success:
		successful_hits += 1
	depth = mini(
		depth + maxi(depth_gained, 0),
		MiningConfig.MAX_PLAYABLE_DEPTH
	)
	mining_x = clampi(
		new_mining_position.x,
		0,
		config.terrain_width_cells - 1
	)
	mining_y = clampi(
		maxi(new_mining_position.y, mining_y),
		config.initial_surface_row,
		config.get_bottom_surface_row()
	)
	depth_changed.emit(depth)
	if depth >= config.total_run_depth and not has_reached_thief:
		has_reached_thief = true
		thief_reached.emit()


## Adopts the resolved combo and records one failed hit.
func record_failure(resolved_combo: int) -> void:
	combo = resolved_combo
	failed_hits += 1
