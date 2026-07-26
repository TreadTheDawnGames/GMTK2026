extends SceneTree

## How it works:
## - Reads every encounter the run schedules and its authored room.
## - Compares the ceiling the config advertises against the room's real opening.
## - Opens the snaking-arrival band of any room that opens lower than advertised.
## - Chips the throat walls outward only, so the guaranteed band stays guaranteed.
## - Rederives the shared four depth masks and saves only the rooms it changed.
## The invariant is that the row the fall is released from is open air in every
## column the snaking path can arrive down.
##
## Why the room's own ceiling is not enough: DepthEncounterController releases
## the fall at the encounter's ceiling depth, which the config derives from the
## chamber height, not from the sculpt. A room whose rock still fills that row
## catches the miner above its cavern, the landing never reaches the floor row,
## the encounter never promotes, and the run stops with him held in the ceiling.

const CONFIG_PATH: String = (
	"res://resources/encounters/depth_encounter_config.tres"
)
const MINING_CONFIG_PATH: String = "res://resources/mining/mining_config.tres"
## Rows of clearance kept above the released row, so rounding or a later ceiling
## tweak cannot put the release back inside rock.
const RELEASE_MARGIN_ROWS: int = 2
## How far past the snaking band the throat walls may wander, in cells. The band
## itself is what has to be open; the chips only stop the break-in reading as a
## bored rectangle, and they never cut inward.
const THROAT_CHIP_CELLS: float = 2.0


func _initialize() -> void:
	var config := load(CONFIG_PATH) as DepthEncounterConfig
	var mining_config := load(MINING_CONFIG_PATH) as MiningConfig
	if config == null or mining_config == null:
		push_error("Arrival throat sweep could not load its configs.")
		quit(1)
		return

	var half_span := mining_config.snake_half_span_cells
	var changed_count := 0
	var failure_count := 0
	for encounter: DepthCharacterEncounter in config.encounters:
		if encounter == null or encounter.terrain_sculpt == null:
			continue
		var sculpt := encounter.terrain_sculpt
		if not sculpt.enabled:
			continue
		var advertised := encounter.resolve_chamber_height_rows(
			config.chamber_height_rows
		)
		var deficit := advertised - _get_worst_clear_height(sculpt, half_span)
		if deficit <= 0:
			print("%-28s ok" % encounter.encounter_id)
			continue

		_open_arrival_throat(sculpt, half_span, advertised)
		var remaining := advertised - _get_worst_clear_height(sculpt, half_span)
		if remaining > 0:
			push_error(
				"ARRIVAL_THROAT_FAIL: %s still opens %d rows short."
				% [encounter.encounter_id, remaining]
			)
			failure_count += 1
			continue
		var save_error := ResourceSaver.save(sculpt, sculpt.resource_path)
		if save_error != OK:
			push_error(
				"ARRIVAL_THROAT_FAIL: could not save %s: %s"
				% [sculpt.resource_path, error_string(save_error)]
			)
			failure_count += 1
			continue
		changed_count += 1
		print(
			"%-28s OPENED advertised=%d deficit was %d"
			% [encounter.encounter_id, advertised, deficit]
		)

	print("ARRIVAL_THROATS: %d opened, %d failed" % [
		changed_count, failure_count
	])
	quit(1 if failure_count > 0 else 0)


## Returns the fewest rows of open air any arrival column has above the floor.
func _get_worst_clear_height(
	sculpt: CutsceneTerrainSculpt,
	half_span_cells: int
) -> int:
	var floor_row := sculpt.get_floor_local_row()
	var first_x := sculpt.get_landing_first_local_x(half_span_cells)
	var column_count := sculpt.get_landing_local_rows(half_span_cells).size()
	var worst_clear := floor_row
	for index in range(column_count):
		var local_x := first_x + index
		var ceiling_row := floor_row
		for local_y in range(floor_row):
			if not sculpt.is_solid_local(Vector2i(local_x, local_y)):
				ceiling_row = local_y
				break
		worst_clear = mini(worst_clear, floor_row - ceiling_row)
	return worst_clear


## Opens every arrival column from above the released row down into the cavern.
##
## Only rock above the room's existing ceiling is removed, so an authored
## cavern silhouette below the throat is left exactly as its own tool cut it.
func _open_arrival_throat(
	sculpt: CutsceneTerrainSculpt,
	half_span_cells: int,
	advertised_height_rows: int
) -> void:
	var centre_x := -sculpt.anchor_offset_cells.x
	var floor_row := sculpt.get_floor_local_row()
	var highest_row := maxi(
		floor_row - advertised_height_rows - RELEASE_MARGIN_ROWS,
		0
	)
	sculpt.begin_edit()
	for local_y in range(highest_row, floor_row):
		var left_chip := maxi(
			roundi(sin(float(local_y) * 0.37) * THROAT_CHIP_CELLS),
			0
		)
		var right_chip := maxi(
			roundi(cos(float(local_y) * 0.29 + 0.8) * THROAT_CHIP_CELLS),
			0
		)
		for local_x in range(
			maxi(centre_x - half_span_cells - left_chip, 0),
			mini(
				centre_x + half_span_cells + right_chip + 1,
				sculpt.grid_size.x
			)
		):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)
	sculpt.end_edit()
	CutsceneSculptBaker.apply_visual_depth_masks(sculpt)
