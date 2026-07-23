class_name DepthEncounterConfig
extends Resource

## Shared Inspector tuning for recurring underground encounter chambers.
## Floor and interval values use rendered depth pixels from the miner's feet.

@export_category("Depth Schedule")
@export_range(8, 1_000_000, 8) var first_floor_depth_px: int = 1_000
@export_range(8, 1_000_000, 8) var repeat_interval_px: int = 5_000

@export_category("Chamber")
@export_range(8, 2_000, 1) var chamber_height_px: int = 100
@export_range(64, 2_000, 8) var chamber_width_px: int = 800

@export_category("Flow")
@export_range(0.0, 5.0, 0.1) var post_dialogue_buffer_seconds: float = 0.5


## Returns the next encounter floor below the player's current depth.
func get_next_floor_depth(current_depth_px: int) -> int:
	if current_depth_px < first_floor_depth_px:
		return first_floor_depth_px
	var completed_intervals := floori(
		float(current_depth_px - first_floor_depth_px)
		/ float(repeat_interval_px)
	) + 1
	return (
		first_floor_depth_px
		+ completed_intervals * repeat_interval_px
	)
