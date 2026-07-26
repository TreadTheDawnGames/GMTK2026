extends SceneTree

## Cuts Encounter 6's room, The Treasure at depth 7,400, as one large irregular
## closed cavern with a shaft above the landing band.
##
## Composed entirely from CutsceneSculptBaker and CutsceneSculptBrush, so the
## room is cut with the same tools the Cutscene panel uses and a designer
## reopening it finds work they can continue. Every decision is seeded from the
## cell coordinate, so re-running this reproduces the room exactly.
##
## Why it was recut. The shipped room was carved 30 rows open while the
## encounter's Chamber Height Override said 81, and the override is the trigger
## row: the shot claimed the shared mining gate 51 rows deep inside solid rock,
## which pauses the swing queue and hides the timing window, so the miner could
## never dig the rest of the way down. The encounter sat pending forever with a
## prestaged Treasure Hunter revealed far above the room. That is one bug with
## two symptoms - a cutscene starting way up in the rock, and mining that simply
## stops - and it is why the ceiling and the cut are now measured against each
## other by tests/verify_treasure_hoard_arrival.gd.
##
## The arrival lip is therefore FLAT. The miner crosses the trigger row at
## whatever column his snaking descent is on, so every column of the landing
## band has to be open air at that exact row or he is walled in at the one the
## roof happens to be lowest over. Encounter 1 solves it the same way: its band
## roof is level at 72 across all 49 columns. The irregular cavern roof lives
## below the shaft, in the ~32 rows the 648px frame can actually see.
##
## Geometry, in the room's own grid columns. The anchor is terrain centre,
## column 192, and the floor is local row 110:
##
##   landing band     168..216   where the snaking descent can put the miner
##   arrival shaft    158..226   the drop, flat-lipped across the whole band
##   hoard            +12..+50   cells right of the miner, wherever he landed
##   Treasure Hunter  +19        cells right of the miner, wherever he landed
##   stage zone       150..300   the union of all of the above across the band

const ROOM_PATH := (
	"res://resources/cinematics/sculpts/treasure_hunter_treasure_room.tres"
)

## The band the snaking descent can arrive down, either side of centre.
const LANDING_HALF_SPAN_CELLS: int = 24

## Where the shot happens, in grid columns: every column the miner, the hoard or
## the Treasure Hunter can occupy at any landing. Rock is cleared to the floor
## across this whole span and nothing is allowed to hang into it.
const STAGE_ZONE_FIRST_COLUMN: int = 150
const STAGE_ZONE_LAST_COLUMN: int = 300

## How far above the floor the arrival opens, and therefore what this room
## requires the encounter's Chamber Height Override to be. The run reports the
## measured number at the end so the two can never drift apart silently.
##
## 56 rows is 448px of fall. The frame is 648px tall with the dig line about
## 260px up it, so roughly the lowest 32 rows are all a player ever sees: a lip
## at 56 sits two thirds of a screen above the visible ceiling, which is what
## makes him arrive THROUGH the roof rather than beginning the shot already
## standing in the room. It is deliberately far short of the 81 the broken room
## claimed, which put the reveal a screen and a half above the floor.
const CEILING_ROWS: int = 56

## The shaft. It stays wider than the landing band at every height so the lip
## can never pinch in on a column the descent is allowed to use, and it flares
## as it drops so the mouth is not a rectangle cut in the ceiling.
const SHAFT_LIP_FIRST_COLUMN: int = 164
const SHAFT_LIP_LAST_COLUMN: int = 220
const SHAFT_FOOT_FIRST_COLUMN: int = 158
const SHAFT_FOOT_LAST_COLUMN: int = 226

## End walls. Both close, because this is the end of the Treasure Hunter's dig
## and not a passage through - see cutscene_direction_notes.md section 6. They
## stand far enough out that the room reads as big: 96 to 360 is 264 cells of
## rock-to-rock span, over two screens wide, against the 214 the old room had.
const LEFT_WALL_FOOT_COLUMN: int = 112
const LEFT_WALL_FACE_COLUMN: int = 96
const RIGHT_WALL_FOOT_COLUMN: int = 344
const RIGHT_WALL_FACE_COLUMN: int = 360

## Clear height the seeded tunnel starts at, before the cavern is swept out of
## its roof.
##
## Deliberately lower than the baker's own sixteen. Carving only ever opens
## rock, so the finished roof is the higher of this tunnel and the cavern above
## it: start at sixteen and the roof can never come back down, and a roof that
## cannot come down is the flat lid this room is being cut to stop being.
const BASE_TUNNEL_HEIGHT_CELLS: int = 9

## Disc centres for the cavern sweep, in cells above the floor. A disc reaches
## about six cells past the line it is centred on once the falloff is done with
## it, so the finished roof runs roughly six cells higher than these.
##
## The shape is the reference's, not a compass arc. IMG_1643_01 at 10.09s and
## 50.38s is one deeply lobed contour with re-entrants and bulges of very
## unequal size, and section 6 reads it as a roof "pressing down at the ends and
## lifting over the span the cast and treasure occupy" - so the hall stays high
## from the landing all the way across the hoard and only closes at the walls.
const ROOF_LEFT_END_CELLS: float = 5.0
const ROOF_LEFT_SHOULDER_CELLS: float = 17.0
const ROOF_HALL_CELLS: float = 27.0
const ROOF_HOARD_CELLS: float = 24.0
const ROOF_RIGHT_SHOULDER_CELLS: float = 15.0
const ROOF_RIGHT_END_CELLS: float = 5.0
## How much the noise moves the roof off that curve, so the swell does not read
## as one smooth arch drawn with a compass.
const ROOF_NOISE_CELLS: float = 3.2

const LEFT_END_COLUMN: float = 100.0
const LEFT_SHOULDER_COLUMN: float = 132.0
const HALL_LEFT_COLUMN: float = 158.0
const HALL_RIGHT_COLUMN: float = 236.0
const HOARD_COLUMN: float = 268.0
const HOARD_END_COLUMN: float = 300.0
const RIGHT_SHOULDER_COLUMN: float = 326.0
const RIGHT_END_COLUMN: float = 356.0

## Radius of the discs that sweep the cavern out, and how far apart they fall.
## Spacing well under the radius is what merges them into one continuous vault
## instead of a row of domes.
const CAVERN_DISC_RADIUS_CELLS: float = 6.0
const CAVERN_DISC_SPACING_CELLS: float = 3.0

## The rim-breaking pass over the finished vault.
const CAVERN_ROUGHEN_RADIUS_CELLS: float = 6.0
const CAVERN_ROUGHEN_SPACING_CELLS: float = 3.0
const CAVERN_ROUGHEN_STRENGTH: float = 0.55

## Tallest rock the floor pass lays down. Columns are cleared to this line
## rather than to the floor itself, so the ground keeps its stones.
const FLOOR_ROCK_CELLS: int = 3

## What the schedule tolerates between the room's floor and where a fall stops.
const LANDING_TOLERANCE_ROWS: int = 4

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var sculpt: CutsceneTerrainSculpt = load(ROOM_PATH)
	if sculpt == null:
		_fail("Could not load %s" % ROOM_PATH)
		_finish()
		return

	# Order matters. The tunnel fills solid and cuts the room's whole shape, so
	# it runs first; the cavern is swept out of what it left; the end walls close
	# what the cavern opened; the clearing pass runs next because both the cavern
	# and the walls can leave rock hanging; and the shaft is cut last so nothing
	# afterwards can put a lump back into the one drop the miner has to make.
	CutsceneSculptBaker.carve_level_tunnel(sculpt, BASE_TUNNEL_HEIGHT_CELLS)
	_sweep_cavern(sculpt)
	CutsceneSculptBaker.carve_jagged_end_wall(
		sculpt,
		LEFT_WALL_FOOT_COLUMN,
		LEFT_WALL_FACE_COLUMN
	)
	CutsceneSculptBaker.carve_jagged_end_wall(
		sculpt,
		RIGHT_WALL_FOOT_COLUMN,
		RIGHT_WALL_FACE_COLUMN
	)
	_drop_hanging_rock(sculpt)
	_cut_arrival_shaft(sculpt)
	CutsceneSculptBaker.apply_visual_depth_masks(sculpt)

	_verify_arrival_lip(sculpt)
	_verify_landing(sculpt)
	_verify_stage_zone_is_clear(sculpt)
	_verify_walls_stand(sculpt)
	_report_roof_profile(sculpt)

	if not _failures.is_empty():
		_finish()
		return

	# The header has to be taken before the save, because the save is what
	# destroys it. ResourceSaver writes this room back without its `uid=` and
	# without the script's, and the encounter resource refers to the room BY
	# uid: re-running this carve therefore silently breaks the reference every
	# time, and the only symptom is an encounter that stops finding its room.
	# Restoring the two lines here is what makes the script safe to re-run.
	var original_header := _read_resource_header()
	var save_result := ResourceSaver.save(sculpt, ROOM_PATH)
	if save_result != OK:
		_fail("Saving the room returned %d." % save_result)
		_finish()
		return
	_restore_resource_header(original_header)
	_finish()


## Returns the two identity lines a save is about to drop, keyed by their line
## prefix so a restore can put each back exactly where it was.
func _read_resource_header() -> Dictionary:
	var file := FileAccess.open(ROOM_PATH, FileAccess.READ)
	if file == null:
		return {}
	var header := {}
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("[gd_resource "):
			header["[gd_resource "] = line
		elif line.begins_with("[ext_resource "):
			header["[ext_resource "] = line
		elif line.begins_with("[resource]"):
			break
	file.close()
	return header


## Puts the saved file's identity lines back, and fails the run rather than
## leaving a room whose uid no longer matches the encounter pointing at it.
func _restore_resource_header(original_header: Dictionary) -> void:
	if original_header.is_empty():
		_fail("Could not read the room's original resource header.")
		return
	var file := FileAccess.open(ROOM_PATH, FileAccess.READ)
	if file == null:
		_fail("Could not reopen the saved room to restore its identity.")
		return
	var body := file.get_as_text()
	file.close()
	var lines := body.split("\n")
	var restored: PackedStringArray = []
	for line in lines:
		var replacement := line
		for prefix in original_header:
			if line.begins_with(prefix):
				replacement = original_header[prefix]
		restored.append(replacement)
	var out := FileAccess.open(ROOM_PATH, FileAccess.WRITE)
	if out == null:
		_fail("Could not rewrite the saved room's identity.")
		return
	out.store_string("\n".join(restored))
	out.close()
	if not FileAccess.get_file_as_string(ROOM_PATH).contains("uid://"):
		_fail("The saved room still has no uid; the encounter would lose it.")
		return
	print("identity: resource and script uids preserved across the save")


## Sweeps the cavern out of the seeded tunnel's roof.
##
## The roof height is four waves of unrelated lengths summed, the same trick the
## floor bumps use and for the same reason: two frequencies in a whole-number
## ratio repeat on a short cycle and the room reads as tiled. The discs are
## carved along that line, so the vault is built from overlapping arcs rather
## than from a height per column - a column-wise roof can only ever be flat or
## vertical, which is the staircase the end walls already had to solve.
func _sweep_cavern(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := float(sculpt.get_floor_local_row())
	var brush := CutsceneSculptBrush.new()
	brush.radius_cells = CAVERN_DISC_RADIUS_CELLS
	brush.falloff = 0.35
	var disc_x := -CAVERN_DISC_RADIUS_CELLS
	while disc_x <= float(sculpt.grid_size.x) + CAVERN_DISC_RADIUS_CELLS:
		brush.carve(
			sculpt,
			Vector2(disc_x, floor_row - _get_roof_height_cells(disc_x))
		)
		disc_x += CAVERN_DISC_SPACING_CELLS

	# Break the arcs. Roughen flips only cells already on a solid/open edge, so
	# this jags the vault's silhouette without punching through the rock above it.
	brush.radius_cells = CAVERN_ROUGHEN_RADIUS_CELLS
	brush.strength = CAVERN_ROUGHEN_STRENGTH
	brush.falloff = 0.55
	var roughen_x := 0.0
	while roughen_x <= float(sculpt.grid_size.x):
		brush.seed_value = int(roughen_x) + 811
		brush.roughen(
			sculpt,
			Vector2(roughen_x, floor_row - _get_roof_height_cells(roughen_x))
		)
		roughen_x += CAVERN_ROUGHEN_SPACING_CELLS


## Returns the height the cavern's discs are centred at over one column.
func _get_roof_height_cells(local_x: float) -> float:
	var roof_height := ROOF_LEFT_END_CELLS
	if local_x < LEFT_SHOULDER_COLUMN:
		roof_height = lerpf(
			ROOF_LEFT_END_CELLS,
			ROOF_LEFT_SHOULDER_CELLS,
			smoothstep(LEFT_END_COLUMN, LEFT_SHOULDER_COLUMN, local_x)
		)
	elif local_x < HALL_LEFT_COLUMN:
		roof_height = lerpf(
			ROOF_LEFT_SHOULDER_CELLS,
			ROOF_HALL_CELLS,
			smoothstep(LEFT_SHOULDER_COLUMN, HALL_LEFT_COLUMN, local_x)
		)
	elif local_x <= HALL_RIGHT_COLUMN:
		roof_height = ROOF_HALL_CELLS
	elif local_x < HOARD_END_COLUMN:
		roof_height = lerpf(
			ROOF_HALL_CELLS,
			ROOF_HOARD_CELLS,
			smoothstep(HALL_RIGHT_COLUMN, HOARD_COLUMN, local_x)
		)
	elif local_x < RIGHT_SHOULDER_COLUMN:
		roof_height = lerpf(
			ROOF_HOARD_CELLS,
			ROOF_RIGHT_SHOULDER_CELLS,
			smoothstep(HOARD_END_COLUMN, RIGHT_SHOULDER_COLUMN, local_x)
		)
	else:
		roof_height = lerpf(
			ROOF_RIGHT_SHOULDER_CELLS,
			ROOF_RIGHT_END_CELLS,
			smoothstep(RIGHT_SHOULDER_COLUMN, RIGHT_END_COLUMN, local_x)
		)
	# The short wave is the important one. The three long ones shape the room,
	# but a roof that only carries them climbs its ramps one cell at a time in
	# the same direction, and a monotonic rise on an eight-pixel grid draws
	# exactly the row of rectangular treads the house rules call a built
	# staircase. Something with a period of about eleven columns breaks every
	# ramp into rock going both ways, which is what a worn edge looks like.
	var noise := (
		sin(local_x * 0.043) * 0.44
		+ sin(local_x * 0.017 + 1.3) * 0.24
		+ sin(local_x * 0.091 + 2.7) * 0.12
		+ sin(local_x * 0.550 + 0.4) * 0.20
	)
	return roof_height + noise * ROOF_NOISE_CELLS


## Opens the drop the miner arrives down, and closes everything above its lip.
##
## Two separate guarantees, and both are load-bearing. Opening the shaft is what
## lets him fall; filling every row above the lip is what makes the measured
## ceiling equal the lip rather than some stray cell the roughen pass left
## higher up, and the encounter's Chamber Height Override is set from that
## measurement. Run in this order the room can only report one arrival row.
func _cut_arrival_shaft(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	var lip_row := floor_row - CEILING_ROWS
	var lowest_open_row := floor_row - FLOOR_ROCK_CELLS
	sculpt.begin_edit()
	for local_y in range(0, lip_row):
		for local_x in range(sculpt.grid_size.x):
			sculpt.set_solid_local(Vector2i(local_x, local_y), true)
	for local_y in range(lip_row, lowest_open_row):
		# The mouth flares as it drops rather than cutting a rectangle in the
		# ceiling. It stays wider than the landing band at every height, so the
		# lip can never pinch in on a column the descent is allowed to use.
		var drop := smoothstep(
			float(lip_row),
			float(floor_row - CEILING_ROWS / 2),
			float(local_y)
		)
		var first_column := int(
			roundf(lerpf(
				float(SHAFT_LIP_FIRST_COLUMN),
				float(SHAFT_FOOT_FIRST_COLUMN),
				drop
			))
		)
		var last_column := int(
			roundf(lerpf(
				float(SHAFT_LIP_LAST_COLUMN),
				float(SHAFT_FOOT_LAST_COLUMN),
				drop
			))
		)
		for local_x in range(first_column, last_column + 1):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)
	sculpt.end_edit()


## Opens every column from the rock it starts at down to the height that column
## is allowed to keep, so nothing is left hanging in air.
##
## This is the pass that makes the room survivable. The cavern sweep and the
## roughen after it both leave rock arching over gaps, and a falling miner stops
## on the first solid cell he meets: one lump four rows under the roof and he
## lands twenty cells above the cast, outside the schedule's tolerance, and the
## encounter sits pending forever with the cinematic gate already claimed. In
## game that looks like mining that simply stopped working, with no error.
func _drop_hanging_rock(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	var lowest_open_row := floor_row - FLOOR_ROCK_CELLS
	sculpt.begin_edit()
	for local_x in range(sculpt.grid_size.x):
		var ceiling_row := _find_ceiling_row(sculpt, local_x, floor_row)
		if ceiling_row < 0:
			continue
		for local_y in range(ceiling_row, lowest_open_row):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)
	sculpt.end_edit()


## Returns the first open row under the rock at one column, or -1 for a column
## that is solid all the way down.
func _find_ceiling_row(
	sculpt: CutsceneTerrainSculpt,
	local_x: int,
	floor_row: int
) -> int:
	for local_y in range(0, floor_row):
		if not sculpt.is_solid_local(Vector2i(local_x, local_y)):
			return local_y
	return -1


## The trigger row has to be open air across the whole landing band.
##
## The encounter claims the shared mining gate the moment the run's depth
## crosses this row, and claiming it pauses the swing queue and disables the
## timing window. He is at whatever column his snaking path is on at that
## instant, so a single band column that is still rock at this row is a run that
## can never dig itself out - which is exactly how the previous room failed.
func _verify_arrival_lip(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	var lip_row := floor_row - CEILING_ROWS
	var centre_column := -sculpt.anchor_offset_cells.x
	for local_x in range(
		centre_column - LANDING_HALF_SPAN_CELLS,
		centre_column + LANDING_HALF_SPAN_CELLS + 1
	):
		if sculpt.is_solid_local(Vector2i(local_x, lip_row)):
			_fail(
				"Column %d is solid at the arrival row %d; the miner would be "
				% [local_x, lip_row]
				+ "walled in with the mining gate already claimed."
			)
			return
	var measured := _measure_carved_rows(sculpt)
	if measured != CEILING_ROWS:
		_fail(
			"The room measures %d rows open but the shaft was cut for %d."
			% [measured, CEILING_ROWS]
		)
		return
	print(
		"arrival: level lip at row %d, %d rows over the floor, open across all "
		% [lip_row, CEILING_ROWS]
		+ "%d landing columns" % (LANDING_HALF_SPAN_CELLS * 2 + 1)
	)


## Returns how many rows above the floor the room is cut open anywhere, which is
## the number the encounter's Chamber Height Override has to carry.
func _measure_carved_rows(sculpt: CutsceneTerrainSculpt) -> int:
	var floor_row := sculpt.get_floor_local_row()
	for local_y in range(sculpt.grid_size.y):
		for local_x in range(sculpt.grid_size.x):
			if not sculpt.is_solid_local(Vector2i(local_x, local_y)):
				return floor_row - local_y
	return 0


## The room is reached by falling, so this is the check that matters. Every
## column the descent can arrive down has to stop the miner on the floor or on
## the loose rock lying on it, within the schedule's four-row tolerance.
func _verify_landing(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	var landing_rows := sculpt.get_landing_local_rows(LANDING_HALF_SPAN_CELLS)
	var first_local_x := sculpt.get_landing_first_local_x(
		LANDING_HALF_SPAN_CELLS
	)
	if landing_rows.is_empty():
		_fail("The room reports no landing columns at all.")
		return
	for index in range(landing_rows.size()):
		var landing_row := landing_rows[index]
		var column := first_local_x + index
		if landing_row < 0:
			_fail("Column %d has no opening to fall into." % column)
			return
		if landing_row > floor_row:
			_fail(
				"Column %d lands on row %d, below the floor row %d."
				% [column, landing_row, floor_row]
			)
			return
		if floor_row - landing_row > LANDING_TOLERANCE_ROWS:
			_fail(
				"Column %d lands on row %d, %d rows above the floor row %d; "
				% [column, landing_row, floor_row - landing_row, floor_row]
				+ "the schedule tolerates four and the encounter would hang."
			)
			return
	print("landing: all %d columns from %d stop within tolerance of row %d" % [
		landing_rows.size(),
		first_local_x,
		floor_row,
	])


## Nothing may hang into the space the shot happens in. The hoard's apex stands
## about twenty cells over the floor and the cast stand in front of it, so a
## lump left at fifteen would sit in the middle of the composition.
func _verify_stage_zone_is_clear(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	for local_x in range(STAGE_ZONE_FIRST_COLUMN, STAGE_ZONE_LAST_COLUMN + 1):
		var ceiling_row := _find_ceiling_row(sculpt, local_x, floor_row)
		if ceiling_row < 0:
			_fail("Column %d in the stage zone is solid to the floor." % local_x)
			return
		for local_y in range(ceiling_row, floor_row - FLOOR_ROCK_CELLS):
			if sculpt.is_solid_local(Vector2i(local_x, local_y)):
				_fail(
					"Column %d has rock hanging at row %d, %d cells over the "
					% [local_x, local_y, floor_row - local_y]
					+ "floor, inside the stage zone."
				)
				return
	print(
		"stage zone: columns %d to %d are open from their roof to the ground"
		% [STAGE_ZONE_FIRST_COLUMN, STAGE_ZONE_LAST_COLUMN]
	)


## Both walls have to actually close. A wall that leaves a gap at any height is
## a crawlspace nobody authored, and the room stops reading as a pocket.
func _verify_walls_stand(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	for local_y in range(0, floor_row):
		if not sculpt.is_solid_local(
			Vector2i(LEFT_WALL_FACE_COLUMN - 4, local_y)
		):
			_fail(
				"The left wall is open at row %d; the room runs off that edge."
				% local_y
			)
			return
	print("left wall: solid from the grid top down to the floor")

	for local_y in range(0, floor_row):
		if not sculpt.is_solid_local(
			Vector2i(RIGHT_WALL_FACE_COLUMN + 4, local_y)
		):
			_fail(
				"The right wall is open at row %d; the room runs off that edge."
				% local_y
			)
			return
	print("right wall: solid from the grid top down to the floor")


## Prints the roof height across the room, so the cavern can be checked as
## numbers as well as by eye. A profile that never moves is the corridor this
## room was cut to stop being.
func _report_roof_profile(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	var lowest := 999
	var highest := -1
	var samples: PackedStringArray = []
	for local_x in range(LEFT_WALL_FOOT_COLUMN, RIGHT_WALL_FOOT_COLUMN, 8):
		var ceiling_row := _find_ceiling_row(sculpt, local_x, floor_row)
		if ceiling_row < 0:
			continue
		var height := floor_row - ceiling_row
		lowest = mini(lowest, height)
		highest = maxi(highest, height)
		samples.append(str(height))
	print("roof: %d to %d cells over the floor" % [lowest, highest])
	print("roof profile every 8 columns: %s" % ", ".join(samples))
	print("open cells: %d" % sculpt.get_open_cell_count())
	print("CHAMBER_HEIGHT_ROWS_OVERRIDE must be %d" % CEILING_ROWS)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		push_error(failure)
	if _failures.is_empty():
		print("TREASURE_ROOM_CARVED")
		quit(0)
		return
	print("TREASURE_ROOM_FAILED %d" % _failures.size())
	quit(1)
