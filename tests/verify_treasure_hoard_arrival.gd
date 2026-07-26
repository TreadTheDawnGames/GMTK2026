extends SceneTree

## How it works:
## - Loads Encounter 6's shipped encounter resource and its authored room.
## - Verifies the arrival ceiling matches the rows the room is actually carved.
## - Verifies that ceiling row is open air across every landing column.
## - Verifies the room still stops a fall within the schedule's tolerance.
## - Verifies the shot keeps normal layered terrain instead of the cafe shader.
## - Uses authored data only, so the check is deterministic and headless.
## - The invariant is that the miner can always reach the floor he is shown on.

const _ENCOUNTER_PATH := (
	"res://resources/encounters/treasure_hunter_treasure_encounter.tres"
)
const _ROOM_PATH := (
	"res://resources/cinematics/sculpts/treasure_hunter_treasure_room.tres"
)
const _STAGE_PATH := (
	"res://Scenes/cinematics/treasure_hunter_hoard_encounter_stage.tscn"
)
const _SEQUENCE_PATH := (
	"res://resources/cinematics/sequences/treasure_hunter_treasure_sequence.tres"
)
## The ActionMarkers child the landing dust is thrown from.
const _CONTACT_MARKER := &"LandingContact"
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
		_expect(
			not encounter.dresses_trodden_floor
			and not encounter.lights_floor_as_plane,
			"Encounter 6 must not consume Encounter 9's floor shaders."
		)
	_verify_contact_dust()
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


## The dust the landing throws up has to land on the miner, not on the room.
##
## The plume is asked for by a STRIKE beat, and a STRIKE resolves its point from
## ActionMarkers - the one marker root that historically never moved. The miner
## can stop on any of 49 columns and the camera centres on whichever one he
## stopped at, so a mark left pinned to the room is up to 192px from his feet:
## the dust goes off in open floor or inside the hoard. Three things have to hold
## together for it to land, they live in three different files, and none of them
## errors on its own.
func _verify_contact_dust() -> void:
	var stage_scene := load(_STAGE_PATH) as PackedScene
	_expect(stage_scene != null, "Encounter 6 stage scene must load.")
	if stage_scene == null:
		return
	var stage := stage_scene.instantiate() as CharacterEncounterStage
	_expect(stage != null, "Encounter 6 stage must be a CharacterEncounterStage.")
	if stage == null:
		return

	_expect(
		stage.conversation_tracks_miner
		and stage.strike_markers_track_tracked_cast,
		"Encounter 6 must carry its strike marks to the landing column."
	)
	var contact := stage.action_markers_root.get_node_or_null(
		NodePath(_CONTACT_MARKER)
	)
	_expect(
		contact != null,
		"Encounter 6 needs ActionMarkers/%s for its landing dust." % _CONTACT_MARKER
	)
	# A strike aimed at a marker that does not exist push_errors at runtime and
	# is otherwise silent, so the beat and the mark are checked against each
	# other rather than each being checked alone.
	var has_contact_beat := false
	var sequence := load(_SEQUENCE_PATH) as CutsceneSequence
	_expect(sequence != null, "Encounter 6 sequence must load.")
	if sequence != null:
		for beat: CutsceneBeat in sequence.beats:
			if (
				beat.kind == CutsceneBeat.Kind.STRIKE
				and beat.cue == _CONTACT_MARKER
			):
				has_contact_beat = true
	_expect(
		has_contact_beat,
		"Encounter 6 needs a STRIKE beat on %s for the landing dust."
			% _CONTACT_MARKER
	)
	# Presentation only. Above zero a strike also opens real terrain, which would
	# turn a landing effect into a hole in the room the cast are standing in.
	_expect(
		stage.strike_breaks_rock_radius_cells == 0,
		"Encounter 6's landing dust must not break real rock."
	)

	# And the shift itself. This is the part with no symptom when it is wrong:
	# the plume still plays, just somewhere else.
	var shift_x := 137.0
	stage.actor_markers_root.position.x = shift_x
	stage._follow_tracked_cast_with_authored_roots()
	_expect(
		is_equal_approx(stage.action_markers_root.position.x, shift_x),
		(
			"Strike marks did not follow the tracked cast: expected %.1f, got %.1f."
			% [shift_x, stage.action_markers_root.position.x]
		)
	)
	_expect(
		is_equal_approx(stage.prop_markers_root.position.x, shift_x),
		"The hoard must keep following the tracked cast as well."
	)

	# Default-preserving: with the opt-in off, ActionMarkers stays where the room
	# put it, which is what every other stage relies on.
	stage.strike_markers_track_tracked_cast = false
	stage.action_markers_root.position.x = 0.0
	stage._follow_tracked_cast_with_authored_roots()
	_expect(
		is_zero_approx(stage.action_markers_root.position.x),
		"Strike marks must not move for a stage that did not opt in."
	)
	stage.free()


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
