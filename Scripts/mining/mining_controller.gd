class_name MiningController
extends Node

## Turns timing results into terrain damage and player depth.

signal mine_resolved(
	depth_advanced_px: int,
	cells_removed: int,
	combo: int,
	effect_strength: float
)
signal mine_missed(combo: int)

@export var config: MiningConfig
@export var run_state: RunState
@export var terrain_manager: TerrainManager
@export var view_controller: ViewController
@export var chip_origin: Marker2D

var _impact_seed: int = 0


## Resolves one timing result. Successful hits break ground and move the player;
## misses only update the failed-hit count.
func resolve_attempt(success: bool, resolved_combo: int) -> void:
	var safe_combo := maxi(resolved_combo, 0)
	if not success:
		run_state.record_failure(safe_combo)
		mine_missed.emit(safe_combo)
		return

	var chip_combo := mini(safe_combo, config.maximum_effect_combo)
	var requested_cells := (
		config.base_chip_cells
		+ config.combo_chip_cells_per_step * chip_combo
	)
	var requested_depth_rows := (
		config.base_chip_depth_rows
		+ config.combo_chip_depth_rows_per_step * chip_combo
	)
	var impact_cell := Vector2i(
		terrain_manager.screen_x_to_terrain_cell_x(
			chip_origin.global_position.x
		),
		run_state.mining_y
	)
	_impact_seed += 1
	var cells_removed := terrain_manager.chip_at(
		impact_cell,
		requested_cells,
		_impact_seed,
		requested_depth_rows
	)
	var new_mining_y := terrain_manager.find_surface_row(
		impact_cell.x,
		run_state.mining_y
	)
	var rows_advanced := maxi(new_mining_y - run_state.mining_y, 0)
	var depth_advanced_px := rows_advanced * config.logical_pixel_scale
	var effect_strength := clampf(
		float(safe_combo) / float(config.maximum_effect_combo),
		0.0,
		1.0
	)

	run_state.record_success(depth_advanced_px, new_mining_y, safe_combo)
	view_controller.follow_mining_y(run_state.mining_y)
	mine_resolved.emit(
		depth_advanced_px,
		cells_removed,
		safe_combo,
		effect_strength
	)
