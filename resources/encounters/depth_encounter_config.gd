class_name DepthEncounterConfig
extends Resource

## Stores the named character schedule and shared chamber settings.
## Vertical values use gameplay depth measured from the miner's feet.

@export_category("Named Encounters")
## Lists every merchant and the final thief in authored depth order.
@export var encounters: Array[DepthCharacterEncounter] = []

@export_category("Chamber")
@export_range(1, 2_000, 1) var chamber_height_rows: int = 100
@export_range(1, 512, 1) var chamber_width_cells: int = 100

@export_category("Flow")
## Waits before the timing bar accepts input after dialogue.
@export_range(0.0, 5.0, 0.1) var post_dialogue_buffer_seconds: float = 0.5


## Reports whether a terrain row belongs to any encounter chamber.
func is_chamber_row(depth: int, total_run_depth: int) -> bool:
	for encounter in encounters:
		if encounter == null:
			continue
		var rows_until_floor := (
			encounter.resolve_depth(total_run_depth) - depth
		)
		if rows_until_floor > 0 and rows_until_floor <= chamber_height_rows:
			return true
	return false
