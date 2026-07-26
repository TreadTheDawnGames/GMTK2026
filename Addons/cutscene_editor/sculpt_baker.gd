@tool
class_name CutsceneSculptBaker
extends RefCounted

## How it works:
## - Uses the encounter's resolved floor as the sculpt anchor cell.
## - Converts every local sculpt cell to a world cell before querying the
##   existing chamber-row and horizontal-bound rules.
## - Writes open chamber cells and solid cells everywhere else in one batch.
## - carve_right_exit_tunnel adds the shared walk-off corridor to any room.
## - Every completed cut derives visible-only stratum masks: layer two forms
##   the receding wall rim and the room-selected deep layer closes the backdrop.
## - It owns no persistent state and returns after the sculpt has been seeded.
## The invariant is that a baked cell uses the same two config queries as
## procedural terrain, so an untouched bake has identical logical collision.

## Clear height of the rectangle the tunnel starts as, in terrain cells. The
## finished ceiling sits higher than this: the strikes that scallop it bite
## upward by their own radius, which lands the real clear height around 22 to 27
## cells, or 176 to 216 world units. That is tall enough to hold the cast with
## headroom and low enough to still read as a tunnel rather than as the open
## chamber it replaces. Raise this and the strike radius together, or the roof
## goes up without the scallops following it.
const LEVEL_TUNNEL_HEIGHT_CELLS: int = 16
## How far the tunnel roof rises and falls along the room, and how many times.
## A ruler-straight roof is the one thing that reads as cut by a tool rather
## than worn by water.
const LEVEL_TUNNEL_ROOF_WAVE_CELLS: float = 3.0
const LEVEL_TUNNEL_ROOF_WAVE_COUNT: float = 3.0
## The bite one pickaxe strike takes out of the ceiling, and how far apart the
## strikes fall. Spacing under twice the radius is what makes them overlap into
## a continuous scalloped roof instead of a row of separate holes.
const LEVEL_TUNNEL_STRIKE_RADIUS_CELLS: float = 6.0
const LEVEL_TUNNEL_STRIKE_SPACING_CELLS: float = 7.0
## Extra reach on the occasional harder swing.
const LEVEL_TUNNEL_STRIKE_DEEP_BITE_CELLS: float = 2.5
## The rim-jagging pass. Strength is well under one so it breaks the arcs up
## rather than chewing the whole edge away, and the spacing is tight enough that
## no stretch of roof is left with a clean swept curve.
const LEVEL_TUNNEL_ROUGHEN_RADIUS_CELLS: float = 5.0
const LEVEL_TUNNEL_ROUGHEN_SPACING_CELLS: float = 4.0
const LEVEL_TUNNEL_ROUGHEN_STRENGTH: float = 0.45
## Depth of the band under the ceiling that is allowed to keep jagged rock. It
## has to clear the roughen radius, or a lump the pass left hanging survives
## into the space the cast walks through.
const LEVEL_TUNNEL_ROOF_JAG_BAND_CELLS: int = 7
## Tallest lump of rock standing on the tunnel floor, in cells. Three cells is
## twenty-four world units: still under knee height on the miner, so it reads as
## broken stone underfoot rather than a step the cast has to climb, but enough
## of it catches the light to be seen from across the room.
const LEVEL_TUNNEL_FLOOR_BUMP_CELLS: int = 3
## How much of the floor carries rock at all.
##
## Pushed above the midpoint so most columns have something on them. Centred, the
## waves spent half their range at zero and the ground came out mostly bare with
## the occasional lump, which reads as a smooth floor somebody dropped rocks on
## instead of a rocky floor.
const LEVEL_TUNNEL_FLOOR_ROCK_BIAS: float = 0.32
## Four gameplay strata are authored from foreground through backdrop. Keeping
## this count beside the depth derivation makes the stored masks agree with the
## renderer profile without coupling collision to either one.
const VISUAL_STRATUM_COUNT: int = 4
## Layer index one is the second visible stratum, which is the first plane
## behind the foreground rim.
const WALL_CEILING_DEPTH_LAYER_INDEX: int = 1
## A two-cell band is wide enough to survive mask smoothing and read at gameplay
## zoom, but narrow enough that it stays a rim instead of becoming the backdrop.
const WALL_CEILING_DEPTH_CELLS: int = 2

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

## The bite one scallop takes out of an end wall's face, and how far apart the
## bites fall. Spacing under twice the radius is what merges them into one worn
## surface instead of a row of separate scoops.
##
## Radius is the whole reason this is a brush pass and not authored cells. A cell
## edge can only ever run flat or straight up, so a wall built cell by cell reads
## as a staircase however finely the steps are cut. A carved disc leaves an arc,
## and overlapping arcs are what rock worn by water and pickaxes actually looks
## like.
const END_WALL_SCALLOP_RADIUS_CELLS: float = 3.5
const END_WALL_SCALLOP_SPACING_CELLS: float = 3.0
## Extra reach on the occasional deeper bite, and how often one lands.
const END_WALL_SCALLOP_DEEP_BITE_CELLS: float = 2.0
const END_WALL_SCALLOP_DEEP_BITE_INTERVAL: int = 3
## How far a bite wanders off the face it is eating, so the scallops vary in
## depth instead of arriving as a neat row of identical scoops.
const END_WALL_SCALLOP_WANDER_CELLS: float = 1.6
## Gap kept between the lowest bite and the floor row, in cells. Bites are held
## clear of the floor entirely rather than trimmed afterward: a disc that reaches
## the ground opens the very row the miner has to land on, and on a room authored
## without guarded floor rows nothing would put it back.
const END_WALL_SCALLOP_FLOOR_CLEARANCE_CELLS: float = 0.5


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
	apply_visual_depth_masks(sculpt)


## Cuts the whole room as one level tunnel running off both edges, with a flat
## floor the cast stands on end to end.
##
## This is the shape a cutscene room wants. A procedural chamber bulges in the
## middle and pinches at the sides, which puts the cast on a curved ledge and
## leaves the miner standing in a dip with rock at his shoulders; a designer
## then fights the brush to flatten it back. Cutting the tunnel outright means
## the authored work starts from a stage rather than from a cave.
##
## The roof waves gently so the tunnel still reads as worn rather than bored,
## but the floor is exactly the room's floor row across every column: that is
## what makes the miner land at the same height wherever he breaks through, and
## what stops a ledge catching him short of the room.
static func carve_level_tunnel(
	sculpt: CutsceneTerrainSculpt,
	height_cells: int = LEVEL_TUNNEL_HEIGHT_CELLS
) -> void:
	if sculpt == null:
		return
	var floor_row := sculpt.get_floor_local_row()
	if floor_row <= 0 or floor_row >= sculpt.grid_size.y:
		return
	# Solid first. A tunnel is the room's whole shape, not an edit on top of
	# whatever was cut before, so anything previously carved outside it has to
	# close or the old chamber's pockets survive as holes in the new walls.
	sculpt.begin_edit()
	sculpt.fill_all(true)
	var clear_height := maxi(height_cells, 4)
	for local_x in range(sculpt.grid_size.x):
		# Open upward from the row directly above the floor. The floor row and
		# the guarded rows under it are never touched, so the ground the cast
		# stands on is the same row in every column.
		var highest_open_row := maxi(floor_row - clear_height, 0)
		for local_y in range(highest_open_row, floor_row):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)

	# The ceiling is bitten out by overlapping strikes rather than left as the
	# straight edge of that rectangle. A cutscene room is a tunnel the miner dug
	# to get here, and a flat roof is the one detail that says it was not: the
	# scallops are the shape a swung pickaxe leaves, so the outline the renderer
	# draws along the rock rim reads as digging all the way across.
	var brush := CutsceneSculptBrush.new()
	brush.falloff = 0.25
	var roof_row := float(maxi(floor_row - clear_height, 0))
	var strike_x := -LEVEL_TUNNEL_STRIKE_RADIUS_CELLS
	var strike_index := 0
	while strike_x <= float(sculpt.grid_size.x) + LEVEL_TUNNEL_STRIKE_RADIUS_CELLS:
		var strike_progress := (
			strike_x / maxf(float(sculpt.grid_size.x - 1), 1.0)
		)
		# A wave under the strikes keeps the ceiling from settling at one
		# height, so the tunnel rises and falls the way a dug one does.
		var roof_wave := LEVEL_TUNNEL_ROOF_WAVE_CELLS * 0.5 * (
			1.0 - cos(strike_progress * TAU * LEVEL_TUNNEL_ROOF_WAVE_COUNT)
		)
		# Every third strike bites deeper, so the scallops read as a person
		# swinging rather than as a machine with one stroke length.
		var deep_bite := (
			LEVEL_TUNNEL_STRIKE_DEEP_BITE_CELLS
			if strike_index % 3 == 0
			else 0.0
		)
		brush.radius_cells = LEVEL_TUNNEL_STRIKE_RADIUS_CELLS + deep_bite
		brush.carve(sculpt, Vector2(strike_x, roof_row - roof_wave))
		strike_x += LEVEL_TUNNEL_STRIKE_SPACING_CELLS
		strike_index += 1

	# One roughen pass along the rim. Roughen flips only boundary cells, so this
	# breaks the arcs into jagged rock without opening a hole through the roof,
	# and the guarded floor rows are unreachable by it either way.
	brush.radius_cells = LEVEL_TUNNEL_ROUGHEN_RADIUS_CELLS
	brush.strength = LEVEL_TUNNEL_ROUGHEN_STRENGTH
	brush.falloff = 0.6
	var roughen_x := 0.0
	while roughen_x <= float(sculpt.grid_size.x):
		var roughen_progress := (
			roughen_x / maxf(float(sculpt.grid_size.x - 1), 1.0)
		)
		var roughen_wave := LEVEL_TUNNEL_ROOF_WAVE_CELLS * 0.5 * (
			1.0 - cos(roughen_progress * TAU * LEVEL_TUNNEL_ROOF_WAVE_COUNT)
		)
		brush.seed_value = int(roughen_x)
		brush.roughen(sculpt, Vector2(roughen_x, roof_row - roughen_wave))
		roughen_x += LEVEL_TUNNEL_ROUGHEN_SPACING_CELLS

	# Drop each column clear from its own ceiling to the floor. Both passes above
	# leave rock hanging under the opening they cut: roughen flips cells inward,
	# and a scallop can arch over a gap. Either way the column reads as ceiling,
	# then air, then rock again — and the miner falling down it lands on that
	# rock a few cells under the roof instead of on the floor with the cast.
	#
	# Opening from the topmost hole downward is what keeps the ceiling jagged
	# while making the fall safe: the height the rock starts at still varies
	# column by column, which is the whole silhouette, but nothing hangs beneath
	# it any more.
	for local_x in range(sculpt.grid_size.x):
		var ceiling_row := -1
		for local_y in range(0, floor_row):
			if not sculpt.is_solid_local(Vector2i(local_x, local_y)):
				ceiling_row = local_y
				break
		if ceiling_row < 0:
			continue
		for local_y in range(ceiling_row, floor_row):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)

	# Lay rock along the ground so the floor is a cave floor rather than a ruled
	# line. The bumps are low and gently varied, because this is the surface the
	# cast walks along: tall enough to catch the light and read as stone, short
	# enough that standing on one is standing on the floor.
	#
	# Deterministic from the column, not random, so recutting a room twice gives
	# the same ground and a designer's memory of a scene stays true.
	for local_x in range(sculpt.grid_size.x):
		var bump := _get_floor_bump_height(local_x)
		for local_y in range(floor_row - bump, floor_row):
			if local_y >= 0:
				sculpt.set_solid_local(Vector2i(local_x, local_y), true)
	sculpt.end_edit()
	apply_visual_depth_masks(sculpt)


## Returns how many cells of rock stand on the floor at one column.
##
## Three waves of unrelated lengths summed, so the ground neither repeats on a
## short cycle nor drifts into one long ramp, and the result is clamped to the
## authored maximum. A column is stone or it is not; there is no half cell.
##
## The frequencies deliberately share no whole-number ratio. An earlier pair at
## 0.21 and 0.63 was exactly three to one, which put an identical lump every
## thirty columns and read as tiling rather than as rock.
static func _get_floor_bump_height(local_x: int) -> int:
	var column := float(local_x)
	var coarse := sin(column * 0.187)
	var fine := sin(column * 0.523 + 1.7)
	var drift := sin(column * 0.079 + 0.4)
	var combined := (coarse + fine * 0.55 + drift * 0.7) / 2.25
	var height := roundi(
		(combined * 0.5 + 0.5 + LEVEL_TUNNEL_FLOOR_ROCK_BIAS)
		* float(LEVEL_TUNNEL_FLOOR_BUMP_CELLS)
	)
	return clampi(height, 0, LEVEL_TUNNEL_FLOOR_BUMP_CELLS)


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
	apply_visual_depth_masks(sculpt)


## Closes one end of a room with broken rock climbing from the floor to the
## ceiling, and fills everything past it with untouched stone.
##
## `foot_local_x` is the column the climb starts from, standing on the floor.
## `face_local_x` is the column it tops out at, past which the room is solid.
## Either order works: a face left of the foot closes the room's left end, a face
## right of it closes the right end. Nothing here is specific to one encounter -
## the walls the cutscenes need are this same cut mirrored.
##
## The wall closes from the grid's top edge rather than from the tunnel ceiling.
## The ceiling waves, so filling only underneath it leaves a slot open above the
## top of the climb, which reads as a crawlspace nobody authored.
##
## The teeth are cut rather than roughened. Roughen flips single boundary cells,
## and a single cell is the finest thing the drawn mask can carry, so it jags the
## rim into aliasing instead of rock. Authored runs stay wide enough to read.
static func carve_jagged_end_wall(
	sculpt: CutsceneTerrainSculpt,
	foot_local_x: int,
	face_local_x: int
) -> void:
	if sculpt == null or foot_local_x == face_local_x:
		return
	var floor_row := sculpt.get_floor_local_row()
	if floor_row <= 0 or floor_row >= sculpt.grid_size.y:
		return
	var direction := signi(face_local_x - foot_local_x)
	var ceiling_row := _find_open_row_below_top(sculpt, face_local_x, floor_row)

	# The face is resolved one ROW at a time, which is the whole trick.
	#
	# Walking columns and choosing a height for each is what builds a staircase:
	# the edge can then only run flat or straight up, and no amount of finer teeth
	# changes that. Walking rows and choosing how far in the rock reaches gives a
	# near-vertical wall whose edge wanders, and the mask's sub-cell interpolation
	# carries that wander as a curve.
	var climb_rows := float(maxi(floor_row - ceiling_row, 1))
	sculpt.begin_edit()
	for local_y in range(0, floor_row):
		var height_progress := clampf(
			float(floor_row - local_y) / climb_rows,
			0.0,
			1.0
		)
		# The face leans back as it rises, so the wall overhangs its own foot the
		# way the drawing does, rather than standing up like a slab.
		var lean := float(absi(face_local_x - foot_local_x)) * height_progress
		var boundary_x := (
			float(foot_local_x)
			+ float(direction) * (lean + _get_end_wall_face_wobble(local_y))
		)
		var solid_first_x := 0 if direction < 0 else int(ceilf(boundary_x))
		var solid_last_x := (
			int(floorf(boundary_x))
			if direction < 0
			else sculpt.grid_size.x - 1
		)
		for local_x in range(maxi(solid_first_x, 0), solid_last_x + 1):
			sculpt.set_solid_local(Vector2i(local_x, local_y), true)
	sculpt.end_edit()

	# One pass of overlapping bites along the finished face. The wandering edge
	# already reads as rock; this is what stops it reading as one continuous
	# surface, by taking scoops out of it at uneven depths.
	var brush := CutsceneSculptBrush.new()
	brush.falloff = 0.3
	var lowest_bite_row := (
		float(floor_row)
		- END_WALL_SCALLOP_RADIUS_CELLS
		- END_WALL_SCALLOP_FLOOR_CLEARANCE_CELLS
	)
	sculpt.begin_edit()
	var bite_row := lowest_bite_row
	var bite_index := 0
	while bite_row > float(ceiling_row):
		var height_progress := clampf(
			(float(floor_row) - bite_row) / climb_rows,
			0.0,
			1.0
		)
		var lean := float(absi(face_local_x - foot_local_x)) * height_progress
		var deep_bite := (
			END_WALL_SCALLOP_DEEP_BITE_CELLS
			if bite_index % END_WALL_SCALLOP_DEEP_BITE_INTERVAL == 0
			else 0.0
		)
		brush.radius_cells = END_WALL_SCALLOP_RADIUS_CELLS + deep_bite
		# Centred a radius into the open air, so the disc takes a crescent off the
		# face instead of boring a tunnel back through the rock behind it.
		brush.carve(sculpt, Vector2(
			float(foot_local_x)
			+ float(direction) * (
				lean
				- END_WALL_SCALLOP_RADIUS_CELLS
				+ sin(float(bite_index) * 1.9 + 0.6)
					* END_WALL_SCALLOP_WANDER_CELLS
			),
			bite_row
		))
		bite_row -= END_WALL_SCALLOP_SPACING_CELLS
		bite_index += 1
	sculpt.end_edit()
	apply_visual_depth_masks(sculpt)


## Returns how far one row's edge wanders off the leaning face, in cells.
##
## Three frequencies sharing no whole-number ratio, so the wall neither repeats on
## a short cycle nor drifts into one straight bevel, and deterministic from the
## row so recutting a room gives back the wall a designer remembers.
static func _get_end_wall_face_wobble(local_y: int) -> float:
	var row := float(local_y)
	var coarse := sin(row * 0.31)
	var medium := sin(row * 0.73 + 2.1)
	var fine := sin(row * 1.61 + 0.4)
	return (coarse + medium * 0.6 + fine * 0.35) * END_WALL_SCALLOP_WANDER_CELLS


## Returns the first open row under the rock at one column, which is where the
## room's ceiling actually sits after the tunnel cut waved and scalloped it.
static func _find_open_row_below_top(
	sculpt: CutsceneTerrainSculpt,
	local_x: int,
	floor_row: int
) -> int:
	for local_y in range(0, floor_row):
		if not sculpt.is_solid_local(Vector2i(local_x, local_y)):
			return local_y
	return maxi(floor_row - LEVEL_TUNNEL_HEIGHT_CELLS, 0)


## Derives the room's visible depth without moving one collision cell.
##
## Layer zero follows the logical silhouette and remains the foreground rim.
## Layer one grows inward only from rock above or beside open air, so the walls
## and ceiling reveal a narrow second-stratum face while the floor remains the
## surface the miner actually lands on. Exactly one of layers two and three is
## then closed into the backdrop selected by the room; the other keeps the
## logical opening so it cannot hide the selected colour.
static func apply_visual_depth_masks(sculpt: CutsceneTerrainSculpt) -> void:
	if sculpt == null:
		return
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
			if logical_solid:
				continue

			var draws_wall_or_ceiling_depth := false
			for offset_y in range(
				-WALL_CEILING_DEPTH_CELLS,
				1
			):
				for offset_x in range(
					-WALL_CEILING_DEPTH_CELLS,
					WALL_CEILING_DEPTH_CELLS + 1
				):
					if offset_x == 0 and offset_y == 0:
						continue
					if (
						absi(offset_x) + absi(offset_y)
						> WALL_CEILING_DEPTH_CELLS
					):
						continue
					if sculpt.is_solid_local(
						local_cell + Vector2i(offset_x, offset_y)
					):
						draws_wall_or_ceiling_depth = true
						break
				if draws_wall_or_ceiling_depth:
					break
			if draws_wall_or_ceiling_depth:
				sculpt.set_layer_solid_local(
					WALL_CEILING_DEPTH_LAYER_INDEX,
					local_cell,
					true
				)
			sculpt.set_layer_solid_local(
				sculpt.background_layer_index,
				local_cell,
				true
			)
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
