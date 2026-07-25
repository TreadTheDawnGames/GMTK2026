@tool
class_name DepthEncounterConfig
extends Resource

## Stores the named character schedule and shared chamber settings.
## Vertical values use gameplay depth measured from the miner's feet.
## @tool because the cutscene terrain preview calls the chamber methods while
## editing; without it Godot loads this resource as a placeholder instance.

@export_category("Named Encounters")
## Lists every character and the final thief in authored depth order.
@export var encounters: Array[DepthCharacterEncounter] = []

@export_category("Placement")
## How far right of the terrain centre an encounter's cast and its stage stand.
##
## This lives on the shared schedule rather than on the controller because the
## editor needs the same number. It used to exist only at runtime, so a stage
## authored in the editor sat on the mining face while the game placed it this
## many cells to the right — every marker, actor and prop was off by exactly
## this distance, and nothing in the editor could show it.
@export_range(-64, 64, 1) var encounter_horizontal_offset_cells: int = 22

@export_category("Chamber")
@export_range(1, 2_000, 1) var chamber_height_rows: int = 100
@export_range(1, 512, 1) var chamber_width_cells: int = 100
## Narrows the ceiling and eases outward toward the floor. Logic and rendering
## both consume these bounds, so the visible wall never invents a landing.
@export_range(0, 64, 1) var chamber_ceiling_inset_cells: int = 12

@export_category("Flow")
## Waits before the timing bar accepts input after dialogue.
@export_range(0.0, 5.0, 0.1) var post_dialogue_buffer_seconds: float = 0.5
## Stable identities gathered at the cafe in this authored order.
@export var gathering_actor_ids: Array[StringName] = []


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


## Returns the first open row of an encounter tunnel.
## A hit may skip every row between this ceiling and the floor, so flow
## controllers compare against this threshold rather than one exact impact.
func get_encounter_ceiling_depth(
	encounter: DepthCharacterEncounter,
	total_run_depth: int
) -> int:
	if encounter == null:
		return -1
	return maxi(
		encounter.resolve_depth(total_run_depth) - chamber_height_rows,
		0
	)


## Returns the first encounter floor whose ceiling a proposed fall crosses.
## Mining uses this to stop an oversized hit at the room instead of letting its
## already-calculated landing target skip below the cutscene presentation.
func get_first_crossed_encounter_floor_depth(
	start_depth: int,
	end_depth: int,
	total_run_depth: int
) -> int:
	if end_depth <= start_depth:
		return -1
	for encounter in encounters:
		if encounter == null:
			continue
		var ceiling_depth := get_encounter_ceiling_depth(
			encounter,
			total_run_depth
		)
		if start_depth < ceiling_depth and end_depth >= ceiling_depth:
			return encounter.resolve_depth(total_run_depth)
	return -1


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
