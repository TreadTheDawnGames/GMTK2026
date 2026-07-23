class_name DepthEncounterConfig
extends Resource

## Shared Inspector tuning for recurring underground encounter chambers.
## Vertical values use gameplay depth measured from the miner's feet.

@export_category("Depth Schedule")
@export_range(1, 1_000_000, 1) var first_floor_depth: int = 1_000
@export_range(1, 1_000_000, 1) var repeat_interval_depth: int = 5_000
## Stops generating chambers after the authored gift encounters run out.
@export_range(0, 100, 1) var maximum_floor_count: int = 4

@export_category("Chamber")
@export_range(1, 2_000, 1) var chamber_height_rows: int = 100
@export_range(1, 512, 1) var chamber_width_cells: int = 100

@export_category("Flow")
## Waits before the timing bar accepts input after dialogue.
@export_range(0.0, 5.0, 0.1) var post_dialogue_buffer_seconds: float = 0.5


## Returns the next authored encounter floor, or -1 when none remain.
func get_next_floor_depth(
	current_depth: int,
	maximum_depth: int
) -> int:
	var next_floor_depth: int
	if current_depth < first_floor_depth:
		next_floor_depth = first_floor_depth
	else:
		var next_floor_index := floori(
			float(current_depth - first_floor_depth)
			/ float(repeat_interval_depth)
		) + 1
		next_floor_depth = (
			first_floor_depth
			+ next_floor_index * repeat_interval_depth
		)
	if next_floor_depth > maximum_depth:
		return -1
	var floor_index := roundi(
		float(next_floor_depth - first_floor_depth)
		/ float(repeat_interval_depth)
	)
	if floor_index >= maximum_floor_count:
		return -1
	return next_floor_depth
