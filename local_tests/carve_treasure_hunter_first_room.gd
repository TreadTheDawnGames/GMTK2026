extends SceneTree

## Cuts the Treasure Hunter's first room: a lobed cavern with a sealed bore in
## its right-hand wall.
##
## How it works:
## - Reads the committed room and cuts ONLY with carve stamps and a derived
##   stratum pass, so it is additive and idempotent. Running it twice produces
##   the same file, and it cannot undo the swell, cones and end walls an earlier
##   pass already put in this room.
## - Bites lobes into the roof and the left wall with the Cutscene panel's own
##   built-in ALCOVE stamp, at authored columns and authored bite depths. A
##   scalloped ceiling of one uniform amplitude reads as a corridor with a rough
##   lid; lobes of different sizes read as a cavern, which is what Zephan's
##   IMG_1636 layout draws.
## - Rebuilds the per-stratum masks so three rock edges recede behind the
##   foreground silhouette and the deepest stratum closes the room. Collision
##   never reads any of it.
## - Clears anything left hanging under the ceiling, per column, before it will
##   save. A single detached cell is a landing surface: the miner stops on it,
##   the encounter never starts, and in game that reads as mining that quietly
##   stopped working with nothing in any log.
## - Verifies and refuses to save on any failure, because a room that is wrong is
##   not a room that looks wrong, it is a run that stops.
##
## The invariant this file exists to protect is that the bore stays SEALED. The
## Treasure Hunter genuinely mines in: the plug is authored solid and his three
## timeline STRIKE beats remove it at runtime. Nothing here may open it, and the
## verification proves the strike discs and the plug still agree.
##
## EDGE SMOOTHING IS ZERO, AND THAT CONTRADICTS THE RESOURCE THAT OWNS IT.
## cutscene_terrain_sculpt.gd documents 1.0 as the default and argues that
## anything lower drags the drawn contour back onto the cell grid and reads as
## stair-steps. Integration has since ruled the other way in commits 37d69a2 and
## 821e660: zero is "the pickaxe-struck edge this cave wants", it is what the
## colony room already used, and encounters 1 and 3 now ship it. Jared's brief
## for this encounter asks for the cave to be sharper, so this room follows the
## rooms either side of it rather than the comment. Worth the steward correcting
## that comment, because the next person to read it will reach for 1.0.

const ROOM_PATH: String = (
	"res://resources/cinematics/sculpts/treasure_hunter_first_room.tres"
)
const MINING_CONFIG_PATH: String = "res://resources/mining/mining_config.tres"
const ENCOUNTER_PATH: String = (
	"res://resources/encounters/treasure_hunter_first_encounter.tres"
)

## With this room's anchor offset a grid column equals its terrain column
## outright, so every number below is also a terrain column.
const GRID_SIZE := Vector2i(384, 120)
const ANCHOR_OFFSET := Vector2i(-192, -110)

## The sealed rock the Treasure Hunter comes through, and the bore behind it.
## Authored solid; only his strikes open it.
const PLUG_FIRST_X: int = 258
const PLUG_LAST_X: int = 265
const BORE_FIRST_X: int = 266

## His three wall strikes, as the stage authors them: all on column 262, at rows
## 95, 100 and 105, with Strike Breaks Rock Radius Cells at 6. Kept here as well
## as in the scene because a plug and a marker set that disagree leave him
## walking into rock with nothing in any log to say why, and this is the file
## that can prove they agree.
const STRIKE_LOCAL_X: int = 262
const STRIKE_LOCAL_ROWS: Array[int] = [95, 100, 105]
const STRIKE_RADIUS_CELLS: int = 6

## Rows of person-height passage the strikes have to leave through the plug,
## measured up from the row above the floor. Nine cells is 72 world units, which
## clears his 120px art at the scale that ships once he is standing on the loose
## rock rather than on the floor row.
const BREAKTHROUGH_PASSAGE_ROWS: int = 9

## Clear air that must survive under anything hanging from the roof, in cells.
##
## Twelve is not a comfortable number - the cast are 120px and twelve cells is
## 96px - and it is not chosen, it is measured. The committed room already
## pinches to twelve at column 176, where the swell brings the roof down, and
## that pinch is the earlier pass's authored shape rather than anything this one
## did. So this guard says what it can honestly say: the fangs may not make the
## room tighter than it already was. Raising it above twelve would refuse to save
## a room nobody has complained about, and lowering it would let a fang close the
## shot without saying so.
const MINIMUM_CAST_HEADROOM_CELLS: int = 12
## And how little the rest of the pocket may keep, so a fang outside the shot's
## standing room still reads as a room rather than as a closed seam.
const MINIMUM_ROOM_HEADROOM_CELLS: int = 10
## The columns anybody actually stands on: the 49-cell landing band the fall can
## arrive down, plus the 24 cells to the Treasure Hunter's own mark at its right
## end, with a cell of margin either side. Outside this a fang is silhouette and
## is allowed to hang lower - which is the only reason the two end fangs can
## reach as far into the frame as they do.
const CAST_COLUMN_FIRST: int = 165
const CAST_COLUMN_LAST: int = 245

## Where his walk starts. Entrance is +604px from Conversation, which is +190px
## from the miner; at the LEFTMOST landing the descent can reach, column 168,
## that puts him at column 267 + 3. Verified as open here rather than trusted,
## because a run that lands left and finds him inside rock is a shot with no
## visitor in it.
const ENTRANCE_WORST_CASE_X: int = 270

## The stalactites, as (column, rows the tip hangs above the FLOOR row).
##
## These are the panel's PILLAR stamp, 5 cells wide and 21 tall, placed so all
## but the tip is buried in the ceiling rock. That is what keeps them joined to
## the roof: a cone standing in mid-air is a ledge, the descent lands on it, and
## the encounter then sits pending forever with the cinematic gate claimed -
## which in game looks like mining that simply stopped working.
##
## THE FRAME IS 29 CELLS TALL ABOVE THE FLOOR. That single number decides this
## whole pass. The encounter camera puts the ground line at half a 648px
## viewport and the letterbox takes the top 91px, so rock above about 29 cells
## is not in the shot at all. Biting the roof upward to make the room feel like a
## cavern therefore does the opposite: it lifts the ceiling clean out of frame
## and the room reads as an open band with no roof on it. The first cut of this
## pass did exactly that and the capture is why it is not here any more.
##
## So the cave language has to come DOWN into the frame rather than up out of it.
## The three tips over the standing room leave at least 16 cells - 128px - of
## clear air against the 120px cast. The two at the ends hang further, because
## nobody stands under them and they are what stops the roof reading as one
## continuous lid.
## How many rows each column of a fang gives back, indexed by its distance from
## the fang's centre column.
const FANG_TAPER_ROWS: Array[int] = [0, 3, 6]

const CEILING_FANGS: Array[Vector2i] = [
	Vector2i(150, 18),
	Vector2i(178, 26),
	Vector2i(205, 23),
	Vector2i(228, 25),
	Vector2i(252, 17),
]

## The one raised dome, as (column, rows its top sits above the FLOOR row).
##
## Measured from the floor and not from the ceiling, which is the difference
## between a cut that reproduces and one that creeps. Placing a lobe "nine cells
## above the ceiling" reads perfectly well and is wrong: the second run measures
## the ceiling this run just raised and bites nine more, so the room grows every
## time somebody re-cuts it and no two checkouts agree. The floor row is the one
## line in this room that nothing is allowed to move.
##
## One dome and not six. Six ALCOVEs at twenty-column spacing are wider than
## their own 25-cell stamp, so they merge into a single flat lid and the jagged
## roof the earlier pass cut disappears under it.
##
## Its top is held at 29 - the top of the visible frame - rather than higher.
## Anything above that is not in the shot, and the carved height is also the
## number the encounter's Chamber Height Rows Override has to match, so a dome
## nobody can see would still push the cutscene's trigger row further up.
##
## Its centre cannot go past column 244. An ALCOVE is 25 cells wide, so a centre
## at 246 would reach column 258 and eat the first column of the plug - the one
## cut in this file that would silently turn "he mines in" back into "he walks
## through a hole that was always there".
const ROOF_DOME := Vector2i(190, 29)

## The left-hand bay, as an absolute cell rather than "wherever the wall is".
##
## Column 137 is the wall face at row 99 in the committed room, so the stamp
## bites sideways into rock rather than upward into air. It is written down
## rather than measured for the same reason the roof lobes are: a stamp centred
## on the wall it just moved walks another twelve cells left on every re-cut.
##
## It sits well left of the landing band, which starts at column 168, so the
## sill it leaves cannot catch the fall. That is the only reason a bay is safe
## on this side and not on the other - the right-hand wall is the plug.
const LEFT_BAY_CELL := Vector2i(137, 99)

## How far behind the foreground silhouette each drawn stratum stands, in cells.
##
## This is the 2.5D read, and it is three numbers rather than one: the opening
## each stratum draws is the logical opening grown by its own amount, so the
## room has a near rim, two receding rock edges behind it, and a backdrop. The
## previous pass on this room used roughly half these values and the room read
## noticeably flatter than encounter 3's, which is cut from the same cave.
##
## Collision never reads any of it. solid_bits stays the only truth for where
## anyone can stand, which is what leaves the guarded floor, the plug and the
## bore exactly as the passes above left them.
const STRATUM_RECESSION_CELLS: Array[int] = [0, 4, 8]
## The deepest stratum closes the room behind all of them.
const BACKDROP_LAYER_INDEX: int = 3
const VISUAL_STRATUM_COUNT: int = 4

var _failures: Array[String] = []


func _initialize() -> void:
	var sculpt := load(ROOM_PATH) as CutsceneTerrainSculpt
	var mining_config := load(MINING_CONFIG_PATH) as MiningConfig
	if sculpt == null or mining_config == null:
		push_error("The Treasure Hunter carve could not load its room or config.")
		quit(1)
		return

	if sculpt.grid_size != GRID_SIZE or sculpt.anchor_offset_cells != ANCHOR_OFFSET:
		push_error(
			(
				"The room's footprint moved (grid %s, anchor %s). Every column "
				+ "constant in this file is a terrain column and none of them "
				+ "survive that; re-derive them before cutting."
			) % [sculpt.grid_size, sculpt.anchor_offset_cells]
		)
		quit(1)
		return

	_cut_room(sculpt)
	_verify_room(sculpt, mining_config)

	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("TREASURE_HUNTER_ROOM_CARVE_FAIL: %s" % failure)
		print(
			"TREASURE_HUNTER_ROOM_CARVE: NOT SAVED (%d problems)"
			% _failures.size()
		)
		quit(1)
		return

	var save_error := ResourceSaver.save(sculpt, ROOM_PATH)
	if save_error != OK:
		push_error(
			"Could not save the Treasure Hunter room: %s"
			% error_string(save_error)
		)
		quit(1)
		return
	print("TREASURE_HUNTER_ROOM_CARVE: SAVED %s" % ROOM_PATH)
	print("  open cells=%d" % sculpt.get_open_cell_count())
	quit(0)


## Runs every cutting pass in the order the room depends on.
func _cut_room(sculpt: CutsceneTerrainSculpt) -> void:
	sculpt.enabled = true
	sculpt.protected_floor_rows = 3
	# Zero, which follows the cells the room was cut on rather than
	# interpolating every rim onto the sub-cell contour. See the note at the top
	# of this file: the sculpt resource argues the other way and integration has
	# since ruled against it on two rooms.
	sculpt.edge_smoothing = 0.0

	_stamp_roof_dome(sculpt)
	_stamp_ceiling_fangs(sculpt)
	_stamp_left_bay(sculpt)
	# Last, and after every pass that can leave rock in mid-air.
	_clear_hanging_rock(sculpt)
	_apply_receding_strata(sculpt)


## Bites the panel's ALCOVE stamp up into the ceiling at the one dome column.
##
## The stamp is centred so its lower half lands in air the room already has,
## which is what keeps the dome joined to the ceiling instead of opening a
## pocket above a bar of floating rock.
func _stamp_roof_dome(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	var ceiling_row := _get_ceiling_row(sculpt, ROOF_DOME.x)
	if ceiling_row < 0:
		_failures.append(
			"Dome column %d has no ceiling to bite into." % ROOF_DOME.x
		)
		return
	# An ALCOVE is 15 cells tall, so its centre sits seven rows below its top
	# edge, and the top edge is the authored height above the floor.
	var top_row := floor_row - ROOF_DOME.y
	if top_row + 14 < ceiling_row:
		_failures.append(
			(
				"The dome at column %d would float: its underside is row %d "
				+ "and the ceiling there is row %d, so it opens a pocket in "
				+ "the rock instead of biting into the roof."
			) % [ROOF_DOME.x, top_row + 14, ceiling_row]
		)
		return
	var brush := CutsceneSculptBrush.new()
	sculpt.begin_edit()
	brush.apply_builtin_stamp(
		sculpt,
		Vector2i(ROOF_DOME.x, top_row + 7),
		CutsceneSculptBrush.STAMP_ALCOVE
	)
	sculpt.end_edit()


## Hangs the panel's PILLAR stamp from the ceiling at each authored column.
##
## A PILLAR is 21 cells tall and only its last few are wanted, so it is placed
## by its TIP: the authored height above the floor is where the fang ends, and
## the other sixteen-odd cells land inside the roof, where filling rock that is
## already rock changes nothing. That is what joins every fang to the ceiling in
## all five of its columns however the roof waves across them, and a fang joined
## to the ceiling leaves the fall line exactly as it was.
##
## It is refused rather than trusted: a fang whose top is below the ceiling is
## rock standing in open air, which is a ledge the descent lands on.
func _stamp_ceiling_fangs(sculpt: CutsceneTerrainSculpt) -> void:
	var brush := CutsceneSculptBrush.new()
	var floor_row := sculpt.get_floor_local_row()
	sculpt.begin_edit()
	for fang: Vector2i in CEILING_FANGS:
		var tip_row := floor_row - fang.y
		var top_row := tip_row - 20
		var lowest_ceiling_row := -1
		for offset_x in range(-2, 3):
			var ceiling_row := _get_ceiling_row(sculpt, fang.x + offset_x)
			if ceiling_row < 0:
				continue
			lowest_ceiling_row = maxi(lowest_ceiling_row, ceiling_row)
		if lowest_ceiling_row < 0:
			_failures.append(
				"Fang column %d has no ceiling to hang from." % fang.x
			)
			continue
		if top_row > lowest_ceiling_row:
			_failures.append(
				(
					"The fang at column %d starts at row %d, below the lowest "
					+ "ceiling in its own span at row %d. It would stand in "
					+ "open air, and floating rock is a ledge the fall lands "
					+ "on."
				) % [fang.x, top_row, lowest_ceiling_row]
			)
			continue
		brush.apply_builtin_stamp(
			sculpt,
			Vector2i(fang.x, tip_row - 10),
			CutsceneSculptBrush.STAMP_PILLAR
		)
		_taper_fang(sculpt, fang.x, tip_row)
	sculpt.end_edit()


## Cuts the square corners off a stamped fang so it comes to a point.
##
## A PILLAR is a rectangle, which is the right stamp for a stalactite and the
## wrong silhouette for one: five columns all ending on the same row read as a
## chimney block hanging out of the roof. Each column outside the centre gives
## back FANG_TAPER_ROWS so the underside steps to a tip.
##
## Carving here rather than filling less is what keeps the pass idempotent. The
## cells it takes back were open air before the stamp, so a second run takes
## back exactly the same ones and the fang stops at the same point.
func _taper_fang(
	sculpt: CutsceneTerrainSculpt,
	center_x: int,
	tip_row: int
) -> void:
	for offset_x in range(-2, 3):
		var shorten := FANG_TAPER_ROWS[absi(offset_x)]
		if shorten <= 0:
			continue
		for local_y in range(tip_row - shorten + 1, tip_row + 1):
			sculpt.set_solid_local(
				Vector2i(center_x + offset_x, local_y),
				false
			)


## Bites one bay into the left-hand wall.
func _stamp_left_bay(sculpt: CutsceneTerrainSculpt) -> void:
	var brush := CutsceneSculptBrush.new()
	sculpt.begin_edit()
	brush.apply_builtin_stamp(
		sculpt,
		LEFT_BAY_CELL,
		CutsceneSculptBrush.STAMP_ALCOVE
	)
	sculpt.end_edit()


## Returns the first open row at a column, or -1 if the column is solid.
func _get_ceiling_row(sculpt: CutsceneTerrainSculpt, local_x: int) -> int:
	for local_y in range(sculpt.get_floor_local_row()):
		if not sculpt.is_solid_local(Vector2i(local_x, local_y)):
			return local_y
	return -1


## Empties every column from its topmost opening down to the rock on its floor.
##
## This is the rule that has to be absolute rather than a protected band under
## the ceiling: a lump inside the band catches a falling miner exactly the same
## way one above it does. The ceiling still reads jagged afterwards, because its
## height varies column to column, and a roof does not need debris hanging under
## it to look like rock.
##
## The ground is found by scanning UP from the floor row rather than down from
## the ceiling. Downward finds the first solid cell below the opening, which is
## the right answer only when nothing is hanging, and the entire reason for
## looking is that something might be.
func _clear_hanging_rock(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	sculpt.begin_edit()
	for local_x in range(sculpt.grid_size.x):
		var topmost_open_row := -1
		for local_y in range(floor_row):
			if not sculpt.is_solid_local(Vector2i(local_x, local_y)):
				topmost_open_row = local_y
				break
		if topmost_open_row < 0:
			continue
		var ground_row := floor_row
		while (
			ground_row - 1 > topmost_open_row
			and sculpt.is_solid_local(Vector2i(local_x, ground_row - 1))
		):
			ground_row -= 1
		for local_y in range(topmost_open_row, ground_row):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)
	sculpt.end_edit()


## Rebuilds every stratum's drawn rock from the finished logical mask.
##
## THIS IS THE 2.5D READ AND IT IS AN INSIDE-OUT OPERATION. The room is open on
## every stratum once it is cut, and the deepest one is held solid as a backdrop,
## so what a player sees inside a sculpted room is the backdrop tint and nothing
## else - one flat slab, whatever the roof is doing. Depth comes from putting
## rock BACK on the middle strata in a band that hugs the rim: the first few
## cells inside the opening draw stratum one, the next few draw stratum two, and
## only past both does the backdrop show. Three tints stepping away from the wall
## is the whole effect.
##
## The first cut of this pass had the sign the other way round - it opened the
## middle strata in a band OUTSIDE the rim - which is invisible, because stratum
## zero is solid there and drawn in front of all of it. The capture is why this
## comment exists.
##
## The bands are 4 and 8 cells against the baker's shared 2, because this room is
## seen at encounter framing rather than at mining zoom and a two-cell step reads
## as an outline rather than as distance.
##
## Rock is only counted ABOVE or BESIDE a cell, never below it, which is the same
## rule the baker uses. Counting the floor would draw a band of near rock along
## the ground the cast stand on and bury their feet in a rim.
##
## Derived entirely from solid_bits, which is what makes re-running this script
## reproduce the same file rather than eroding the room a little further every
## time. Collision never reads any of it: solid_bits stays the only truth for
## where anyone can stand, which is what leaves the guarded floor, the plug and
## the bore exactly as the passes above left them.
func _apply_receding_strata(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	sculpt.begin_edit()
	sculpt.ensure_layer_masks(VISUAL_STRATUM_COUNT)
	for local_y in range(sculpt.grid_size.y):
		for local_x in range(sculpt.grid_size.x):
			var local_cell := Vector2i(local_x, local_y)
			var logical_solid := sculpt.is_solid_local(local_cell)
			for layer_index in range(VISUAL_STRATUM_COUNT):
				sculpt.set_layer_solid_local(
					layer_index,
					local_cell,
					logical_solid
				)
			if logical_solid or local_y >= floor_row:
				continue
			sculpt.set_layer_solid_local(
				BACKDROP_LAYER_INDEX,
				local_cell,
				true
			)
			var reach := _get_reach_to_rock(sculpt, local_cell)
			if reach < 0:
				continue
			for layer_index in range(STRATUM_RECESSION_CELLS.size()):
				if STRATUM_RECESSION_CELLS[layer_index] <= 0:
					continue
				if reach <= STRATUM_RECESSION_CELLS[layer_index]:
					sculpt.set_layer_solid_local(layer_index, local_cell, true)
	sculpt.end_edit()


## Returns how far one open cell is from the nearest rock above or beside it, or
## -1 when no rock is within the deepest band.
##
## Manhattan reach inside a half-kernel, matching CutsceneSculptBaker's own rim
## test so the two agree about what "against the wall" means. The kernel is small
## enough - eight rows by seventeen columns at the deepest band - that scanning
## it per open cell costs less than the bookkeeping a distance transform would
## need to stay honest about the excluded direction.
func _get_reach_to_rock(
	sculpt: CutsceneTerrainSculpt,
	local_cell: Vector2i
) -> int:
	var deepest: int = STRATUM_RECESSION_CELLS[STRATUM_RECESSION_CELLS.size() - 1]
	var nearest := -1
	for offset_y in range(-deepest, 1):
		for offset_x in range(-deepest, deepest + 1):
			if offset_x == 0 and offset_y == 0:
				continue
			var reach := absi(offset_x) + absi(offset_y)
			if reach > deepest:
				continue
			if nearest >= 0 and reach >= nearest:
				continue
			if sculpt.is_solid_local(
				local_cell + Vector2i(offset_x, offset_y)
			):
				nearest = reach
	return nearest


## Proves the room before it is allowed to exist on disk.
func _verify_room(
	sculpt: CutsceneTerrainSculpt,
	mining_config: MiningConfig
) -> void:
	var sculpt_error := sculpt.get_sculpt_error()
	if not sculpt_error.is_empty():
		_failures.append("The room is unusable: %s" % sculpt_error)
		return

	var floor_row := sculpt.get_floor_local_row()
	var half_span := mining_config.snake_half_span_cells
	var landing_rows := sculpt.get_landing_local_rows(half_span)
	var first_local_x := sculpt.get_landing_first_local_x(half_span)
	if landing_rows.is_empty():
		_failures.append("No column in the landing band is reachable at all.")
		return

	var tolerance := DepthEncounterController.LANDING_FLOOR_TOLERANCE_ROWS
	var worst_shortfall := 0
	for index in range(landing_rows.size()):
		var landing_row := landing_rows[index]
		var column := first_local_x + index
		if landing_row < 0:
			_failures.append("Column %d has nothing to land on." % column)
			continue
		var shortfall := floor_row - landing_row
		worst_shortfall = maxi(worst_shortfall, shortfall)
		if shortfall > tolerance:
			_failures.append(
				(
					"Column %d stops the fall %d rows above the floor, past "
					+ "the controller's %d-row tolerance."
				) % [column, shortfall, tolerance]
			)

	_verify_cast_headroom(sculpt)
	_verify_front_stratum_matches_collision(sculpt)
	_verify_arrival_trigger_matches_the_roof(sculpt, floor_row)
	_verify_sealed_bore(sculpt, floor_row)
	_verify_strikes_open_the_plug(sculpt, floor_row)

	# He has to be standing in air at the worst landing, or the walk starts
	# inside the rock he is about to break.
	if _get_contiguous_headroom(sculpt, ENTRANCE_WORST_CASE_X) <= 0:
		_failures.append(
			"Column %d, his entrance at the leftmost landing, is solid rock."
			% ENTRANCE_WORST_CASE_X
		)

	_report_room_shape(sculpt, floor_row, landing_rows.size(), worst_shortfall, tolerance)


## Proves nothing this pass hung from the roof crowds the two of them.
##
## The cast are 120px tall and stand on loose rock rather than on the floor row,
## so a fang that leaves fewer than MINIMUM_CAST_HEADROOM_CELLS of clear air
## comes down through the shot rather than into the top of it. Checked across the
## whole pocket, because the miner's landing column moves and the fangs do not.
func _verify_cast_headroom(sculpt: CutsceneTerrainSculpt) -> void:
	for local_x in range(140, PLUG_FIRST_X):
		var headroom := _get_contiguous_headroom(sculpt, local_x)
		if headroom <= 0:
			continue
		var stands_here := (
			local_x >= CAST_COLUMN_FIRST and local_x <= CAST_COLUMN_LAST
		)
		var required := (
			MINIMUM_CAST_HEADROOM_CELLS
			if stands_here
			else MINIMUM_ROOM_HEADROOM_CELLS
		)
		if headroom < required:
			_failures.append(
				(
					"Column %d has only %d cells of clear air, under the %d "
					+ "it needs. Something hanging from the roof is in the "
					+ "shot rather than over it."
				) % [local_x, headroom, required]
			)
			return


## Proves the silhouette the player reads is the silhouette collision agrees with.
##
## This is the room's parity invariant, and it is the one thing the stratum pass
## could plausibly break. Stratum zero is the frontmost drawn rock, so its edge IS
## the wall as far as a player is concerned; strata one and two stand behind it
## and may differ freely, which is the whole point of them. If stratum zero ever
## drifts from solid_bits, the drawn wall and the wall you can stand against stop
## being the same wall, and no amount of looking at the room will tell you - the
## rock still looks like rock.
##
## Checked here rather than through the F3 overlay because the overlay cannot be
## rendered through the editor preview at all; capture_treasure_hunter_first_stage.gd
## carries the full explanation. Cell for cell over the whole grid is stronger
## evidence than a screenshot would have been anyway.
func _verify_front_stratum_matches_collision(
	sculpt: CutsceneTerrainSculpt
) -> void:
	var mismatches := 0
	var first_mismatch := Vector2i(-1, -1)
	for local_y in range(sculpt.grid_size.y):
		for local_x in range(sculpt.grid_size.x):
			var local_cell := Vector2i(local_x, local_y)
			if (
				sculpt.is_layer_solid_local(0, local_cell)
				== sculpt.is_solid_local(local_cell)
			):
				continue
			if mismatches == 0:
				first_mismatch = local_cell
			mismatches += 1
	if mismatches > 0:
		_failures.append(
			(
				"The front stratum disagrees with collision in %d cells, first "
				+ "at %s. The drawn wall and the wall the cast stand against "
				+ "have to be the same wall."
			) % [mismatches, first_mismatch]
		)


## Proves the encounter is captured where this room's roof actually is.
##
## The schedule captures the run when it comes within Chamber Height Rows of the
## floor, and that row has to be the room's own opening. Leave it at the shared
## default of 24 over a room carved 31 rows up and the miner breaks through the
## roof and falls seven rows through open air with nothing happening - which is
## the fault encounter 3 shipped a fix for in 37d69a2. Set it higher than the
## carve and the cutscene starts while he is still inside solid rock.
##
## Nothing else in the project ties these two numbers together: the override
## lives on the encounter resource and the opening lives in this file, and a
## later carve that opens the roof further would silently put the trigger back
## inside the room. This check is that tie, and it is why the encounter resource
## is loaded by a script that otherwise only touches the sculpt.
func _verify_arrival_trigger_matches_the_roof(
	sculpt: CutsceneTerrainSculpt,
	floor_row: int
) -> void:
	var encounter := load(ENCOUNTER_PATH) as DepthCharacterEncounter
	if encounter == null:
		_failures.append("The encounter resource could not be loaded.")
		return
	var highest_open_row := floor_row
	for local_x in range(sculpt.grid_size.x):
		for local_y in range(floor_row):
			if not sculpt.is_solid_local(Vector2i(local_x, local_y)):
				highest_open_row = mini(highest_open_row, local_y)
				break
	var carved_height := floor_row - highest_open_row
	if encounter.chamber_height_rows_override != carved_height:
		_failures.append(
			(
				"The room is carved %d rows above its floor but the encounter's "
				+ "Chamber Height Rows Override is %d. Set the override to %d, "
				+ "or the shot starts in the wrong place: too low and he falls "
				+ "through open air before anything begins, too high and it "
				+ "starts while he is still in the rock."
			) % [
				carved_height,
				encounter.chamber_height_rows_override,
				carved_height,
			]
		)


## Proves the wall he mines through is still authored closed.
func _verify_sealed_bore(sculpt: CutsceneTerrainSculpt, floor_row: int) -> void:
	for local_x in range(PLUG_FIRST_X, PLUG_LAST_X + 1):
		if _get_contiguous_headroom(sculpt, local_x) > 0:
			_failures.append(
				(
					"Plug column %d is open air. The bore must be authored "
					+ "SEALED - his swings are what open it, and a bore cut "
					+ "open turns the whole beat into dust thrown at a hole "
					+ "that was always there."
				) % local_x
			)
			return
	if _get_contiguous_headroom(sculpt, BORE_FIRST_X) <= 0:
		_failures.append(
			"Column %d is solid, so there is no bore behind the plug at all."
			% BORE_FIRST_X
		)


## Proves his three authored swings actually take the plug out.
##
## The disc is resolved exactly as TerrainManager.break_presentation_pocket
## resolves it - per row, half-width floor(sqrt(r^2 - dy^2)), guarded floor rows
## skipped - so a marker set that has drifted off the plug fails here rather than
## in a run, where it looks like a man walking into a wall.
func _verify_strikes_open_the_plug(
	sculpt: CutsceneTerrainSculpt,
	floor_row: int
) -> void:
	var first_row := floor_row - BREAKTHROUGH_PASSAGE_ROWS
	for local_y in range(first_row, floor_row):
		for local_x in range(PLUG_FIRST_X, PLUG_LAST_X + 1):
			if not _strikes_reach(local_x, local_y):
				_failures.append(
					(
						"The three wall strikes leave plug cell (%d, %d) "
						+ "standing, so his passage is not person-height. "
						+ "Move the strike markers or narrow the plug."
					) % [local_x, local_y]
				)
				return


## Reports whether any authored strike disc covers one cell.
func _strikes_reach(local_x: int, local_y: int) -> bool:
	for strike_row: int in STRIKE_LOCAL_ROWS:
		var row_offset := local_y - strike_row
		if absi(row_offset) > STRIKE_RADIUS_CELLS:
			continue
		var half_width := floori(sqrt(
			float(
				STRIKE_RADIUS_CELLS * STRIKE_RADIUS_CELLS
				- row_offset * row_offset
			)
		))
		if absi(local_x - STRIKE_LOCAL_X) <= half_width:
			return true
	return false


## Prints the shape the cut actually produced, so a change is readable in the
## diff of a run rather than only in the diff of the file.
func _report_room_shape(
	sculpt: CutsceneTerrainSculpt,
	floor_row: int,
	landing_column_count: int,
	worst_shortfall: int,
	tolerance: int
) -> void:
	var lowest_ceiling := sculpt.grid_size.y
	var highest_ceiling := 0
	for local_x in range(140, 258):
		var headroom := _get_contiguous_headroom(sculpt, local_x)
		lowest_ceiling = mini(lowest_ceiling, headroom)
		highest_ceiling = maxi(highest_ceiling, headroom)
	var recessed_cells := PackedInt32Array()
	for layer_index in range(VISUAL_STRATUM_COUNT):
		var count := 0
		for local_y in range(floor_row):
			for local_x in range(sculpt.grid_size.x):
				var local_cell := Vector2i(local_x, local_y)
				if (
					not sculpt.is_solid_local(local_cell)
					and sculpt.is_layer_solid_local(layer_index, local_cell)
				):
					count += 1
		recessed_cells.append(count)
	print(
		"TREASURE_HUNTER_ROOM_CARVE: landing columns=%d worst=%d/%d rows"
		% [landing_column_count, worst_shortfall, tolerance]
	)
	print(
		"  cavern headroom %d..%d cells across the pocket"
		% [lowest_ceiling, highest_ceiling]
	)
	print("  cells of near rock each stratum draws inside the room: %s" % [recessed_cells])


## Returns the rows of unbroken open air standing on the ground at one column.
##
## Contiguous, not ceiling-to-floor: the second number cheerfully ignores
## whatever is floating in the middle of it, which is the thing being checked.
func _get_contiguous_headroom(
	sculpt: CutsceneTerrainSculpt,
	local_x: int
) -> int:
	var floor_row := sculpt.get_floor_local_row()
	var ground_row := floor_row
	while (
		ground_row - 1 >= 0
		and sculpt.is_solid_local(Vector2i(local_x, ground_row - 1))
	):
		ground_row -= 1
		if floor_row - ground_row > sculpt.grid_size.y:
			break
	var open_rows := 0
	var local_y := ground_row - 1
	while local_y >= 0 and not sculpt.is_solid_local(Vector2i(local_x, local_y)):
		open_rows += 1
		local_y -= 1
	return open_rows
