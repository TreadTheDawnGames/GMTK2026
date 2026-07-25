@tool
class_name CutsceneSculptBaker
extends RefCounted

## How it works:
## - Uses the encounter's resolved floor as the sculpt anchor cell.
## - Converts every local sculpt cell to a world cell before querying the
##   existing chamber-row and horizontal-bound rules.
## - Writes open chamber cells and solid cells everywhere else in one batch.
## - It owns no persistent state and returns after the sculpt has been seeded.
## The invariant is that a baked cell uses the same two config queries as
## procedural terrain, so an untouched bake has identical logical collision.


static func bake_procedural_chamber(
	sculpt: CutsceneTerrainSculpt,
	encounter_config: DepthEncounterConfig,
	encounter: DepthCharacterEncounter,
	mining_config: MiningConfig
) -> void:
	if sculpt == null or encounter_config == null or encounter == null:
		return
	if mining_config == null:
		return

	var anchor_cell := Vector2i(
		floori(float(mining_config.terrain_width_cells) / 2.0),
		mining_config.initial_surface_row
			+ encounter.resolve_depth(mining_config.total_run_depth)
	)
	sculpt.begin_edit()
	for local_y in range(sculpt.grid_size.y):
		for local_x in range(sculpt.grid_size.x):
			var local_cell := Vector2i(local_x, local_y)
			var world_cell := sculpt.local_to_world(local_cell, anchor_cell)
			var depth := world_cell.y - mining_config.initial_surface_row
			var chamber_bounds := (
				encounter_config.get_chamber_horizontal_bounds(
					depth,
					mining_config.total_run_depth,
					mining_config.terrain_width_cells
				)
			)
			var is_open := (
				encounter_config.is_chamber_row(
					depth,
					mining_config.total_run_depth
				)
				and world_cell.x >= chamber_bounds.x
				and world_cell.x < chamber_bounds.y
			)
			sculpt.set_solid_local(local_cell, not is_open)
	sculpt.end_edit()
