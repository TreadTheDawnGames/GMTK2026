@tool
class_name CutsceneSculptBaker
extends RefCounted

## How it works:
## - Uses the encounter's resolved floor as the sculpt anchor cell.
## - Converts every local sculpt cell to a world cell before querying the
##   existing chamber-row and horizontal-bound rules.
## - Writes open chamber cells and solid cells everywhere else in one batch.
## - carve_right_exit_tunnel adds the shared walk-off corridor to any room.
## - It owns no persistent state and returns after the sculpt has been seeded.
## The invariant is that a baked cell uses the same two config queries as
## procedural terrain, so an untouched bake has identical logical collision.

## Corridor height in terrain cells. Twelve cells is 96 world units, which
## clears the tallest authored actor with room to read as a tunnel rather than
## a slot cut through the wall.
const EXIT_TUNNEL_HEIGHT_CELLS: int = 12
## How much taller the corridor is where it leaves the chamber, and over how
## many cells that extra height falls away. Without the flare the corridor meets
## the wall as a rectangular notch. The length matters as much as the size: let
## it decay over the whole corridor and the chamber never closes down into a
## tunnel at all, it just gets longer.
const EXIT_TUNNEL_MOUTH_FLARE_CELLS: float = 5.0
const EXIT_TUNNEL_MOUTH_FLARE_LENGTH_CELLS: float = 10.0
## How far the corridor roof rises and falls along its length, and how many
## times. A ruler-straight roof is the one thing that reads as cut by a tool
## rather than worn by water.
const EXIT_TUNNEL_ROOF_WAVE_CELLS: float = 2.0
const EXIT_TUNNEL_ROOF_WAVE_COUNT: float = 2.5
## Gap kept between a disc's underside and the floor row. A disc resting on the
## floor exactly still clears a hair of the floor row once rounding is done with
## it, and those cells only stay solid because the guarded floor covers for
## them; the day someone lowers that guard, the ground opens.
const EXIT_TUNNEL_FLOOR_CLEARANCE_CELLS: float = 0.25


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


## Cuts a level walk-off corridor from the room's right wall out through the
## room's own right edge, so an actor can leave the frame at the end of a
## cutscene instead of standing at a rest marker. Any encounter's room can take
## the same corridor; nothing here is specific to one cutscene.
##
## Every disc it sweeps rests exactly on the room's floor row and only ever
## grows upward, so the corridor's own underside is the room's ground. That is
## what makes the walk out need no path of its own, and it is why the cut can
## never open a pocket beneath the ledge the cast is standing on.
static func carve_right_exit_tunnel(
	sculpt: CutsceneTerrainSculpt,
	height_cells: int = EXIT_TUNNEL_HEIGHT_CELLS
) -> void:
	if sculpt == null:
		return
	var floor_row := sculpt.get_floor_local_row()
	if floor_row <= 0 or floor_row >= sculpt.grid_size.y:
		return
	var radius := maxf(float(height_cells) * 0.5, 1.0)
	var mouth_x := (
		float(_find_right_open_edge(sculpt, _get_mouth_reference_row(
			floor_row,
			radius
		)))
		- radius * 0.5
	)
	# One radius past the last column, so the corridor leaves through the room's
	# edge instead of dead-ending a few cells short of it.
	var edge_x := float(sculpt.grid_size.x - 1) + radius
	if edge_x <= mouth_x:
		return
	var brush := CutsceneSculptBrush.new()
	brush.falloff = 0.3
	sculpt.begin_edit()
	# Sampled at half a cell, the same spacing the brush's own line stamp uses,
	# so a swept disc of changing size still leaves no gaps between steps.
	var step_count := maxi(ceili((edge_x - mouth_x) * 2.0), 1)
	for step_index in range(step_count + 1):
		var progress := float(step_index) / float(step_count)
		var cells_from_mouth := (edge_x - mouth_x) * progress
		var flare_fade := 1.0 - minf(
			cells_from_mouth / EXIT_TUNNEL_MOUTH_FLARE_LENGTH_CELLS,
			1.0
		)
		var flare := EXIT_TUNNEL_MOUTH_FLARE_CELLS * flare_fade * flare_fade
		var roof_wave := EXIT_TUNNEL_ROOF_WAVE_CELLS * 0.5 * (
			1.0 - cos(progress * TAU * EXIT_TUNNEL_ROOF_WAVE_COUNT)
		)
		var disc_radius := radius + flare + roof_wave
		brush.radius_cells = disc_radius
		brush.carve(
			sculpt,
			# Resting the disc on the floor rather than centring it at a fixed
			# height is what keeps a taller corridor taller upward only. A fixed
			# centre would sink the flare through the ground.
			Vector2(
				lerpf(mouth_x, edge_x, progress),
				float(floor_row)
					- disc_radius
					- EXIT_TUNNEL_FLOOR_CLEARANCE_CELLS
			)
		)
	# One wear pass over the join. The corridor's own rim is already a swept
	# disc; what reads as cut rather than worn is the corner where the chamber
	# wall meets it.
	var mouth_radius := radius + EXIT_TUNNEL_MOUTH_FLARE_CELLS
	brush.radius_cells = mouth_radius
	brush.smooth(sculpt, Vector2(
		mouth_x,
		float(floor_row) - mouth_radius - EXIT_TUNNEL_FLOOR_CLEARANCE_CELLS
	))
	sculpt.end_edit()


## Returns the row the corridor measures the chamber wall from: one row above
## anything the corridor itself can open. Reading the wall off a row the cut
## cannot reach is what lets this be pressed twice without the mouth walking
## further out of the room each time.
static func _get_mouth_reference_row(floor_row: int, radius: float) -> int:
	return floor_row - ceili(
		radius * 2.0
		+ EXIT_TUNNEL_MOUTH_FLARE_CELLS
		+ EXIT_TUNNEL_ROOF_WAVE_CELLS
	) - 1


## Returns the last open column of one room row, scanned outward from the
## room's own centre column, so rock left standing inside the chamber cannot be
## mistaken for the wall the corridor should start from.
static func _find_right_open_edge(
	sculpt: CutsceneTerrainSculpt,
	local_row: int
) -> int:
	var centre_x := -sculpt.anchor_offset_cells.x
	var edge_x := centre_x
	for local_x in range(centre_x, sculpt.grid_size.x):
		if sculpt.is_solid_local(Vector2i(local_x, local_row)):
			break
		edge_x = local_x
	return edge_x
