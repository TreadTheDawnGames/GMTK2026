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
## Narrows the ceiling and eases outward toward the floor. Logic and rendering
## both consume these bounds, so the visible wall never invents a landing.
@export_range(0, 64, 1) var chamber_ceiling_inset_cells: int = 12

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


## Returns shared logic/visual chamber bounds for one gameplay depth row.
func get_chamber_horizontal_bounds(
	depth: int,
	total_run_depth: int,
	terrain_width_cells: int
) -> Vector2i:
	var continuous_bounds: Vector2 = (
		get_chamber_horizontal_bounds_at_depth(
			float(depth),
			total_run_depth,
			terrain_width_cells
		)
	)
	var left_cell: int = clampi(
		ceili(continuous_bounds.x),
		0,
		maxi(terrain_width_cells - 1, 0)
	)
	var right_cell: int = clampi(
		floori(continuous_bounds.y),
		left_cell + 1,
		maxi(terrain_width_cells, left_cell + 1)
	)
	return Vector2i(left_cell, right_cell)


## Returns sub-cell chamber bounds so rendered slopes can be antialiased while
## logical cells conservatively stay inside the exact same continuous opening.
func get_chamber_horizontal_bounds_at_depth(
	depth: float,
	total_run_depth: int,
	terrain_width_cells: int
) -> Vector2:
	var safe_terrain_width: float = float(maxi(terrain_width_cells, 1))
	var safe_chamber_width: float = minf(
		float(chamber_width_cells),
		safe_terrain_width
	)
	var left_cell: float = (
		(safe_terrain_width - safe_chamber_width) * 0.5
	)
	var right_cell: float = left_cell + safe_chamber_width
	for encounter in encounters:
		if encounter == null:
			continue
		var rows_until_floor: float = (
			float(encounter.resolve_depth(total_run_depth)) - depth
		)
		if (
			rows_until_floor > 0.0
			and rows_until_floor <= float(chamber_height_rows)
		):
			var maximum_inset: float = minf(
				float(chamber_ceiling_inset_cells),
				maxf((safe_chamber_width - 1.0) * 0.5, 0.0)
			)
			var taper_progress: float = (
				0.0
				if chamber_height_rows <= 1
				else clampf(
					(rows_until_floor - 1.0)
						/ float(chamber_height_rows - 1),
					0.0,
					1.0
				)
			)
			var tapered_inset: float = (
				maximum_inset
				* smoothstep(0.0, 1.0, taper_progress)
			)
			left_cell += tapered_inset
			right_cell -= tapered_inset
			if encounter.opens_right_exit:
				right_cell = float(safe_terrain_width)
			break
	return Vector2(left_cell, right_cell)
