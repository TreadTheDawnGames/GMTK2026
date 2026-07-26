extends SceneTree

## How it works:
## - Loads Encounter 6's shipped encounter resource and its authored room.
## - Verifies the arrival ceiling matches the rows the room is actually carved.
## - Verifies that ceiling row is open air across every landing column.
## - Verifies the room still stops a fall within the schedule's tolerance.
## - Verifies the shot keeps the shared trodden-floor dressing it is composed for.
## - Uses authored data only, so the check is deterministic and headless.
## - The invariant is that the miner can always reach the floor he is shown on.

const _ENCOUNTER_PATH := (
	"res://resources/encounters/treasure_hunter_treasure_encounter.tres"
)
const _ROOM_PATH := (
	"res://resources/cinematics/sculpts/treasure_hunter_treasure_room.tres"
)
## The schedule default, passed in so this never depends on the shared config.
const _SCHEDULE_DEFAULT_ROWS := 24
## DepthEncounterController.LANDING_FLOOR_TOLERANCE_ROWS, restated so a headless
## check never has to build the controller to read one constant.
const _LANDING_TOLERANCE_ROWS := 4
## Half the 49-column band the run's snaking descent can arrive down.
const _LANDING_HALF_SPAN_CELLS := 24

var _failures: PackedStringArray = []


func _initialize() -> void:
	var encounter := load(_ENCOUNTER_PATH) as DepthCharacterEncounter
	var room := load(_ROOM_PATH) as CutsceneTerrainSculpt
	_expect(encounter != null, "Encounter 6 resource must load.")
	_expect(room != null, "Encounter 6 room sculpt must load.")
	if encounter != null and room != null:
		_verify_arrival(encounter, room)
	if room != null:
		_verify_landing(room)
	if encounter != null:
		# The 2.5D read this shot is composed against is the shared walked-floor
		# dressing Encounter 9 introduced, not a local shader. Losing the opt-in
		# would not error anywhere; the room would just quietly go flat again.
		_expect(
			encounter.dresses_trodden_floor,
			"Encounter 6 must keep the shared trodden-floor dressing."
		)
	if _failures.is_empty():
		print("TREASURE_HOARD_ARRIVAL_PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


## The override is the encounter ceiling - the row that starts the shot - while
## the sculpt decides where rock really is. They are set in two different files
## and nothing ties them together, so this measures the cut and requires the
## ceiling to agree with it.
##
## The failure this protects against is not cosmetic. Crossing the ceiling row
## claims the shared mining gate, which pauses the swing queue and disables the
## timing window; if the room is not open at that row the miner cannot dig the
## rest of the way down and the encounter sits pending forever. In game that is
## mining that simply stops working, with nothing in any log. Encounter 6
## shipped exactly that way: carved 30 rows open with the ceiling set to 81.
func _verify_arrival(
	encounter: DepthCharacterEncounter,
	room: CutsceneTerrainSculpt
) -> void:
	var carved_rows := _measure_carved_rows_above_floor(room)
	_expect(
		carved_rows > 0,
		"Encounter 6's room must be carved open somewhere above its floor."
	)
	if carved_rows <= 0:
		return
	var resolved := encounter.resolve_chamber_height_rows(
		_SCHEDULE_DEFAULT_ROWS
	)
	_expect(
		resolved == carved_rows,
		(
			"Arrival ceiling is %d rows but the room is carved %d rows open."
			% [resolved, carved_rows]
		)
	)
	if resolved != carved_rows:
		return

	# Matching the topmost opening is not enough on its own. He crosses the
	# trigger row at whatever column his snaking path is on, so the lip has to be
	# open air across the whole band rather than only at its highest point.
	var floor_row := room.get_floor_local_row()
	var ceiling_row := floor_row - resolved
	var centre_column := -room.anchor_offset_cells.x
	for column in range(
		centre_column - _LANDING_HALF_SPAN_CELLS,
		centre_column + _LANDING_HALF_SPAN_CELLS + 1
	):
		if room.is_solid_local(Vector2i(column, ceiling_row)):
			_expect(
				false,
				(
					"Landing column %d is solid at the arrival row %d; a "
					% [column, ceiling_row]
					+ "descent arriving there would be walled in with the "
					+ "mining gate already claimed."
				)
			)
			return


## Every column the descent can arrive down has to stop him on the floor or on
## the loose rock lying on it. A ledge that catches him higher leaves the
## encounter pending with the gate claimed, the same dead run by another route.
func _verify_landing(room: CutsceneTerrainSculpt) -> void:
	var floor_row := room.get_floor_local_row()
	var landing_rows := room.get_landing_local_rows(_LANDING_HALF_SPAN_CELLS)
	var first_column := room.get_landing_first_local_x(
		_LANDING_HALF_SPAN_CELLS
	)
	_expect(
		not landing_rows.is_empty(),
		"Encounter 6's room must report landing columns."
	)
	for index in range(landing_rows.size()):
		var landing_row := landing_rows[index]
		var column := first_column + index
		if landing_row < 0:
			_expect(false, "Column %d has no opening to fall into." % column)
			return
		if floor_row - landing_row > _LANDING_TOLERANCE_ROWS:
			_expect(
				false,
				(
					"Column %d stops %d rows above the floor; the schedule "
					% [column, floor_row - landing_row]
					+ "tolerates %d." % _LANDING_TOLERANCE_ROWS
				)
			)
			return


## Returns how many rows above the floor line the room is actually cut open.
func _measure_carved_rows_above_floor(room: CutsceneTerrainSculpt) -> int:
	var grid: Vector2i = room.grid_size
	var anchor: Vector2i = room.anchor_offset_cells
	for row in range(grid.y):
		for column in range(grid.x):
			if not room.is_solid_local(Vector2i(column, row)):
				# Grid row 0 sits anchor.y rows above the floor.
				return -(anchor.y + row)
	return 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
