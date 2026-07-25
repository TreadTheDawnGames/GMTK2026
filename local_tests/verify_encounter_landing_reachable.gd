extends SceneTree

## Proves every authored cutscene room can actually satisfy the promotion gate
## that starts its encounter.
##
## DepthEncounterController holds a crossed encounter pending until the visible
## fall reaches the room's floor. A sculpted room's ground is not its floor row
## though - the level tunnel lays loose rock along the floor and the miner comes
## to rest on top of that - so the landing legitimately stops a few rows short.
## When the gate demanded the bare floor row, the fall could never satisfy it:
## the encounter stayed pending forever with the cinematic flow already claimed,
## and the game read as mining that stopped working with no error anywhere.
##
## This walks the shipped schedule and asserts, for every room, that the rows the
## miner can actually land on are within the tolerance the controller allows, and
## that no reachable column drops him past the room entirely.
##
## The invariant is that a room the schedule can open is a room the fall can
## finish arriving in.

const ENCOUNTER_CONFIG_PATH := (
	"res://resources/encounters/depth_encounter_config.tres"
)
const MINING_CONFIG_PATH := "res://resources/mining/mining_config.tres"

var _failures: Array[String] = []
var _worst_shortfall: int = 0
var _worst_room: StringName = &"none"


func _initialize() -> void:
	var encounter_config := load(ENCOUNTER_CONFIG_PATH) as DepthEncounterConfig
	var mining_config := load(MINING_CONFIG_PATH) as MiningConfig
	if encounter_config == null or mining_config == null:
		push_error("Landing check could not load the shipped configuration.")
		quit(1)
		return

	var tolerance := DepthEncounterController.LANDING_FLOOR_TOLERANCE_ROWS
	var checked := 0
	for encounter in encounter_config.encounters:
		if encounter == null or encounter.terrain_sculpt == null:
			continue
		if not encounter.terrain_sculpt.enabled:
			continue
		checked += 1
		_verify_room(
			encounter,
			encounter.terrain_sculpt,
			mining_config,
			tolerance
		)

	if checked == 0:
		_failures.append(
			"No encounter carries a sculpt, so this check proved nothing. "
			+ "An encounter that embeds its room as an inline sub-resource "
			+ "instead of referencing its sculpts/ file will look like this."
		)

	# The tightest room is printed because passing says nothing about how nearly
	# it failed: a room sitting one row inside the tolerance is a room the next
	# floor-detail change breaks.
	print("ENCOUNTER_LANDING rooms=%d tolerance=%d worst=%d rows (%s)" % [
		checked,
		tolerance,
		_worst_shortfall,
		_worst_room,
	])
	if _failures.is_empty():
		print("ENCOUNTER_LANDING_VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ENCOUNTER_LANDING_VERIFY: FAIL (%d)" % _failures.size())
	quit(1)


func _verify_room(
	encounter: DepthCharacterEncounter,
	sculpt: CutsceneTerrainSculpt,
	mining_config: MiningConfig,
	tolerance: int
) -> void:
	var sculpt_error := sculpt.get_sculpt_error()
	if not sculpt_error.is_empty():
		_failures.append(
			"Room '%s' is unusable: %s" % [encounter.encounter_id, sculpt_error]
		)
		return

	var floor_local_row := sculpt.get_floor_local_row()
	var landing_rows := sculpt.get_landing_local_rows(
		mining_config.snake_half_span_cells
	)
	if landing_rows.is_empty():
		_failures.append(
			"Room '%s' reports no reachable columns at all."
			% encounter.encounter_id
		)
		return

	var first_local_x := sculpt.get_landing_first_local_x(
		mining_config.snake_half_span_cells
	)
	var highest_landing := floor_local_row
	var bottomless_columns := 0
	for index in range(landing_rows.size()):
		var landing_row := landing_rows[index]
		if landing_row < 0:
			bottomless_columns += 1
			continue
		highest_landing = mini(highest_landing, landing_row)

	if bottomless_columns > 0:
		_failures.append(
			"Room '%s' has %d columns the miner can fall down with nothing to "
			% [encounter.encounter_id, bottomless_columns]
			+ "land on."
		)

	var shortfall := floor_local_row - highest_landing
	if shortfall > _worst_shortfall:
		_worst_shortfall = shortfall
		_worst_room = encounter.encounter_id
	if shortfall > tolerance:
		_failures.append(
			(
				"Room '%s' stops the fall %d rows above its floor, past the "
				+ "controller's %d-row tolerance, so the encounter would stay "
				+ "pending forever. Highest landing row %d against floor %d, "
				+ "columns from %d."
			)
			% [
				encounter.encounter_id,
				shortfall,
				tolerance,
				highest_landing,
				floor_local_row,
				first_local_x,
			]
		)
