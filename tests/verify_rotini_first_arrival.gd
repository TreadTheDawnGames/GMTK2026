extends SceneTree

## How it works:
## - Loads Encounter 3's shipped encounter, room sculpt, and stage scene.
## - Verifies the arrival ceiling matches the rows the room is actually carved.
## - Verifies the room keeps the hard cut edge the cave language is built on.
## - Verifies the procession stays inside its declared population contract.
## - Uses authored data only, so the check is deterministic and headless.
## - The invariant is that the shot starts where the rock opens, not inside it.

const _ENCOUNTER_PATH := (
	"res://resources/encounters/rutini_first_encounter.tres"
)
const _ROOM_PATH := "res://resources/cinematics/sculpts/rutini_first_room.tres"
const _STAGE_PATH := (
	"res://Scenes/cinematics/rotini_first_encounter_stage.tscn"
)
## The schedule default, passed in so this never depends on the shared config.
const _SCHEDULE_DEFAULT_ROWS := 24
## The top of the declared @export_range on max_live_followers.
const _DECLARED_FOLLOWER_CAP := 12

var _failures: PackedStringArray = []


func _initialize() -> void:
	var encounter := load(_ENCOUNTER_PATH) as DepthCharacterEncounter
	var room := load(_ROOM_PATH) as CutsceneTerrainSculpt
	_expect(encounter != null, "Encounter 3 resource must load.")
	_expect(room != null, "Encounter 3 room sculpt must load.")
	if encounter != null and room != null:
		_verify_arrival(encounter, room)
	if room != null:
		_expect(
			is_equal_approx(room.edge_smoothing, 0.0),
			"Encounter 3's room must keep hard cut edges (edge_smoothing 0)."
		)
	var stage_scene := load(_STAGE_PATH) as PackedScene
	_expect(stage_scene != null, "Encounter 3 stage scene must load.")
	if stage_scene != null:
		_verify_procession(stage_scene)
	if _failures.is_empty():
		print("ROTINI_FIRST_ARRIVAL_PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


## The override is the encounter ceiling - the row that starts the shot - while
## the sculpt decides where rock really is. They are set independently, so this
## measures the cut and requires the ceiling to agree with it. Too low and the
## miner falls through open air before the cutscene starts; too high and the
## ceiling is buried in solid rock.
func _verify_arrival(
	encounter: DepthCharacterEncounter,
	room: CutsceneTerrainSculpt
) -> void:
	var carved_rows := _measure_carved_rows_above_floor(room)
	_expect(
		carved_rows > 0,
		"Encounter 3's room must be carved open somewhere above its floor."
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


## The live count is the whole cost of the stampede: one follower spawns per
## interval and only under the cap, so the cap is the budget. Rows and spawn
## interval change how it reads without changing how much of it there is.
func _verify_procession(stage_scene: PackedScene) -> void:
	var stage := stage_scene.instantiate()
	_expect(
		stage.procession_cue == &"stampede",
		"The horde must wait for the stampede cue, not the opening."
	)
	_expect(
		stage.max_live_followers <= _DECLARED_FOLLOWER_CAP,
		(
			"Live follower cap %d exceeds the declared range of %d."
			% [stage.max_live_followers, _DECLARED_FOLLOWER_CAP]
		)
	)
	_expect(
		stage.web_max_live_followers <= stage.max_live_followers,
		"The web follower cap must not exceed the native cap."
	)
	# At this cap the drawn crowd is what reads as a wall; individual mice at the
	# same population read as a line.
	var has_clump := false
	for appearance in stage.rat_appearances:
		if appearance != null and appearance.resource_path.contains("clump"):
			has_clump = true
	_expect(has_clump, "The procession must keep its clump appearances.")
	stage.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
