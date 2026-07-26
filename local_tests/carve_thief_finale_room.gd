extends SceneTree

## Cuts the Thief finale's room: a dug tunnel that opens into a vault.
##
## How it works:
## - Starts from the shared level-tunnel cut, so the room the miner lands in is
##   the same corridor language as every other encounter. That is the point of
##   the shot: nothing about the arrival says this one is different.
## - Then sweeps a vault out of the rock well to the right of the landing band,
##   twice the corridor's height, and leaves the roof between them climbing into
##   it. The organ stands under that vault, off screen, and the camera pan is the
##   only thing that reveals it.
## - Walls both ends. Every other room is a corridor open to somewhere; this one
##   is a destination, and a chamber the player cannot see past is what says the
##   digging has arrived rather than passed through.
## - Clears anything left hanging under the ceiling, per column, before it will
##   save. A single detached cell is a landing surface: the miner stops on it,
##   the encounter never starts, and in game that reads as mining that quietly
##   stopped working with nothing in any log.
## - Verifies and refuses to save on any failure, because a room that is wrong is
##   not a room that looks wrong, it is a run that stops.
##
## Every pass is deterministic from the cell coordinate, so re-running reproduces
## this room exactly and a designer who reopens it in the Cutscene panel finds
## work they can continue.

const ROOM_PATH: String = (
	"res://resources/cinematics/sculpts/thief_finale_room.tres"
)
const MINING_CONFIG_PATH: String = "res://resources/mining/mining_config.tres"

## Full terrain width, so one room holds both the landing shaft and the vault.
const GRID_SIZE := Vector2i(384, 120)
## Places the grid's centre column on the encounter anchor and reaches 110 rows
## above the floor, leaving 10 below it for the floor itself to be shaped.
const ANCHOR_OFFSET := Vector2i(-192, -110)
## With this offset a grid column equals its terrain column outright, so the
## landing band really is columns 168 to 216 in this file's coordinates too.
const ROOM_CENTRE_X: int = 192

## Where the organ stands, and how wide a berth the vault gives it.
##
## 120 cells is 960px, and the frame is 1152px wide centred on the miner. Even
## when he lands at the far right of his 49-column band the organ's near edge is
## still 88px outside the shot, so it cannot be glimpsed before the pan. That
## clearance is the whole reason this number is not smaller.
const ORGAN_LOCAL_X: int = ROOM_CENTRE_X + 120
## How far the vault holds its full height before it starts coming down.
##
## THIS IS WIDE ON PURPOSE AND IT COST A RENDER TO LEARN. A pointed arch over the
## organ alone is invisible: the encounter framing puts the ground line at half
## the viewport and the letterbox covers the top 91px, so only about 29 rows of
## air above the floor are ever on screen. A 44-row vault is off the top of the
## frame whatever shape it is, and a narrow one reads as a black notch punched in
## the ceiling directly over the instrument rather than as a chamber.
##
## Held flat across 34 cells, the ceiling is simply gone across 544px of a 1152px
## shot, with rock closing back in at both edges. That reads as a room too tall
## to see the top of, which is the only version of "cathedral" this camera can
## actually deliver.
const VAULT_HALF_SPAN_CELLS: int = 34
## Rows of clear air over the organ. The corridor settles around 22 to 27, so the
## roof climbing into this is the largest change in the room's shape anywhere.
const VAULT_HEIGHT_CELLS: int = 44
## How the vault comes down across the blend once it leaves the plateau. Below
## one it falls away slowly and then steepens, so the roof reads as springing off
## the corridor rather than as a ramp bolted onto it.
const VAULT_APEX_SHARPNESS: float = 0.55

## The end walls, as the foot and face columns the baker leans between.
const LEFT_WALL_FOOT_X: int = 148
const LEFT_WALL_FACE_X: int = 128
const RIGHT_WALL_FOOT_X: int = 356
const RIGHT_WALL_FACE_X: int = 376

## The corridor roof must genuinely climb into the vault rather than step into
## it, so the sweep that cuts the vault is blended out over this many cells.
const VAULT_BLEND_CELLS: int = 22

var _failures: Array[String] = []


func _initialize() -> void:
	var sculpt := load(ROOM_PATH) as CutsceneTerrainSculpt
	var mining_config := load(MINING_CONFIG_PATH) as MiningConfig
	if sculpt == null or mining_config == null:
		push_error("The finale carve could not load its room or config.")
		quit(1)
		return

	_cut_room(sculpt)
	_verify_room(sculpt, mining_config)

	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("THIEF_ROOM_CARVE_FAIL: %s" % failure)
		print("THIEF_ROOM_CARVE: NOT SAVED (%d problems)" % _failures.size())
		quit(1)
		return

	var save_error := ResourceSaver.save(sculpt, ROOM_PATH)
	if save_error != OK:
		push_error("Could not save the finale room: %s" % error_string(save_error))
		quit(1)
		return
	print("THIEF_ROOM_CARVE: SAVED %s" % ROOM_PATH)
	print("  open cells=%d" % sculpt.get_open_cell_count())
	quit(0)


## Runs every cutting pass in the order the room depends on.
func _cut_room(sculpt: CutsceneTerrainSculpt) -> void:
	sculpt.enabled = true
	sculpt.grid_size = GRID_SIZE
	sculpt.anchor_offset_cells = ANCHOR_OFFSET
	sculpt.protected_floor_rows = 3

	# The shared corridor first. Everything after this is an edit on top of a
	# room that already reads as one of the game's tunnels.
	CutsceneSculptBaker.carve_level_tunnel(sculpt)
	_carve_vault(sculpt)
	CutsceneSculptBaker.carve_jagged_end_wall(
		sculpt,
		LEFT_WALL_FOOT_X,
		LEFT_WALL_FACE_X
	)
	CutsceneSculptBaker.carve_jagged_end_wall(
		sculpt,
		RIGHT_WALL_FOOT_X,
		RIGHT_WALL_FACE_X
	)
	# Last, and after every pass that can leave rock in mid-air.
	_clear_hanging_rock(sculpt)
	CutsceneSculptBaker.apply_visual_depth_masks(sculpt)


## Sweeps the vault over the organ and blends the corridor roof up into it.
func _carve_vault(sculpt: CutsceneTerrainSculpt) -> void:
	var floor_row := sculpt.get_floor_local_row()
	var reach := VAULT_HALF_SPAN_CELLS + VAULT_BLEND_CELLS
	sculpt.begin_edit()
	for local_x in range(
		maxi(ORGAN_LOCAL_X - reach, 0),
		mini(ORGAN_LOCAL_X + reach + 1, sculpt.grid_size.x)
	):
		var lift := _get_vault_lift_cells(local_x)
		if lift <= 0:
			continue
		# Open from the vault's own ceiling down to the floor. The corridor pass
		# already opened the lower rows; this only takes the rock above them.
		var vault_ceiling_row := maxi(floor_row - lift, 0)
		for local_y in range(vault_ceiling_row, floor_row):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)
	sculpt.end_edit()

	# The swept arch is a clean curve, and a clean curve reads as built. One
	# roughen pass along it breaks the sweep into rock without opening holes:
	# roughen only flips cells already on a solid/open boundary.
	var brush := CutsceneSculptBrush.new()
	brush.radius_cells = 5.0
	brush.strength = 0.4
	brush.falloff = 0.6
	for local_x in range(
		maxi(ORGAN_LOCAL_X - reach, 0),
		mini(ORGAN_LOCAL_X + reach + 1, sculpt.grid_size.x),
		4
	):
		var lift := _get_vault_lift_cells(local_x)
		if lift <= 0:
			continue
		brush.seed_value = local_x
		brush.roughen(
			sculpt,
			Vector2(float(local_x), float(floor_row - lift))
		)


## Returns how many rows above the floor the vault reaches at one column.
##
## Zero outside the sweep, so a caller can skip a column without asking twice.
## Full height across the plateau and then falling to nothing across the blend,
## which is what makes the corridor roof climb into the vault instead of meeting
## it at a corner.
func _get_vault_lift_cells(local_x: int) -> int:
	var distance := absf(float(local_x - ORGAN_LOCAL_X))
	if distance <= float(VAULT_HALF_SPAN_CELLS):
		return VAULT_HEIGHT_CELLS
	var blend := float(maxi(VAULT_BLEND_CELLS, 1))
	var blend_distance := distance - float(VAULT_HALF_SPAN_CELLS)
	if blend_distance >= blend:
		return 0
	var falloff := clampf(1.0 - blend_distance / blend, 0.0, 1.0)
	return int(
		roundf(float(VAULT_HEIGHT_CELLS) * pow(falloff, VAULT_APEX_SHARPNESS))
	)


## Empties every column from its topmost opening down to the rock on its floor.
##
## This is the rule that has to be absolute rather than a protected band under
## the ceiling: a lump inside the band catches a falling miner exactly the same
## way one above it does. The ceiling still reads jagged afterwards, because its
## height varies column to column - that is what the roughen passes moved, and
## a roof does not need debris hanging under it to look like rock.
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
		# Walk up off the floor while the rock stays continuous with it. That
		# last solid row is the ground; everything above it must be air.
		var ground_row := floor_row
		while (
			ground_row - 1 > topmost_open_row
			and sculpt.is_solid_local(Vector2i(local_x, ground_row - 1))
		):
			ground_row -= 1
		for local_y in range(topmost_open_row, ground_row):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)
	sculpt.end_edit()


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
			_failures.append(
				"Column %d has nothing to land on." % column
			)
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

	# The organ has to fit under its own vault with room to spare, or the pan
	# arrives at an instrument buried in the ceiling.
	var organ_headroom := _get_contiguous_headroom(sculpt, ORGAN_LOCAL_X)
	if organ_headroom < VAULT_HEIGHT_CELLS - 6:
		_failures.append(
			"The vault over the organ is only %d rows of standing air."
			% organ_headroom
		)

	# Both ends have to actually be closed, or the chamber reads as more
	# corridor and the arrival is not an arrival.
	for wall_column in [LEFT_WALL_FACE_X - 8, RIGHT_WALL_FACE_X + 8]:
		if wall_column < 0 or wall_column >= sculpt.grid_size.x:
			continue
		if _get_contiguous_headroom(sculpt, wall_column) > 0:
			_failures.append(
				"Column %d is open air, so that end of the room is not walled."
				% wall_column
			)

	print(
		"THIEF_ROOM_CARVE: landing columns=%d worst=%d/%d rows, organ headroom=%d"
		% [landing_rows.size(), worst_shortfall, tolerance, organ_headroom]
	)
	_report_prop_ground(sculpt, mining_config)


## Prints where a prop standing at the organ has to be authored.
##
## A prop is not floor-sampled the way the cast are: it is a static node at the y
## that was typed. The level tunnel lays loose rock along the floor row, so a
## prop left on y = 0 stands buried to its knees in the surface the cast are
## standing on, and in the editor it looks correct because the preview draws the
## rock over it exactly as the game will.
##
## The whole span the organ covers is reported, not just its centre column,
## because loose rock is uneven and one static prop cannot follow it. The spread
## between these numbers is the error the shot has to live with.
func _report_prop_ground(
	sculpt: CutsceneTerrainSculpt,
	mining_config: MiningConfig
) -> void:
	var floor_row := sculpt.get_floor_local_row()
	var cell_size := mining_config.terrain_cell_world_size
	var highest_ground := floor_row
	var lowest_ground := 0
	for local_x in range(ORGAN_LOCAL_X - 12, ORGAN_LOCAL_X + 13):
		var ground_row := floor_row
		while (
			ground_row - 1 >= 0
			and sculpt.is_solid_local(Vector2i(local_x, ground_row - 1))
		):
			ground_row -= 1
		highest_ground = mini(highest_ground, ground_row)
		lowest_ground = maxi(lowest_ground, ground_row)
	print(
		"  organ ground rows %d..%d of floor %d -> author prop y between %d and %d"
		% [
			highest_ground,
			lowest_ground,
			floor_row,
			(highest_ground - floor_row) * cell_size,
			(lowest_ground - floor_row) * cell_size,
		]
	)


## Returns the rows of unbroken open air standing on the ground at one column.
##
## Contiguous, not ceiling-to-floor: the second number cheerfully ignores
## whatever is floating in the middle of it, which is the thing being checked.
##
## It starts from the ground rather than from the floor row, because the level
## tunnel lays up to three cells of loose rock along the floor and that rock is
## what the miner stands on. Measuring from the floor row would read a column
## with a bump in it as having no air above it at all.
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
