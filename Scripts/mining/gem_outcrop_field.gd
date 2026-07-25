class_name GemOutcropField
extends Node2D

## How it works:
## - Watches terrain damage and, rarely, leaves one drawn crystal jutting out of
##   a stratum the hit just exposed, so breaking ground occasionally uncovers
##   something worth looking at.
## - Which stratum a crystal belongs to decides its colour, its size and which
##   depth it draws at, so a shallow break and a deep one yield different finds.
## - Cutscenes call place_gem() to stand an authored crystal wherever they frame.
## - Records stay in terrain space and are saved; scrolling only redraws the
##   nearby chunks, so returning to an old depth finds the same crystal there.
## The invariant is that placing a gem never turns it into screen-space state:
## mining, review scrolling, scene reloads and render culling cannot move it.

## Draws the crystals belonging to one stratum. Each shelf carries that
## stratum's own z_index, so a crystal uncovered deep in the tunnel is covered
## by the layers still standing in front of it instead of floating over them.
## Godot draws equal-z siblings in tree order, and the field sits after the
## terrain renderer, so matching a layer's z puts a crystal just in front of it.
class GemShelf:
	extends Node2D

	var field: GemOutcropField
	## At most maximum_gems_per_chunk entries are retained across all shelves in
	## one chunk. Drawing only visits the visible chunk range, so a 100,000-row
	## run does not add per-frame work as its sparse record set grows.
	var gems_by_chunk: Dictionary[int, Array] = {}

	func _draw() -> void:
		field.draw_shelf(self)


## One placed crystal. Terrain-space so it survives streaming and view movement.
class GemOutcrop:
	var terrain_position: Vector2
	## The original rock cell remains useful for palette selection and saving,
	## but it is not an attachment: later mining cannot move or delete the gem.
	var anchor_cell: Vector2i
	var rotation: float
	var world_height: float
	var variant_index: int
	var flip_x: bool
	## Runs 0 to 1 once, driving the crystal's push up out of the rock.
	var emergence: float = 0.0


@export_category("References")
@export var terrain_manager: TerrainManager
@export var terrain_profile: TerrainLayerProfile
## Optional. The drawn opening is wider than the cells a hit actually removed,
## so a crystal seated on the logical floor hangs above the rock the player can
## see. With the renderer supplied, floor placements snap to the same drawn rim
## the miner lands on; without it they fall back to the logical cell.
@export var terrain_renderer: TerrainLayerRenderer

@export_category("Artwork")
## Horizontal atlas of crystal colours, each frame drawn standing on its base.
@export var gem_texture: Texture2D
@export_range(1, 16, 1) var gem_variant_count: int = 5

@export_category("Rarity")
## Chance that one qualifying hit leaves a crystal behind. Deliberately low:
## a find stops being a find once the player expects one.
@export_range(0.0, 1.0, 0.01) var spawn_chance: float = 0.07
## Small chips expose nothing; a hit must open at least this many cells.
@export_range(1, 128, 1) var minimum_cells_removed: int = 14

@export_category("Appearance")
@export_range(4.0, 160.0, 1.0) var minimum_world_height: float = 30.0
@export_range(4.0, 160.0, 1.0) var maximum_world_height: float = 52.0
## Shrinks each deeper stratum's crystals, so a find further back sits back.
@export_range(0.4, 1.0, 0.01) var depth_size_falloff: float = 0.9
## How far a floor placement may be moved down to meet the drawn rim. The drawn
## opening is grown past the removed cells by the profile's core padding plus one
## rim width per layer behind, so this needs to cover that much or the crystal
## never reaches the rock meant to bury it. Past it the renderer answered with an
## unrelated lip, so the logical floor is kept.
@export_range(0.0, 256.0, 1.0) var maximum_floor_snap_world_px: float = 72.0
## Chance one crystal takes a neighbouring colour instead of its stratum's own,
## so a stratum reads as a signature rather than a rule.
@export_range(0.0, 1.0, 0.05) var variant_drift_chance: float = 0.35
## How much of a crystal is sunk behind the stratum covering it. Zero leaves it
## fully exposed and sitting on the rock instead of embedded in it.
@export_range(0.0, 0.8, 0.05) var buried_fraction: float = 0.22
## Floor cells one hit may ask the renderer to seat a crystal against before it
## gives up. Each attempt is one mask walk, so this bounds the per-hit cost.
@export_range(1, 24, 1) var floor_seating_attempts: int = 8
## Multiplied into a crystal, reached at the deepest stratum, so a find further
## back sits in the same muddy shadow as the rock around it rather than glowing
## out of the tunnel at full saturation.
@export var depth_shade_color: Color = Color(0.62, 0.55, 0.5)
## How far a crystal may lean off the rock face it grew out of.
@export_range(0.0, 80.0, 1.0) var maximum_tilt_degrees: float = 26.0
## How long one crystal takes to push out of the rock after a hit.
@export_range(0.05, 2.0, 0.05) var emergence_duration: float = 0.3
## Rows of descent before the palette walks on to the next colours. Stratum and
## depth together are what put every drawn colour into play across one run
## instead of showing the same two near the surface forever.
@export_range(50, 20_000, 50) var depth_variant_period_rows: int = 900

@export_category("Performance")
## Bounds both saved density and the number a viewport can draw. Four gems per
## 64-row chunk means the default 100,000-row map retains at most about 6,300
## lightweight records, while a 648px web viewport normally visits 2-3 chunks.
@export_range(1, 32, 1) var maximum_gems_per_chunk: int = 4
## Keeps crystals just outside the viewport ready during smooth camera motion.
@export_range(0.0, 512.0, 8.0) var draw_margin_screen_px: float = 96.0

var _shelves: Array[GemShelf] = []
var _random := RandomNumberGenerator.new()
var _gem_count_by_chunk: Dictionary[int, int] = {}
var _gem_count: int = 0
var _first_visible_chunk: int = 0
var _last_visible_chunk: int = 0
var _save_game: SaveGame


## Builds one drawing shelf per stratum a hit can expose.
func _ready() -> void:
	if terrain_manager == null or terrain_profile == null:
		push_error(
			"GemOutcropField requires terrain_manager and terrain_profile."
		)
		return
	_random.randomize()
	for layer_index in range(_get_exposed_layer_count()):
		var shelf := GemShelf.new()
		shelf.name = "GemShelf_%d" % layer_index
		shelf.field = self
		shelf.z_index = terrain_profile.get_layer_z_index(layer_index)
		add_child(shelf)
		_shelves.append(shelf)
	_restore_saved_gems()
	_refresh_visible_chunk_range(terrain_manager.get_view_position())
	set_process(false)


## Supplies persistence after the composition root resolves the active save.
func set_save_game(save_game: SaveGame) -> void:
	_save_game = save_game
	if is_node_ready():
		_restore_saved_gems()


## Rolls for a crystal on newly opened ground.
func _on_terrain_damaged(
	destroyed_cells: Array[Vector2i],
	_horizontal_direction: int,
	impact_origin_cell: Vector2i
) -> void:
	if (
		gem_texture == null
		or _shelves.is_empty()
		or destroyed_cells.size() < minimum_cells_removed
		or _random.randf() >= spawn_chance
	):
		return
	_place_in_exposed_stratum(destroyed_cells, impact_origin_cell)


## Stands a crystal at an authored terrain position for a cutscene to frame.
## The caller owns the placement, so this skips the support test the mining roll
## uses; a cutscene draws its own ground. Passing a stratum picks which depth it
## is covered at, and a colour and height of zero take the field's own choice.
func place_gem(
	terrain_position: Vector2,
	surface_normal: Vector2 = Vector2.UP,
	layer_index: int = 0,
	variant_index: int = -1,
	world_height: float = 0.0
) -> void:
	if gem_texture == null or _shelves.is_empty():
		return
	var cell_size := float(terrain_manager.config.terrain_cell_world_size)
	_add_gem(
		clampi(layer_index, 0, _shelves.size() - 1),
		terrain_position,
		Vector2i(
			floori(terrain_position.x / cell_size),
			floori(terrain_position.y / cell_size)
		),
		surface_normal,
		variant_index,
		world_height
	)


## Clears every placed crystal, so a restarted run does not inherit the last.
func clear_gems() -> void:
	var had_saved_gems := (
		_save_game != null
		and not _save_game.gem_outcrops.is_empty()
	)
	for shelf in _shelves:
		shelf.gems_by_chunk.clear()
		shelf.queue_redraw()
	_gem_count_by_chunk.clear()
	_gem_count = 0
	if had_saved_gems:
		_persist_gems()
	set_process(false)


## Advances each crystal's push out of the rock and stops once all have landed.
func _process(delta: float) -> void:
	var still_emerging := false
	for shelf in _shelves:
		var shelf_emerging := false
		for chunk_index in range(
			_first_visible_chunk,
			_last_visible_chunk + 1
		):
			if not shelf.gems_by_chunk.has(chunk_index):
				continue
			var chunk_gems: Array = shelf.gems_by_chunk[chunk_index]
			for gem: GemOutcrop in chunk_gems:
				if gem.emergence >= 1.0:
					continue
				gem.emergence = minf(
					gem.emergence
						+ delta / maxf(emergence_duration, 0.01),
					1.0
				)
				shelf_emerging = true
		if shelf_emerging:
			shelf.queue_redraw()
			still_emerging = true
	if not still_emerging:
		set_process(false)


## Draws one shelf's crystals standing on their bases. Called by the shelf so
## every stratum keeps its own z while the drawing itself stays in one place.
func draw_shelf(shelf: GemShelf) -> void:
	if gem_texture == null:
		return
	var frame_count := maxi(gem_variant_count, 1)
	var frame_size := Vector2(
		float(gem_texture.get_width()) / float(frame_count),
		float(gem_texture.get_height())
	)
	# One shade for the whole shelf, because a shelf is exactly one stratum's
	# worth of distance back into the tunnel.
	var depth_shade := Color.WHITE.lerp(
		depth_shade_color,
		float(_shelves.find(shelf))
		/ maxf(float(_shelves.size() - 1), 1.0)
	)
	var viewport_size := get_viewport_rect().size
	for chunk_index in range(
		_first_visible_chunk,
		_last_visible_chunk + 1
	):
		if not shelf.gems_by_chunk.has(chunk_index):
			continue
		var chunk_gems: Array = shelf.gems_by_chunk[chunk_index]
		for gem: GemOutcrop in chunk_gems:
			var screen_position := terrain_manager.terrain_to_screen_position(
				gem.terrain_position
			)
			if (
				screen_position.x < -draw_margin_screen_px
				or screen_position.x
					> viewport_size.x + draw_margin_screen_px
				or screen_position.y < -draw_margin_screen_px
				or screen_position.y
					> viewport_size.y + draw_margin_screen_px
			):
				continue
			var height := gem.world_height
			var width := height * frame_size.x / frame_size.y
			# The crystal keeps its drawn proportions and slides out of the rock
			# instead of growing in place, so the covering stratum does the
			# reveal. The record itself never leaves terrain space.
			var emerged := ease(gem.emergence, 0.4)
			emerged += sin(PI * gem.emergence) * 0.07
			var buried_slide := (1.0 - emerged) * height
			shelf.draw_set_transform(
				screen_position,
				gem.rotation,
				Vector2(-1.0 if gem.flip_x else 1.0, 1.0)
			)
			# Local down is into the rock once the transform has aligned the
			# crystal to its original face.
			shelf.draw_texture_rect_region(
				gem_texture,
				Rect2(
					Vector2(-width * 0.5, -height + buried_slide),
					Vector2(width, height)
				),
				Rect2(
					Vector2(
						frame_size.x * float(gem.variant_index),
						0.0
					),
					frame_size
				),
				depth_shade
			)
	shelf.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Grows a crystal out of one of the strata this hit just cut through.
func _place_in_exposed_stratum(
	destroyed_cells: Array[Vector2i],
	impact_origin_cell: Vector2i
) -> void:
	# A wider break cuts further back, so it can uncover a deeper stratum. The
	# roll still reaches the shallow ones, or every large hit would look alike.
	var deepest_exposed := clampi(
		destroyed_cells.size() / maxi(minimum_cells_removed, 1) - 1,
		0,
		_shelves.size() - 1
	)
	# The foreground stratum is skipped where a deeper one exists, because a
	# crystal on it has nothing drawn in front to bury its base behind, and a
	# fully exposed crystal reads as sitting on the rock rather than in it.
	var shallowest_usable := 1 if _shelves.size() > 1 else 0
	var layer_index := _random.randi_range(
		shallowest_usable,
		maxi(deepest_exposed, shallowest_usable)
	)
	# Only floors are used. The drawing is posed standing on its base, and the
	# renderer can only answer where a drawn floor lip is, so a wall placement
	# would have to be both rotated onto its side and left unseated.
	#
	# Seating is what decides whether a candidate is usable, and only the
	# renderer can answer that, so candidates are tried in turn rather than
	# committing to the first floor cell found. The attempt cap bounds the mask
	# walks one hit can trigger.
	var cell_size := float(terrain_manager.config.terrain_cell_world_size)
	var covering_layer_index := maxi(layer_index - 1, 0)
	var impact_center := (
		Vector2(impact_origin_cell) + Vector2(0.5, 0.5)
	) * cell_size
	# Only the hit's own bottom row is considered. A cell higher up also has a
	# drawn floor beneath it, but that floor is the bottom of the whole opening,
	# far enough below to be rejected as an unrelated rim; the bottom row is the
	# only place the logical floor and the drawn one are the same lip.
	var floor_cells := _get_floor_row_cells(destroyed_cells)
	if floor_cells.is_empty():
		return
	# Walking from a random start spreads placements along the floor instead of
	# always taking the first cell the dig happened to record.
	var start_index := _random.randi_range(0, floor_cells.size() - 1)
	var attempts_left := floor_seating_attempts
	for offset in range(floor_cells.size()):
		if attempts_left <= 0:
			return
		var opened_cell := floor_cells[
			(start_index + offset) % floor_cells.size()
		]
		attempts_left -= 1
		# Deeper strata are exposed nearer the middle of the opening, so the
		# crystal steps inward to sit on the band it belongs to.
		var rim_position := (
			(Vector2(opened_cell) + Vector2(0.5, 0.5)) * cell_size
			- Vector2.UP * cell_size * 0.5
		).move_toward(
			impact_center,
			float(terrain_profile.rim_width * layer_index)
		)
		# Seat the base on the rim of the stratum in FRONT of this one, not this
		# one's own. That rim is where the rock covering the crystal begins, so
		# it is the line the crystal has to break through to be seen at all.
		var seated_position := _get_drawn_floor_position(
			rim_position,
			opened_cell.y,
			covering_layer_index
		)
		if is_nan(seated_position.y):
			continue
		var world_height := (
			_random.randf_range(
				minf(minimum_world_height, maximum_world_height),
				maxf(minimum_world_height, maximum_world_height)
			) * pow(depth_size_falloff, float(layer_index))
		)
		# Sink the base into the rock. This shelf draws behind the covering
		# stratum, so the sunk part is hidden and only the tip juts out.
		_add_gem(
			layer_index,
			seated_position + Vector2.DOWN * world_height * buried_fraction,
			opened_cell + Vector2i.DOWN,
			Vector2.UP,
			-1,
			world_height
		)
		return


## Returns the cells on the bottom row this hit opened that still have solid rock
## beneath them, which is the floor the opening actually left behind.
func _get_floor_row_cells(
	destroyed_cells: Array[Vector2i]
) -> Array[Vector2i]:
	# TerrainManager emits tunnel cells in row-major order. Walk back only over
	# the final row so a rare gem roll on an 8,900-cell stacked hit does not
	# rescan the entire opening twice inside the hit frame.
	var bottom_row: int = destroyed_cells.back().y
	var floor_start_index := destroyed_cells.size() - 1
	while (
		floor_start_index > 0
		and destroyed_cells[floor_start_index - 1].y == bottom_row
	):
		floor_start_index -= 1
	var floor_cells: Array[Vector2i] = []
	for cell_index in range(floor_start_index, destroyed_cells.size()):
		var cell := destroyed_cells[cell_index]
		if (
			terrain_manager.is_solid_cell(cell + Vector2i.DOWN)
		):
			floor_cells.append(cell)
	return floor_cells


## Returns the position seated on the stratum's drawn rim rather than on the
## logical cell floor, which sits higher because the drawn opening is grown past
## the cells a hit removed. Returns a NAN y when no rim of this stratum is within
## reach, which is the caller's signal to drop the placement entirely.
func _get_drawn_floor_position(
	terrain_position: Vector2,
	landing_world_row: int,
	layer_index: int
) -> Vector2:
	if terrain_renderer == null:
		return terrain_position
	var screen_position := terrain_manager.terrain_to_screen_position(
		terrain_position
	)
	var drawn_floor_y: float = (
		terrain_renderer.get_layer_opening_floor_support_screen_y(
			screen_position.x,
			landing_world_row,
			layer_index
		)
	)
	# The query walks the mask for the nearest lip, so where this stratum has no
	# opening near the hit it can answer with an unrelated rim elsewhere in the
	# column. Two guards keep only the lip this crystal actually grew from: an
	# opening is always grown outward from the damage, never shrunk, so its floor
	# can only ever be at or below the logical one, and it can only be as far
	# below as that growth reaches.
	if (
		is_nan(drawn_floor_y)
		or drawn_floor_y < screen_position.y
		or drawn_floor_y - screen_position.y > maximum_floor_snap_world_px
	):
		return Vector2(terrain_position.x, NAN)
	return terrain_manager.screen_to_terrain_position(
		Vector2(screen_position.x, drawn_floor_y)
	)



## Records one crystal on its stratum's shelf and enforces the placement cap.
func _add_gem(
	layer_index: int,
	terrain_position: Vector2,
	anchor_cell: Vector2i,
	surface_normal: Vector2,
	variant_index: int,
	world_height: float
) -> void:
	var chunk_index := _terrain_position_to_chunk(terrain_position)
	if (
		_gem_count_by_chunk.get(chunk_index, 0)
		>= maximum_gems_per_chunk
	):
		return
	var gem := GemOutcrop.new()
	gem.terrain_position = terrain_position
	gem.anchor_cell = anchor_cell
	gem.variant_index = (
		_get_stratum_variant(layer_index, anchor_cell.y)
		if variant_index < 0
		else clampi(variant_index, 0, maxi(gem_variant_count, 1) - 1)
	)
	gem.world_height = (
		_random.randf_range(
			minf(minimum_world_height, maximum_world_height),
			maxf(minimum_world_height, maximum_world_height)
		) * pow(depth_size_falloff, float(layer_index))
		if world_height <= 0.0
		else world_height
	)
	gem.flip_x = _random.randf() < 0.5
	# The drawing already stands upright, so aligning it to the face it grew
	# from means rotating from straight up onto that normal.
	gem.rotation = (
		Vector2.UP.angle_to(surface_normal.normalized())
		+ deg_to_rad(
			_random.randf_range(
				-maximum_tilt_degrees,
				maximum_tilt_degrees
			)
		)
	)
	_append_gem(layer_index, chunk_index, gem)
	_persist_gems()
	for shelf in _shelves:
		shelf.queue_redraw()
	set_process(true)


## Returns the colour a stratum yields at one depth. Walking the palette with
## both stratum and depth is what brings every drawn crystal into a run rather
## than showing the same first colours near the surface forever.
func _get_stratum_variant(layer_index: int, terrain_row: int) -> int:
	var variant_count := maxi(gem_variant_count, 1)
	var depth_band := (
		maxi(terrain_row - terrain_manager.config.initial_surface_row, 0)
		/ maxi(depth_variant_period_rows, 1)
	)
	var variant := layer_index + depth_band
	# Without the drift a stratum yields exactly one colour until the run is deep
	# enough to advance the band, so the first minutes would only ever show two.
	if _random.randf() < variant_drift_chance:
		variant += (1 if _random.randf() < 0.5 else -1)
	return posmod(variant, variant_count)


## Returns how many strata an ordinary hit can expose. The deepest gameplay
## layer stays solid as the back wall, so nothing is ever uncovered in it.
func _get_exposed_layer_count() -> int:
	var gameplay_layers := terrain_profile.get_gameplay_layer_count()
	if terrain_profile.keep_back_layer_solid:
		gameplay_layers -= 1
	return maxi(gameplay_layers, 1)


## Redraws only the sparse chunk window surrounding the current camera.
func _on_view_position_changed(view_cell_position: Vector2) -> void:
	# A crystal discovered on the previous screen must not replay its entrance
	# when the player eventually scrolls back. Only the old visible chunks can
	# contain an animation that was interrupted by this camera move.
	for shelf in _shelves:
		for chunk_index in range(
			_first_visible_chunk,
			_last_visible_chunk + 1
		):
			if not shelf.gems_by_chunk.has(chunk_index):
				continue
			var chunk_gems: Array = shelf.gems_by_chunk[chunk_index]
			for gem: GemOutcrop in chunk_gems:
				gem.emergence = 1.0
	_refresh_visible_chunk_range(view_cell_position)
	for shelf in _shelves:
		shelf.queue_redraw()


## Converts a terrain-space y coordinate into the same chunk grid as terrain.
func _terrain_position_to_chunk(terrain_position: Vector2) -> int:
	var cell_size := float(terrain_manager.config.terrain_cell_world_size)
	var terrain_row := floori(terrain_position.y / cell_size)
	return floori(
		float(terrain_row)
		/ float(terrain_manager.config.chunk_height_cells)
	)


## Adds one record to its saved chunk without creating a node per gem.
func _append_gem(
	layer_index: int,
	chunk_index: int,
	gem: GemOutcrop
) -> void:
	var shelf := _shelves[layer_index]
	var chunk_gems: Array = shelf.gems_by_chunk.get(chunk_index, [])
	chunk_gems.append(gem)
	shelf.gems_by_chunk[chunk_index] = chunk_gems
	_gem_count_by_chunk[chunk_index] = (
		_gem_count_by_chunk.get(chunk_index, 0) + 1
	)
	_gem_count += 1


## Restores exact terrain-space records. Loaded gems are already emerged so a
## scene reload cannot replay their discovery animation.
func _restore_saved_gems() -> void:
	if _save_game == null:
		return
	for saved_gem: Dictionary in _save_game.gem_outcrops:
		var layer_index := clampi(
			int(saved_gem.get("layer_index", 0)),
			0,
			_shelves.size() - 1
		)
		var terrain_position: Vector2 = saved_gem.get(
			"terrain_position",
			Vector2.ZERO
		)
		var chunk_index := _terrain_position_to_chunk(terrain_position)
		if (
			_gem_count_by_chunk.get(chunk_index, 0)
			>= maximum_gems_per_chunk
		):
			continue
		var gem := GemOutcrop.new()
		gem.terrain_position = terrain_position
		gem.anchor_cell = saved_gem.get(
			"anchor_cell",
			Vector2i.ZERO
		)
		gem.rotation = float(saved_gem.get("rotation", 0.0))
		gem.world_height = maxf(
			float(saved_gem.get("world_height", minimum_world_height)),
			1.0
		)
		gem.variant_index = clampi(
			int(saved_gem.get("variant_index", 0)),
			0,
			maxi(gem_variant_count, 1) - 1
		)
		gem.flip_x = bool(saved_gem.get("flip_x", false))
		gem.emergence = 1.0
		_append_gem(layer_index, chunk_index, gem)
	for shelf in _shelves:
		shelf.queue_redraw()


## Serializes compact values only when a rare placement changes the map. Review
## scrolling never writes or rebuilds this complete list.
func _persist_gems() -> void:
	if _save_game == null:
		return
	var saved_gems: Array[Dictionary] = []
	saved_gems.resize(_gem_count)
	var saved_index := 0
	for layer_index in range(_shelves.size()):
		var shelf := _shelves[layer_index]
		for chunk_gems: Array in shelf.gems_by_chunk.values():
			for gem: GemOutcrop in chunk_gems:
				saved_gems[saved_index] = {
					"layer_index": layer_index,
					"terrain_position": gem.terrain_position,
					"anchor_cell": gem.anchor_cell,
					"rotation": gem.rotation,
					"world_height": gem.world_height,
					"variant_index": gem.variant_index,
					"flip_x": gem.flip_x,
				}
				saved_index += 1
	_save_game.gem_outcrops = saved_gems
	_save_game.write_savegame()


## Computes the bounded draw window without scanning stored gems.
func _refresh_visible_chunk_range(view_cell_position: Vector2) -> void:
	var config := terrain_manager.config
	var cell_size := float(config.terrain_cell_world_size)
	var chunk_height := float(config.chunk_height_cells)
	var viewport_height := get_viewport_rect().size.y
	var first_visible_row := (
		view_cell_position.y
		+ (-config.mining_face_screen_y - draw_margin_screen_px)
			/ cell_size
	)
	var last_visible_row := (
		view_cell_position.y
		+ (
			viewport_height
			- config.mining_face_screen_y
			+ draw_margin_screen_px
		) / cell_size
	)
	_first_visible_chunk = floori(first_visible_row / chunk_height)
	_last_visible_chunk = floori(last_visible_row / chunk_height)
