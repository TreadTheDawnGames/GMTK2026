extends SceneTree

## How it works:
## - Walks every encounter the run schedules, in the order the run reaches them.
## - Drops a simulated arrival down each column of the snaking band.
## - Starts each drop at the row the controller actually releases the fall from.
## - Reports the row the miner first touches and the shortfall to the room floor.
## - Fails on any column that stops outside the controller's landing tolerance.
## The invariant is that every legal arrival promotes its encounter.
##
## This checks the outcome rather than the cause. The throat sweep asks whether
## a room opens as many rows as its config advertises; this asks the question
## that actually matters, which is where the miner ends up - so an authored
## ledge, a prop shelf, or hanging rock below the release row is caught here
## even though the room's ceiling measured fine.

const CONFIG_PATH: String = (
	"res://resources/encounters/depth_encounter_config.tres"
)
const MINING_CONFIG_PATH: String = "res://resources/mining/mining_config.tres"

var _failures: Array[String] = []


func _initialize() -> void:
	var config := load(CONFIG_PATH) as DepthEncounterConfig
	var mining_config := load(MINING_CONFIG_PATH) as MiningConfig
	if config == null or mining_config == null:
		push_error("Arrival verification could not load its configs.")
		quit(1)
		return

	var half_span := mining_config.snake_half_span_cells
	var tolerance := DepthEncounterController.LANDING_FLOOR_TOLERANCE_ROWS
	for encounter: DepthCharacterEncounter in config.encounters:
		if encounter == null:
			continue
		var sculpt := encounter.terrain_sculpt
		if sculpt == null or not sculpt.enabled:
			print("%-28s procedural chamber, no authored room" % (
				encounter.encounter_id
			))
			continue
		_verify_encounter(encounter, config, half_span, tolerance)
		if encounter.ends_rat_colony_support:
			encounter.persistent_colony_requested_leave.emit()

	if _failures.is_empty():
		print("ENCOUNTER_ARRIVALS_VERIFY_PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("ENCOUNTER_ARRIVALS_VERIFY_FAIL: %s" % failure)
	quit(1)


func _verify_encounter(
	encounter: DepthCharacterEncounter,
	config: DepthEncounterConfig,
	half_span_cells: int,
	tolerance_rows: int
) -> void:
	var sculpt := encounter.terrain_sculpt
	var floor_row := sculpt.get_floor_local_row()
	var advertised := encounter.resolve_chamber_height_rows(
		config.chamber_height_rows
	)
	# The row DepthEncounterController releases the fall from, expressed in the
	# room's own grid rather than in run depth.
	var release_row := maxi(floor_row - advertised, 0)
	var first_x := sculpt.get_landing_first_local_x(half_span_cells)
	var column_count := sculpt.get_landing_local_rows(half_span_cells).size()

	var blocked_columns := 0
	var worst_shortfall := 0
	var worst_column := -1
	for index in range(column_count):
		var local_x := first_x + index
		if sculpt.is_solid_local(Vector2i(local_x, release_row)):
			blocked_columns += 1
			_failures.append(
				"%s column %d is rock at the released row %d."
				% [encounter.encounter_id, local_x, release_row]
			)
			continue
		var touch_row := floor_row
		for local_y in range(release_row, floor_row + 1):
			if sculpt.is_solid_local(Vector2i(local_x, local_y)):
				touch_row = local_y
				break
		var shortfall := floor_row - touch_row
		if shortfall > worst_shortfall:
			worst_shortfall = shortfall
			worst_column = local_x
		if shortfall > tolerance_rows:
			_failures.append(
				"%s column %d stops %d rows above the floor (limit %d)."
				% [encounter.encounter_id, local_x, shortfall, tolerance_rows]
			)

	print(
		"%-28s %-4s release_row=%-4d columns=%d blocked=%d worst=%d/%d%s"
		% [
			encounter.encounter_id,
			"FAIL" if blocked_columns > 0 or worst_shortfall > tolerance_rows
				else "ok",
			release_row,
			column_count,
			blocked_columns,
			worst_shortfall,
			tolerance_rows,
			"" if worst_column < 0 else " at column %d" % worst_column,
		]
	)
