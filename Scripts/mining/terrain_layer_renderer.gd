@tool
class_name TerrainLayerRenderer
extends Node2D

## Streams layered terrain art and reveals organic openings at mining impacts.
## @tool lets authored encounter scenes preview the production terrain. Editor
## work is opt-in per instance via
## preview_in_editor, so opening the mining scene costs nothing. There is no
## second renderer and no redrawn approximation: the editor runs this code.
## Visual cutouts intentionally retain one colored backdrop over logical holes.
## Normal hits stop at orange; big hits may expose the solid brown back layer.
## Chamber antialiasing may differ by less than one logical cell at a side edge;
## layer one may sit up to the profile's authored reveal distance below a room's
## logical floor while layer two stays aligned to support. Neither mismatch
## affects collision. Press F3 to compare the logical opening.

class TerrainChunkVisual:
	var root: Node2D
	var mask_images: Array[Image] = []
	var mask_textures: Array[ImageTexture] = []
	var layer_sprites: Array[Sprite2D] = []


class HoleMaskData:
	var erase_mask: Image
	var fracture_source: Image
	var transparent_bounds: Rect2i
	var cache_id: int


class ImpactStamp:
	var center: Vector2
	var core_radius: float
	var damage_bounds: Rect2
	var narrow_path_points: PackedVector2Array
	var narrow_path_radius_scale: float = 1.0
	var narrow_path_two_layer_fraction: float = 0.5
	var use_big_hole: bool
	var flip_x: bool
	var flip_y: bool
	var rotation_quarters: int
	var size_variation: float = 1.0
	## Seeds this hit's per-stratum orientation and size jitter. Kept on the
	## stamp so a chunk streamed back in redraws the exact same rims.
	var variation_hash: int = 0

class ResizedStampImages:
	var erase_mask: Image
	var transparent_source: Image
	var fracture_source: Image


const LAYER_SHADER: Shader = preload(
	"res://Shaders/terrain_layer.gdshader"
)
const SOLID_MASK_COLOR := Color.WHITE
const EMPTY_MASK_COLOR := Color.TRANSPARENT
# A landing samples at most 64 rows upward and 64 rows back to the support lip
# (512 mask pixels total at the default profile). The query runs once per
# landing and never grows with run depth or hit count.
const MAX_SUPPORT_SCAN_ROWS: int = 64
# Landing refinement examines only the immediate authored rim after the normal
# bounded support scan; it never searches unrelated cracks deeper in the layer.
const FRACTURE_SUPPORT_SCAN_MASK_PIXELS: int = 8
const FRACTURE_SUPPORT_HALF_WIDTH_MASK_PIXELS: int = 2
const FRACTURE_SUPPORT_VALUE_THRESHOLD: float = 0.9
@export_category("References")
@export var terrain_manager: TerrainManager
@export var profile: TerrainLayerProfile

@export_category("Impact Reveal")
## Layer four remains covered until the active hit reaches this combo.
@export_range(1, 100, 1) var deepest_layer_combo_threshold: int = 7

@export_category("Web Performance")
## Limits reusable resized masks so repeated hit sizes avoid image allocations.
@export_range(0, 48, 1) var resized_stamp_cache_limit: int = 48
## Oversized combo openings are one-off and must not occupy the reusable cache.
@export_range(1, 1_048_576, 1) var resized_stamp_cache_max_pixels: int = 65_536

@export_category("Chamber Integration")
## Places overlapping organic openings across each encounter-room ceiling.
@export_range(0, 32, 1) var chamber_circle_count: int = 8
@export_range(1, 16, 1) var chamber_circle_min_radius_cells: int = 5
@export_range(1, 16, 1) var chamber_circle_max_radius_cells: int = 8
@export_range(0.0, 8.0, 0.5) var chamber_circle_jitter_cells: float = 3.0

@export_category("Editor Preview")
## Streams terrain inside the editor for this instance only. The mining scene
## leaves it off so opening it stays instant; cutscene previews turn it on.
@export var preview_in_editor: bool = false

@export_category("Debug")
## Toggles the logical opening overlay without affecting terrain presentation.
@export var logical_overlay_key: Key = KEY_F3
@export var logical_overlay_color := Color(0.2, 1.0, 0.35, 0.45)

var _active_chunks: Dictionary[int, TerrainChunkVisual] = {}
# Historical stamps are retained so review mode can rebuild old terrain.
# Growth is bounded by the configured run and accepted hit count; only the
# viewport-sized _active_chunks set owns Image and ImageTexture allocations.
var _impact_stamps_by_chunk: Dictionary = {}
var _chamber_stamps_by_chunk: Dictionary = {}
var _small_mask_data: Array[HoleMaskData] = []
var _big_mask_data: Array[HoleMaskData] = []
# Stores at most resized_stamp_cache_limit transformed hole-and-line pairs,
# each no larger than resized_stamp_cache_max_pixels; least-recently-used
# entries are pruned before another pair is inserted.
var _resized_stamp_cache: Dictionary[Vector4i, ResizedStampImages] = {}
var _resized_stamp_cache_order: Array[Vector4i] = []
# Oversized pairs live only for one synchronous impact or chunk rebuild. The
# list is bounded by that operation's stamp count times its gameplay layers.
var _temporary_stamp_cache_keys: Array[Vector4i] = []
var _current_view_x: float
var _current_view_y: float
var _loaded_first_chunk: int = -1
var _loaded_last_chunk: int = -1
var _latest_foreground_opening_rect := Rect2()
var _latest_impact_stamp: ImpactStamp
var _latest_support_world_position := Vector2(NAN, NAN)
var _show_logical_overlay: bool = false
# One entry per stratum, all 1.0 unless the editor is isolating a layer.
var _layer_display_opacity: PackedFloat32Array = PackedFloat32Array()
var _active_impact_combo: int = 0


## Connects terrain events and loads the initial visible strata.
func _ready() -> void:
	if Engine.is_editor_hint():
		# Streaming, input, and signal routes belong to a running game. An
		# editor instance only draws, and only when its scene asked it to.
		set_process_unhandled_key_input(false)
		if not preview_in_editor:
			return
		if terrain_manager == null or profile == null:
			return
		# The damage routes stay connected: breaking terrain while authoring
		# has to travel the same signal path a real hit does, or the preview
		# would only be showing a drawing of terrain rather than terrain.
		_connect_once(
			terrain_manager.terrain_damaged,
			_on_terrain_damaged
		)
		_connect_once(
			terrain_manager.terrain_paths_damaged,
			_on_terrain_paths_damaged
		)
		_prepare_hole_masks()
		_prepare_chamber_transition_stamps()
		_on_view_position_changed(terrain_manager.get_view_position())
		return
	if terrain_manager == null or profile == null:
		push_error(
			"TerrainLayerRenderer requires terrain_manager and profile."
		)
		return
	var layer_count: int = profile.get_layer_count()
	if (
		profile.layer_dirt_detail_scales_px.size() != layer_count
		or profile.layer_dirt_detail_colors.size() != layer_count
		or profile.layer_dirt_variance_strengths.size() != layer_count
		or profile.layer_rock_densities.size() != layer_count
		or profile.layer_rock_detail_strengths.size() != layer_count
		or profile.layer_rock_body_colors.size() != layer_count
		or profile.layer_rock_outline_colors.size() != layer_count
	):
		push_error(
			"TerrainLayerRenderer texture arrays must match Layer Tints."
		)
		return
	_connect_once(
		terrain_manager.terrain_damaged,
		_on_terrain_damaged
	)
	_connect_once(
		terrain_manager.terrain_paths_damaged,
		_on_terrain_paths_damaged
	)
	_connect_once(
		get_viewport().size_changed,
		_on_viewport_size_changed
	)
	_prepare_hole_masks()
	_prepare_chamber_transition_stamps()
	_on_view_position_changed(terrain_manager.get_view_position())


## Captures the combo used by synchronous damage stamps for one resolved hit.
func _on_dig_presentation_started(combo: int) -> void:
	_active_impact_combo = maxi(combo, 0)


## Saves and applies one organic opening for newly destroyed terrain.
func _on_terrain_damaged(
	destroyed_cells: Array[Vector2i],
	horizontal_direction: int,
	impact_origin_cell: Vector2i
) -> void:
	if destroyed_cells.is_empty():
		return
	var stamp := _create_impact_stamp(
		destroyed_cells,
		horizontal_direction,
		false,
		impact_origin_cell.x
	)
	_latest_impact_stamp = stamp
	_latest_foreground_opening_rect = _get_layer_opening_rect(stamp, 0)
	_apply_impact_stamps([stamp])
	if _show_logical_overlay:
		queue_redraw()


## Applies branching damage as one texture update per affected chunk.
func _on_terrain_paths_damaged(
	destroyed_paths: Array,
	horizontal_direction: int
) -> void:
	var stamps: Array[ImpactStamp] = []
	for destroyed_path: Array[Vector2i] in destroyed_paths:
		if destroyed_path.is_empty():
			continue
		stamps.append(
			_create_impact_stamp(
				destroyed_path,
				horizontal_direction,
				true
			)
		)
	_apply_impact_stamps(stamps)


## Stores related stamps and uploads each visible chunk only once.
func _apply_impact_stamps(stamps: Array[ImpactStamp]) -> void:
	var affected_chunk_lookup: Dictionary[int, bool] = {}
	for stamp in stamps:
		for chunk_index in _register_impact_stamp(stamp):
			affected_chunk_lookup[chunk_index] = true
	for chunk_index in affected_chunk_lookup:
		if not _active_chunks.has(chunk_index):
			continue
		var chunk := _active_chunks[chunk_index]
		var changed_layers := 0
		for stamp in stamps:
			if chunk_index not in _get_stamp_chunk_indices(stamp):
				continue
			changed_layers |= _apply_impact_stamp(
				chunk,
				chunk_index,
				stamp
			)
		_upload_chunk_masks(chunk, changed_layers)
	_clear_temporary_stamp_cache()


## Drops every streamed chunk and its stamp history so the next refresh draws
## intact terrain again. The editor preview needs this because moving a test
## impact has to un-break the rock the previous position broke.
func rebuild_all_chunks() -> void:
	_impact_stamps_by_chunk.clear()
	for chunk_index in _active_chunks.keys():
		_unload_chunk(chunk_index)
	_latest_impact_stamp = null
	_latest_foreground_opening_rect = Rect2()
	_loaded_first_chunk = -1
	_loaded_last_chunk = -1
	# Read the view back rather than reusing the cached one. Outside the mining
	# scene nothing connects view_position_changed, so the cached copy is still
	# sitting at the surface and the preview would ignore its authored depth.
	_on_view_position_changed(terrain_manager.get_view_position())


## Repositions streamed terrain around the current 2D mining face.
func _on_view_position_changed(view_cell_position: Vector2) -> void:
	_current_view_x = view_cell_position.x
	_current_view_y = view_cell_position.y
	_refresh_active_chunks()
	_position_active_chunks()
	if _show_logical_overlay:
		queue_redraw()


## Recalculates streamed coverage when the browser canvas changes size.
func _on_viewport_size_changed() -> void:
	_loaded_first_chunk = -1
	_loaded_last_chunk = -1
	_refresh_active_chunks()
	_position_active_chunks()


## Loads visible chunks plus the configured below-view margin.
func _refresh_active_chunks() -> void:
	# Coverage is measured against the viewport, which only exists once this is
	# in the tree. The editor instantiates a scene before parenting it, so an
	# unparented pass would size every chunk against an empty Rect2.
	if not is_inside_tree():
		return
	var config := terrain_manager.config
	var viewport_height := get_viewport_rect().size.y
	var cell_size := float(config.terrain_cell_world_size)
	var top_world_y := (
		_current_view_y
		- config.mining_face_screen_y / cell_size
	)
	var bottom_world_y := (
		_current_view_y
		+ (viewport_height - config.mining_face_screen_y) / cell_size
	)
	var first_chunk := maxi(
		floori(top_world_y / float(config.chunk_height_cells)),
		0
	)
	var last_visible_chunk := maxi(
		floori(
			(bottom_world_y - 0.001)
			/ float(config.chunk_height_cells)
		),
		first_chunk
	)
	var last_chunk := mini(
		last_visible_chunk + config.preload_chunks_below,
		_world_row_to_chunk(config.get_bottom_surface_row())
	)
	if (
		first_chunk == _loaded_first_chunk
		and last_chunk == _loaded_last_chunk
	):
		return

	var chunks_to_unload: Array[int] = []
	for chunk_index: int in _active_chunks:
		if chunk_index < first_chunk or chunk_index > last_chunk:
			chunks_to_unload.append(chunk_index)
	for chunk_index in chunks_to_unload:
		_unload_chunk(chunk_index)

	for chunk_index in range(first_chunk, last_chunk + 1):
		if not _active_chunks.has(chunk_index):
			_load_chunk(chunk_index)

	_loaded_first_chunk = first_chunk
	_loaded_last_chunk = last_chunk


## Creates every visual stratum for one terrain chunk.
func _load_chunk(chunk_index: int) -> void:
	var layer_count := profile.get_layer_count()
	if layer_count <= 0:
		return

	var chunk := TerrainChunkVisual.new()
	chunk.root = Node2D.new()
	chunk.root.name = "LayeredTerrainChunk_%d" % chunk_index
	add_child(chunk.root)

	var config: MiningConfig = terrain_manager.config
	var chunk_start_row := chunk_index * config.chunk_height_cells
	var chunk_contains_chamber := false
	if terrain_manager.encounter_config != null:
		for local_row in range(config.chunk_height_cells):
			if terrain_manager.encounter_config.is_chamber_row(
				chunk_start_row + local_row
					- config.initial_surface_row,
				config.total_run_depth
			):
				chunk_contains_chamber = true
				break
	# A sculpted room may sit in a chunk the encounter schedule alone would call
	# ordinary rock, so streaming has to ask about rooms as well as chambers.
	var chunk_contains_sculpt := _chunk_contains_sculpt(chunk_index)
	var chunk_has_per_layer_sculpt := (
		chunk_contains_sculpt and _chunk_has_per_layer_sculpt(chunk_index)
	)
	var base_mask := _build_chunk_base_mask(
		chunk_index,
		false,
		chunk_contains_chamber,
		chunk_contains_sculpt
	)
	var back_layer_mask: Image
	if profile.keep_back_layer_solid:
		back_layer_mask = (
			_build_chunk_base_mask(
				chunk_index,
				true,
				chunk_contains_chamber,
				chunk_contains_sculpt
			)
			if chunk_contains_chamber
			else base_mask
		)
	var chunk_world_size := _get_chunk_world_size()
	var world_origin := Vector2(
		0.0,
		float(chunk_index) * chunk_world_size.y
	)
	var first_backdrop_source_layer := (
		profile.get_gameplay_layer_count() - 1
	)
	for layer_index in range(layer_count):
		# The fourth gameplay stratum begins intact as the tunnel back wall.
		var uses_backdrop_source := (
			profile.keep_back_layer_solid
			and layer_index >= first_backdrop_source_layer
		)
		# Only the deepest stratum is immutable and may use the shared-mask/
		# one-pixel-fracture allocation optimization.
		var uses_final_backing_optimization := (
			profile.keep_back_layer_solid
			and layer_index == layer_count - 1
		)
		var source_mask := (
			back_layer_mask
			if uses_backdrop_source
			else base_mask
		)
		# The final reserved stratum is never stamped or used for support, so
		# it can own the already-built backdrop instead of copying it again.
		var layer_mask := (
			source_mask
			if uses_final_backing_optimization
			else source_mask.duplicate()
		)
		# A room whose strata were sculpted apart needs its own rock per
		# stratum. Only then is the extra build paid for, and only for the
		# gameplay strata: the reserved back wall stays the shared backdrop.
		if chunk_has_per_layer_sculpt and not uses_backdrop_source:
			layer_mask = _build_chunk_base_mask(
				chunk_index,
				false,
				chunk_contains_chamber,
				chunk_contains_sculpt,
				layer_index
			)
		if layer_index == 0:
			_clear_chamber_foreground_floor_bands(
				layer_mask,
				chunk_index
			)
		chunk.mask_images.append(layer_mask)
	var chamber_stamps: Array = _chamber_stamps_by_chunk.get(
		chunk_index,
		[]
	)
	for chamber_stamp: ImpactStamp in chamber_stamps:
		_apply_impact_stamp(chunk, chunk_index, chamber_stamp)
	var saved_stamps: Array = _impact_stamps_by_chunk.get(
		chunk_index,
		[]
	)
	for saved_stamp: ImpactStamp in saved_stamps:
		_apply_impact_stamp(chunk, chunk_index, saved_stamp)
	_clear_temporary_stamp_cache()

	for layer_index in range(layer_count):
		var mask_image := chunk.mask_images[layer_index]
		var mask_texture := ImageTexture.create_from_image(mask_image)
		var sprite := Sprite2D.new()
		sprite.name = "TerrainLayer_%d" % layer_index
		sprite.centered = false
		sprite.texture = mask_texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.scale = Vector2.ONE * (
			float(terrain_manager.config.terrain_cell_world_size)
			/ float(profile.mask_pixels_per_cell)
		)
		sprite.z_index = profile.get_layer_z_index(layer_index)
		# Editor stratum isolation. Nothing at runtime sets an override, so
		# this reads 1.0 during play and the sprite is untouched. Applying it
		# here rather than only to live chunks is what makes an isolated
		# stratum survive the rebuild every sculpt stroke causes.
		sprite.modulate.a = get_layer_display_opacity(layer_index)
		sprite.material = _create_layer_material(
			layer_index,
			world_origin,
			chunk_world_size
		)
		chunk.root.add_child(sprite)
		chunk.layer_sprites.append(sprite)
		chunk.mask_textures.append(mask_texture)
	_active_chunks[chunk_index] = chunk


## Dims or hides one stratum everywhere it is drawn, so a designer sculpting a
## buried layer can see it instead of the foreground rock covering it.
##
## Editor-only by convention rather than by a flag: nothing in a running game
## calls this, so every stratum reads 1.0 and the game draws exactly as it did.
## It changes no mask, no cell, and no z-order — only how visible a stratum is
## while it is being worked on.
func set_layer_display_opacity(layer_index: int, opacity: float) -> void:
	if layer_index < 0 or layer_index >= profile.get_layer_count():
		return
	if _layer_display_opacity.size() < profile.get_layer_count():
		_layer_display_opacity.resize(profile.get_layer_count())
		_layer_display_opacity.fill(1.0)
	_layer_display_opacity[layer_index] = clampf(opacity, 0.0, 1.0)
	_apply_layer_display_opacity()


## Returns how visible a stratum is currently drawn. Defaults to fully opaque,
## which is the only value a running game ever sees.
func get_layer_display_opacity(layer_index: int) -> float:
	if layer_index < 0 or layer_index >= _layer_display_opacity.size():
		return 1.0
	return _layer_display_opacity[layer_index]


## Restores every stratum to fully visible.
func clear_layer_display_overrides() -> void:
	if _layer_display_opacity.is_empty():
		return
	_layer_display_opacity.fill(1.0)
	_apply_layer_display_opacity()


func _apply_layer_display_opacity() -> void:
	for chunk_index: int in _active_chunks:
		var chunk := _active_chunks[chunk_index]
		for layer_index in range(chunk.layer_sprites.size()):
			chunk.layer_sprites[layer_index].modulate.a = (
				get_layer_display_opacity(layer_index)
			)


## Removes rendered chunk nodes while retaining their impact records.
func _unload_chunk(chunk_index: int) -> void:
	var chunk := _active_chunks[chunk_index]
	# Streaming can cross many chunk boundaries in one frame during a fast
	# review or fall. Deferred deletion would retain every old ImageTexture
	# until the frame ends and can exhaust memory before Godot flushes it.
	chunk.root.free()
	_active_chunks.erase(chunk_index)


## Builds one layer's undamaged terrain before applying organic openings.
func _build_chunk_base_mask(
	chunk_index: int,
	preserve_chamber_backdrop: bool,
	chunk_contains_chamber: bool,
	chunk_contains_sculpt: bool = false,
	sculpt_layer_index: int = -1
) -> Image:
	var config := terrain_manager.config
	var mask_cell_size := profile.mask_pixels_per_cell
	var mask_size := _get_chunk_mask_size()
	var image := Image.create(
		mask_size.x,
		mask_size.y,
		false,
		Image.FORMAT_LA8
	)
	var chunk_start_row := chunk_index * config.chunk_height_cells
	var chunk_end_row := (
		chunk_start_row + config.chunk_height_cells - 1
	)
	if (
		not chunk_contains_chamber
		and not chunk_contains_sculpt
		and chunk_start_row >= config.initial_surface_row
		and chunk_end_row <= config.get_bottom_surface_row()
	):
		image.fill(SOLID_MASK_COLOR)
		return image
	image.fill(EMPTY_MASK_COLOR)
	var encounter_config := terrain_manager.encounter_config
	var backdrop_right_cell := config.terrain_width_cells
	if encounter_config != null:
		var backdrop_width := mini(
			encounter_config.chamber_width_cells,
			config.terrain_width_cells
		)
		backdrop_right_cell = (
			floori(
				float(config.terrain_width_cells - backdrop_width) * 0.5
			)
			+ backdrop_width
		)
	for local_row in range(config.chunk_height_cells):
		var world_row := chunk_start_row + local_row
		if (
			world_row < config.initial_surface_row
			or world_row > config.get_bottom_surface_row()
		):
			continue
		var is_chamber_row := (
			encounter_config != null
			and encounter_config.is_chamber_row(
				world_row - config.initial_surface_row,
				config.total_run_depth
			)
		)
		var row_mask_y := local_row * mask_cell_size
		# An authored room overrides the procedural taper inside its own
		# footprint only, so the surrounding row is drawn first and the room is
		# printed over it. The retained backdrop pass is left alone: the back
		# wall is scenery behind every room, sculpted or not.
		var sculpt_placement := (
			terrain_manager.get_sculpt_placement_for_row(world_row)
			if chunk_contains_sculpt and not preserve_chamber_backdrop
			else null
		)
		if sculpt_placement != null:
			if is_chamber_row:
				_fill_chamber_side_mask(
					image,
					row_mask_y,
					world_row,
					mask_cell_size
				)
			else:
				image.fill_rect(
					Rect2i(0, row_mask_y, mask_size.x, mask_cell_size),
					SOLID_MASK_COLOR
				)
			_fill_sculpt_row_mask(
				image,
				row_mask_y,
				world_row,
				mask_cell_size,
				sculpt_placement,
				sculpt_layer_index
			)
			continue
		if not is_chamber_row:
			image.fill_rect(
				Rect2i(
					0,
					row_mask_y,
					mask_size.x,
					mask_cell_size
				),
				SOLID_MASK_COLOR
			)
			continue
		var chamber_bounds := (
			encounter_config.get_chamber_horizontal_bounds(
				world_row - config.initial_surface_row,
				config.total_run_depth,
				config.terrain_width_cells
			)
		)
		var chamber_left_cell := chamber_bounds.x
		var chamber_right_cell := chamber_bounds.y
		if preserve_chamber_backdrop:
			# Visual terrain may retain a solid deepest-layer backdrop behind
			# the logical chamber. A departure room clears exactly the normal
			# right side-wall width so the authored logical exit reads by eye;
			# F3 still overlays logical cells for parity inspection.
			var retained_backdrop_right := (
				backdrop_right_cell
				if chamber_right_cell == config.terrain_width_cells
				else config.terrain_width_cells
			)
			image.fill_rect(
				Rect2i(
					0,
					row_mask_y,
					retained_backdrop_right * mask_cell_size,
					mask_cell_size
				),
				SOLID_MASK_COLOR
			)
			continue
		_fill_chamber_side_mask(
			image,
			row_mask_y,
			world_row,
			mask_cell_size
		)
	return image


## Reports whether any authored room reaches into a streamed chunk.
func _chunk_contains_sculpt(chunk_index: int) -> bool:
	var config: MiningConfig = terrain_manager.config
	var chunk_start_row := chunk_index * config.chunk_height_cells
	var chunk_end_row := chunk_start_row + config.chunk_height_cells
	for placement in terrain_manager.get_sculpt_placements():
		if (
			placement.world_rect.position.y < chunk_end_row
			and placement.world_rect.end.y > chunk_start_row
		):
			return true
	return false


## Reports whether a chunk holds a room whose strata were sculpted apart, which
## is the only case that costs one mask build per stratum instead of one shared.
func _chunk_has_per_layer_sculpt(chunk_index: int) -> bool:
	var config: MiningConfig = terrain_manager.config
	var chunk_start_row := chunk_index * config.chunk_height_cells
	var chunk_end_row := chunk_start_row + config.chunk_height_cells
	for placement in terrain_manager.get_sculpt_placements():
		if (
			placement.world_rect.position.y < chunk_end_row
			and placement.world_rect.end.y > chunk_start_row
			and placement.sculpt.has_layer_masks()
		):
			return true
	return false


## Prints one authored room row over the terrain already drawn beneath it.
## Interior cells are filled in runs and only cells touching a solid/open
## boundary pay per-pixel work, which is what keeps a sculpted chunk's build
## cost in the same range as the procedural chamber it replaces.
func _fill_sculpt_row_mask(
	image: Image,
	row_mask_y: int,
	world_row: int,
	mask_cell_size: int,
	placement: TerrainManager.SculptPlacement,
	sculpt_layer_index: int
) -> void:
	var config: MiningConfig = terrain_manager.config
	var sculpt: CutsceneTerrainSculpt = placement.sculpt
	var room_rect: Rect2i = placement.world_rect
	var local_y: int = world_row - room_rect.position.y
	var first_cell_x: int = maxi(room_rect.position.x, 0)
	var last_cell_x: int = mini(
		room_rect.end.x,
		config.terrain_width_cells
	) - 1
	if last_cell_x < first_cell_x:
		return

	var run_start_cell_x: int = first_cell_x
	var run_is_solid: bool = _is_sculpt_cell_solid(
		sculpt,
		sculpt_layer_index,
		Vector2i(first_cell_x - room_rect.position.x, local_y)
	)
	for cell_x in range(first_cell_x, last_cell_x + 2):
		var is_solid: bool = (
			run_is_solid
			if cell_x > last_cell_x
			else _is_sculpt_cell_solid(
				sculpt,
				sculpt_layer_index,
				Vector2i(cell_x - room_rect.position.x, local_y)
			)
		)
		if is_solid == run_is_solid and cell_x <= last_cell_x:
			continue
		image.fill_rect(
			Rect2i(
				run_start_cell_x * mask_cell_size,
				row_mask_y,
				(cell_x - run_start_cell_x) * mask_cell_size,
				mask_cell_size
			),
			SOLID_MASK_COLOR if run_is_solid else EMPTY_MASK_COLOR
		)
		run_start_cell_x = cell_x
		run_is_solid = is_solid

	if sculpt.edge_smoothing <= 0.0:
		return
	for cell_x in range(first_cell_x, last_cell_x + 1):
		var local_cell := Vector2i(cell_x - room_rect.position.x, local_y)
		if not _is_sculpt_boundary_cell(sculpt, sculpt_layer_index, local_cell):
			continue
		_write_sculpt_boundary_cell(
			image,
			cell_x * mask_cell_size,
			row_mask_y,
			mask_cell_size,
			sculpt,
			sculpt_layer_index,
			local_cell
		)


## Reads one room cell, choosing the stratum's own rock when the strata were
## sculpted apart and the shared collision shape otherwise.
func _is_sculpt_cell_solid(
	sculpt: CutsceneTerrainSculpt,
	sculpt_layer_index: int,
	local_cell: Vector2i
) -> bool:
	if sculpt_layer_index < 0:
		return sculpt.is_solid_local(local_cell)
	return sculpt.is_layer_solid_local(sculpt_layer_index, local_cell)


## Reports whether a cell sits on a solid/open edge, the only place the drawn
## rock departs from the authored cell grid.
func _is_sculpt_boundary_cell(
	sculpt: CutsceneTerrainSculpt,
	sculpt_layer_index: int,
	local_cell: Vector2i
) -> bool:
	var is_solid := _is_sculpt_cell_solid(
		sculpt,
		sculpt_layer_index,
		local_cell
	)
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			if offset_x == 0 and offset_y == 0:
				continue
			if _is_sculpt_cell_solid(
				sculpt,
				sculpt_layer_index,
				local_cell + Vector2i(offset_x, offset_y)
			) != is_solid:
				return true
	return false


## Softens one rim cell toward its neighbours so a sculpted wall reads as rock
## rather than as the stair-stepped grid it was painted on. edge_smoothing at
## zero leaves the hard cell edge, which is what makes a roughened wall jagged.
func _write_sculpt_boundary_cell(
	image: Image,
	cell_mask_x: int,
	cell_mask_y: int,
	mask_cell_size: int,
	sculpt: CutsceneTerrainSculpt,
	sculpt_layer_index: int,
	local_cell: Vector2i
) -> void:
	var smoothing := sculpt.edge_smoothing
	var hard_value := (
		1.0
		if _is_sculpt_cell_solid(sculpt, sculpt_layer_index, local_cell)
		else 0.0
	)
	var image_width := image.get_width()
	var image_height := image.get_height()
	for sub_y in range(mask_cell_size):
		var mask_y := cell_mask_y + sub_y
		if mask_y < 0 or mask_y >= image_height:
			continue
		for sub_x in range(mask_cell_size):
			var mask_x := cell_mask_x + sub_x
			if mask_x < 0 or mask_x >= image_width:
				continue
			var coverage := _sample_sculpt_coverage(
				sculpt,
				sculpt_layer_index,
				local_cell,
				(float(sub_x) + 0.5) / float(mask_cell_size),
				(float(sub_y) + 0.5) / float(mask_cell_size)
			)
			image.set_pixel(
				mask_x,
				mask_y,
				Color(1.0, 1.0, 1.0, lerpf(hard_value, coverage, smoothing))
			)


## Interpolates the four room cells nearest one mask pixel. Sampling cell
## centers rather than cell corners is what keeps a straight wall straight
## instead of pulling it half a cell into the rock.
func _sample_sculpt_coverage(
	sculpt: CutsceneTerrainSculpt,
	sculpt_layer_index: int,
	local_cell: Vector2i,
	sub_cell_x: float,
	sub_cell_y: float
) -> float:
	var sample_x := float(local_cell.x) + sub_cell_x - 0.5
	var sample_y := float(local_cell.y) + sub_cell_y - 0.5
	var base_x := floori(sample_x)
	var base_y := floori(sample_y)
	var weight_x := sample_x - float(base_x)
	var weight_y := sample_y - float(base_y)
	var top_left := _get_sculpt_cell_value(
		sculpt, sculpt_layer_index, Vector2i(base_x, base_y)
	)
	var top_right := _get_sculpt_cell_value(
		sculpt, sculpt_layer_index, Vector2i(base_x + 1, base_y)
	)
	var bottom_left := _get_sculpt_cell_value(
		sculpt, sculpt_layer_index, Vector2i(base_x, base_y + 1)
	)
	var bottom_right := _get_sculpt_cell_value(
		sculpt, sculpt_layer_index, Vector2i(base_x + 1, base_y + 1)
	)
	return lerpf(
		lerpf(top_left, top_right, weight_x),
		lerpf(bottom_left, bottom_right, weight_x),
		weight_y
	)


func _get_sculpt_cell_value(
	sculpt: CutsceneTerrainSculpt,
	sculpt_layer_index: int,
	local_cell: Vector2i
) -> float:
	return (
		1.0
		if _is_sculpt_cell_solid(sculpt, sculpt_layer_index, local_cell)
		else 0.0
	)


## Lowers only layer one beneath each room's unchanged layer-two support.
func _clear_chamber_foreground_floor_bands(
	image: Image,
	chunk_index: int
) -> void:
	var config := terrain_manager.config
	var encounter_config := terrain_manager.encounter_config
	if (
		encounter_config == null
		or profile.chamber_layer_two_floor_reveal_px <= 0.0
		or profile.mask_pixels_per_cell <= 0
	):
		return
	var reveal_mask_height := maxi(
		ceili(
			profile.chamber_layer_two_floor_reveal_px
				* float(profile.mask_pixels_per_cell)
				/ float(config.terrain_cell_world_size)
		),
		1
	)
	var chunk_mask_height := (
		config.chunk_height_cells * profile.mask_pixels_per_cell
	)
	var chunk_mask_top := chunk_index * chunk_mask_height
	var image_bounds := Rect2i(Vector2i.ZERO, image.get_size())
	for encounter in encounter_config.encounters:
		if encounter == null:
			continue
		var encounter_depth := encounter.resolve_depth(
			config.total_run_depth
		)
		var floor_world_row := (
			config.initial_surface_row + encounter_depth
		)
		var floor_mask_y := (
			floor_world_row * profile.mask_pixels_per_cell
			- chunk_mask_top
		)
		var chamber_bounds := (
			encounter_config.get_chamber_horizontal_bounds(
				encounter_depth - 1,
				config.total_run_depth,
				config.terrain_width_cells
			)
		)
		var reveal_rect := Rect2i(
			chamber_bounds.x * profile.mask_pixels_per_cell,
			floor_mask_y,
			(chamber_bounds.y - chamber_bounds.x)
				* profile.mask_pixels_per_cell,
			reveal_mask_height
		).intersection(image_bounds)
		if reveal_rect.has_area():
			image.fill_rect(reveal_rect, EMPTY_MASK_COLOR)


## Draws the shared chamber taper at mask-pixel resolution. This runs only
## while a chunk is built, never on the per-hit mining hot path.
func _fill_chamber_side_mask(
	image: Image,
	row_mask_y: int,
	world_row: int,
	mask_cell_size: int
) -> void:
	var config: MiningConfig = terrain_manager.config
	var encounter_config: DepthEncounterConfig = (
		terrain_manager.encounter_config
	)
	if encounter_config == null or mask_cell_size <= 0:
		return
	var mask_width: int = image.get_width()
	for sub_row: int in range(mask_cell_size):
		var depth: float = (
			float(world_row - config.initial_surface_row)
			+ (float(sub_row) + 0.5) / float(mask_cell_size)
		)
		var chamber_bounds: Vector2 = (
			encounter_config.get_chamber_horizontal_bounds_at_depth(
				depth,
				config.total_run_depth,
				config.terrain_width_cells
			)
		)
		var left_mask_x: float = clampf(
			chamber_bounds.x * float(mask_cell_size),
			0.0,
			float(mask_width)
		)
		var right_mask_x: float = clampf(
			chamber_bounds.y * float(mask_cell_size),
			left_mask_x,
			float(mask_width)
		)
		var mask_y: int = row_mask_y + sub_row
		var left_full_pixels: int = floori(left_mask_x)
		if left_full_pixels > 0:
			image.fill_rect(
				Rect2i(0, mask_y, left_full_pixels, 1),
				SOLID_MASK_COLOR
			)
		if left_full_pixels < mask_width:
			var left_coverage: float = (
				left_mask_x - float(left_full_pixels)
			)
			if left_coverage > 0.0:
				image.set_pixel(
					left_full_pixels,
					mask_y,
					Color(1.0, 1.0, 1.0, left_coverage)
				)

		var right_full_start: int = ceili(right_mask_x)
		if right_full_start < mask_width:
			image.fill_rect(
				Rect2i(
					right_full_start,
					mask_y,
					mask_width - right_full_start,
					1
				),
				SOLID_MASK_COLOR
			)
		var right_boundary_pixel: int = floori(right_mask_x)
		if (
			right_boundary_pixel >= 0
			and right_boundary_pixel < mask_width
		):
			var right_coverage: float = (
				float(right_full_start) - right_mask_x
			)
			if right_coverage > 0.0:
				image.set_pixel(
					right_boundary_pixel,
					mask_y,
					Color(1.0, 1.0, 1.0, right_coverage)
				)


## Keeps every loaded chunk aligned as the view follows the player.
func _position_active_chunks() -> void:
	var config := terrain_manager.config
	var cell_size := float(config.terrain_cell_world_size)
	var terrain_left := (
		config.terrain_screen_center_x
		- _current_view_x * cell_size
	)
	for chunk_index: int in _active_chunks:
		var chunk := _active_chunks[chunk_index]
		var chunk_start_row := (
			float(chunk_index) * float(config.chunk_height_cells)
		)
		chunk.root.position = Vector2(
			terrain_left,
			config.mining_face_screen_y
			+ (chunk_start_row - _current_view_y) * cell_size
		)


## Converts one hit's actual damage bounds into a persistent art stamp.
func _create_impact_stamp(
	destroyed_cells: Array[Vector2i],
	horizontal_direction: int,
	is_narrow_path: bool = false,
	impact_origin_cell_x: int = -1
) -> ImpactStamp:
	var minimum_cell := destroyed_cells[0]
	var maximum_cell := destroyed_cells[0]
	for cell in destroyed_cells:
		minimum_cell.x = mini(minimum_cell.x, cell.x)
		minimum_cell.y = mini(minimum_cell.y, cell.y)
		maximum_cell.x = maxi(maximum_cell.x, cell.x)
		maximum_cell.y = maxi(maximum_cell.y, cell.y)

	var cell_size := terrain_manager.config.terrain_cell_world_size
	var stamp := ImpactStamp.new()
	var damage_rect := Rect2(
		Vector2(minimum_cell * cell_size),
		Vector2(
			(maximum_cell - minimum_cell + Vector2i.ONE)
			* cell_size
		)
	)
	var damage_center := damage_rect.get_center()
	# Damage may fan toward either swing side, but its visual center remains the
	# reachable pickaxe contact instead of expanding from beneath the miner.
	stamp.center = damage_center
	if not is_narrow_path and impact_origin_cell_x >= 0:
		stamp.center.x = (
			float(impact_origin_cell_x) + 0.5
		) * float(cell_size)
	stamp.damage_bounds = damage_rect
	if is_narrow_path:
		var combo_strength := clampf(
			float(_active_impact_combo)
				/ float(
					maxi(
						terrain_manager.config.maximum_effect_combo,
						1
					)
				),
			0.0,
			1.0
		)
		stamp.narrow_path_radius_scale = lerpf(
			0.9,
			1.5,
			combo_strength
		)
		# Inner crack segments retain enough force to cut two upper strata.
		# The final segment always fades to the foreground layer only.
		stamp.narrow_path_two_layer_fraction = lerpf(
			0.45,
			0.75,
			combo_strength
		)
		for cell_index in range(0, destroyed_cells.size(), 2):
			stamp.narrow_path_points.append(
				(
					Vector2(destroyed_cells[cell_index])
					+ Vector2.ONE * 0.5
				) * cell_size
			)
		if destroyed_cells.size() % 2 == 0:
			stamp.narrow_path_points.append(
				(
					Vector2(destroyed_cells.back())
					+ Vector2.ONE * 0.5
				) * cell_size
			)
	stamp.core_radius = (
		maxf(damage_rect.size.x, damage_rect.size.y) * 0.5
	)
	stamp.use_big_hole = (
		not is_narrow_path
		and _active_impact_combo >= deepest_layer_combo_threshold
		and stamp.core_radius * 2.0
		>= float(profile.big_hole_minimum_size)
	)
	var variation_hash := (
		minimum_cell.x * 73_856_093
		^ minimum_cell.y * 19_349_663
		^ destroyed_cells.size() * 83_492_791
	)
	stamp.flip_x = (
		horizontal_direction < 0
		or (horizontal_direction == 0 and variation_hash % 2 == 0)
	)
	stamp.flip_y = variation_hash % 3 == 0
	stamp.rotation_quarters = posmod(variation_hash, 4)
	stamp.size_variation = (
		0.92
		+ float(posmod(variation_hash / 4, 9)) * 0.02
	)
	stamp.variation_hash = variation_hash
	return stamp


## Returns one stratum's own orientation and size jitter for a hit.
##
## Every layer used to punch the identical silhouette at a smaller scale, so a
## hit left four concentric copies of one shape and read as the same jagged
## outline traced over and over. Decorrelating orientation by layer makes each
## exposed rim its own break. Nesting is unaffected: punch_hole normalises the
## authored cavity into the layer's opening rect whatever its orientation, so a
## deeper opening still cannot escape the shallower one in front of it.
##
## The layer's own hash drives this, so a chunk streamed back in redraws the
## same rims rather than rerolling them. Layer zero keeps the stamp's authored
## orientation, because its flip carries the swing direction.
func _get_layer_stamp_variation(
	stamp: ImpactStamp,
	layer_index: int
) -> Vector4i:
	if layer_index <= 0:
		return Vector4i(
			1 if stamp.flip_x else 0,
			1 if stamp.flip_y else 0,
			stamp.rotation_quarters,
			4
		)
	var layer_hash := absi(
		stamp.variation_hash
		^ (layer_index * 2_654_435_761)
	)
	return Vector4i(
		layer_hash % 2,
		(layer_hash / 2) % 2,
		(layer_hash / 4) % 4,
		(layer_hash / 16) % 9
	)


## Stores a stamp beside every chunk its organic edge can touch.
func _register_impact_stamp(stamp: ImpactStamp) -> Array[int]:
	var affected_chunks := _get_stamp_chunk_indices(stamp)
	for chunk_index in affected_chunks:
		var stamps: Array = _impact_stamps_by_chunk.get(
			chunk_index,
			[]
		)
		stamps.append(stamp)
		_impact_stamps_by_chunk[chunk_index] = stamps
	return affected_chunks


## Punches transformed organic masks so every stratum has a distinct rim.
func _apply_impact_stamp(
	chunk: TerrainChunkVisual,
	chunk_index: int,
	stamp: ImpactStamp
) -> int:
	var gameplay_layer_count := profile.get_gameplay_layer_count()
	var layer_count := gameplay_layer_count
	var changed_layers := 0
	for layer_index in range(layer_count):
		if (
			profile.keep_back_layer_solid
			and layer_index == gameplay_layer_count - 1
		):
			continue
		var is_layer_covering_backdrop := (
			profile.keep_back_layer_solid
			and layer_index == gameplay_layer_count - 2
		)
		# Orange remains the decorative tunnel backdrop below combo seven.
		# At or above the combo gate, the size threshold still prevents a
		# physically small secondary path from exposing the brown back wall.
		if is_layer_covering_backdrop and not stamp.use_big_hole:
			continue
		var layer_changed := false
		if not stamp.narrow_path_points.is_empty():
			if _punch_narrow_path(
				chunk.mask_images[layer_index],
				chunk_index,
				stamp,
				layer_index
			):
				layer_changed = true
			if layer_changed:
				changed_layers |= 1 << layer_index
			continue
		var mask_data := _get_hole_mask_data(
			layer_index,
			stamp.use_big_hole
		)
		if mask_data == null:
			if layer_changed:
				changed_layers |= 1 << layer_index
			continue
		var opening_rect := _get_layer_opening_rect(
			stamp,
			layer_index
		)
		var layer_variation := _get_layer_stamp_variation(
			stamp,
			layer_index
		)
		if _punch_hole(
			chunk.mask_images[layer_index],
			chunk_index,
			opening_rect,
			mask_data,
			layer_variation.x == 1,
			layer_variation.y == 1,
			layer_variation.z
		):
			layer_changed = true
		if layer_changed:
			changed_layers |= 1 << layer_index
	return changed_layers


## Returns the organic opening drawn for one ordinary impact layer.
func _get_layer_opening_rect(
	stamp: ImpactStamp,
	layer_index: int
) -> Rect2:
	var layers_below := maxi(
		profile.get_gameplay_layer_count() - layer_index - 1,
		0
	)
	var opening_growth := (
		profile.core_hole_padding
		+ profile.rim_width * layers_below
	)
	# Each stratum nudges its own radius as well as its orientation, so the
	# bands between rims vary in width instead of stepping down by one constant.
	# The jitter stays well inside the rim_width the layers are already spaced
	# by, so a deeper opening can never overtake the one in front of it.
	var layer_size_jitter := (
		0.94
		+ float(_get_layer_stamp_variation(stamp, layer_index).w) * 0.015
	)
	var opening_radius := (
		(stamp.core_radius + float(opening_growth))
		* stamp.size_variation
		* layer_size_jitter
		* profile.get_layer_impact_scale(layer_index)
	)
	var layer_offset := profile.get_layer_impact_offset(layer_index)
	if stamp.flip_x:
		layer_offset.x *= -1.0
	if stamp.flip_y:
		layer_offset.y *= -1.0
	var opening_center := stamp.center + layer_offset
	# Mining stamps expand far enough to cover every damaged cell.
	if stamp.damage_bounds.has_area():
		var damage_end := stamp.damage_bounds.end
		var damage_corners := PackedVector2Array([
			stamp.damage_bounds.position,
			Vector2(damage_end.x, stamp.damage_bounds.position.y),
			damage_end,
			Vector2(stamp.damage_bounds.position.x, damage_end.y),
		])
		for damage_corner in damage_corners:
			opening_radius = maxf(
				opening_radius,
				opening_center.distance_to(damage_corner)
					+ float(profile.core_hole_padding)
			)
	return Rect2(
		opening_center - Vector2.ONE * opening_radius,
		Vector2.ONE * opening_radius * 2.0
	)


## Returns the latest foreground opening for impact-bound presentation.
func get_latest_foreground_opening_rect() -> Rect2:
	return _latest_foreground_opening_rect


## Converts the latest terrain-space impact opening into screen coordinates.
func get_latest_foreground_opening_screen_rect() -> Rect2:
	if not _latest_foreground_opening_rect.has_area():
		return Rect2()
	var config: MiningConfig = terrain_manager.config
	var cell_size: float = float(config.terrain_cell_world_size)
	var terrain_left: float = (
		config.terrain_screen_center_x
		- _current_view_x * cell_size
	)
	return Rect2(
		Vector2(
			terrain_left + _latest_foreground_opening_rect.position.x,
			config.mining_face_screen_y
				+ _latest_foreground_opening_rect.position.y
				- _current_view_y * cell_size
		),
		_latest_foreground_opening_rect.size
	)


## Finds the bottom lip where one layer's organic opening becomes solid again.
func get_layer_opening_floor_support_screen_y(
	screen_x: float,
	landing_world_row: int,
	layer_index: int
) -> float:
	if (
		layer_index < 0
		or layer_index >= profile.get_layer_count()
		or profile.mask_pixels_per_cell <= 0
	):
		return NAN
	var config: MiningConfig = terrain_manager.config
	var cell_size: float = float(config.terrain_cell_world_size)
	var mask_pixels_per_world_unit: float = (
		float(profile.mask_pixels_per_cell) / cell_size
	)
	var terrain_left: float = (
		config.terrain_screen_center_x
		- _current_view_x * cell_size
	)
	var mask_x: int = floori(
		(screen_x - terrain_left) * mask_pixels_per_world_unit
	)
	var mask_width: int = (
		config.terrain_width_cells * profile.mask_pixels_per_cell
	)
	if mask_x < 0 or mask_x >= mask_width:
		return NAN

	var chunk_mask_height: int = (
		config.chunk_height_cells * profile.mask_pixels_per_cell
	)
	var landing_mask_y: int = maxi(
		landing_world_row * profile.mask_pixels_per_cell,
		0
	)
	var sample_count: int = (
		MAX_SUPPORT_SCAN_ROWS * profile.mask_pixels_per_cell
	)
	var opening_mask_y: int = -1
	for sample_offset: int in range(sample_count + 1):
		var world_mask_y: int = landing_mask_y - sample_offset
		if world_mask_y < 0:
			break
		var chunk_index: int = floori(
			float(world_mask_y) / float(chunk_mask_height)
		)
		if not _active_chunks.has(chunk_index):
			continue
		var chunk: TerrainChunkVisual = _active_chunks[chunk_index]
		if layer_index >= chunk.mask_images.size():
			continue
		var local_mask_y: int = posmod(
			world_mask_y,
			chunk_mask_height
		)
		var layer_alpha: float = (
			chunk.mask_images[layer_index]
			.get_pixel(mask_x, local_mask_y)
			.a
		)
		if layer_alpha < profile.transparent_alpha_threshold:
			opening_mask_y = world_mask_y
			break
	if opening_mask_y < 0:
		return NAN

	for sample_offset: int in range(sample_count + 1):
		var world_mask_y: int = opening_mask_y + sample_offset
		var chunk_index: int = floori(
			float(world_mask_y) / float(chunk_mask_height)
		)
		if not _active_chunks.has(chunk_index):
			continue
		var chunk: TerrainChunkVisual = _active_chunks[chunk_index]
		if layer_index >= chunk.mask_images.size():
			continue
		var local_mask_y: int = posmod(
			world_mask_y,
			chunk_mask_height
		)
		var layer_alpha: float = (
			chunk.mask_images[layer_index]
			.get_pixel(mask_x, local_mask_y)
			.a
		)
		if layer_alpha < profile.transparent_alpha_threshold:
			continue

		var support_mask_y := world_mask_y
		var fracture_support_found := false
		var fracture_scan_start := maxi(
			opening_mask_y + 1,
			world_mask_y - FRACTURE_SUPPORT_HALF_WIDTH_MASK_PIXELS
		)
		var fracture_scan_end := (
			world_mask_y + FRACTURE_SUPPORT_SCAN_MASK_PIXELS
		)
		for fracture_world_y: int in range(
			fracture_scan_start,
			fracture_scan_end + 1
		):
			var fracture_chunk_index := floori(
				float(fracture_world_y) / float(chunk_mask_height)
			)
			if not _active_chunks.has(fracture_chunk_index):
				continue
			var fracture_chunk: TerrainChunkVisual = (
				_active_chunks[fracture_chunk_index]
			)
			if layer_index >= fracture_chunk.mask_images.size():
				continue
			var fracture_local_y := posmod(
				fracture_world_y,
				chunk_mask_height
			)
			var fracture_min_x := maxi(
				mask_x - FRACTURE_SUPPORT_HALF_WIDTH_MASK_PIXELS,
				0
			)
			var fracture_max_x := mini(
				mask_x + FRACTURE_SUPPORT_HALF_WIDTH_MASK_PIXELS,
				mask_width - 1
			)
			for fracture_x: int in range(
				fracture_min_x,
				fracture_max_x + 1
			):
				var fracture_layer_alpha := (
					fracture_chunk.mask_images[layer_index]
					.get_pixel(fracture_x, fracture_local_y)
					.a
				)
				if (
					fracture_layer_alpha
					< profile.transparent_alpha_threshold
				):
					continue
				var fracture_value := (
					fracture_chunk.mask_images[layer_index]
					.get_pixel(fracture_x, fracture_local_y)
					.r
				)
				if fracture_value < FRACTURE_SUPPORT_VALUE_THRESHOLD:
					support_mask_y = fracture_world_y
					fracture_support_found = true
					break
			if fracture_support_found:
				break

		var support_world_y: float = (
			(
				float(support_mask_y)
				+ (0.0 if fracture_support_found else 0.5)
			)
			/ mask_pixels_per_world_unit
		)
		_latest_support_world_position = Vector2(
			screen_x - terrain_left,
			support_world_y
		)
		if _show_logical_overlay:
			queue_redraw()
		return (
			config.mining_face_screen_y
			+ support_world_y
			- _current_view_y * cell_size
		)
	return NAN


## Toggles a visual audit of logical openings with one debug keypress.
func _unhandled_key_input(event: InputEvent) -> void:
	if (
		not event is InputEventKey
		or not event.pressed
		or event.echo
		or event.keycode != logical_overlay_key
	):
		return
	_show_logical_overlay = not _show_logical_overlay
	queue_redraw()
	get_viewport().set_input_as_handled()


## Draws visible non-solid cells over whichever decorative backdrop remains.
func _draw() -> void:
	if not _show_logical_overlay:
		return
	var config := terrain_manager.config
	var cell_size := float(config.terrain_cell_world_size)
	var viewport_height := get_viewport_rect().size.y
	var first_row := maxi(
		floori(
			_current_view_y
				- config.mining_face_screen_y / cell_size
		),
		config.initial_surface_row
	)
	var last_row := mini(
		ceili(
			_current_view_y
				+ (
					viewport_height - config.mining_face_screen_y
				) / cell_size
		),
		config.get_bottom_surface_row()
	)
	var terrain_left := (
		config.terrain_screen_center_x
		- _current_view_x * cell_size
	)
	for cell_y in range(first_row, last_row + 1):
		for cell_x in range(config.terrain_width_cells):
			if terrain_manager.is_solid_cell(Vector2i(cell_x, cell_y)):
				continue
			draw_rect(
				Rect2(
					terrain_left + float(cell_x) * cell_size,
					config.mining_face_screen_y
						+ (float(cell_y) - _current_view_y)
							* cell_size,
					cell_size,
					cell_size
				),
				logical_overlay_color
			)
	if not is_nan(_latest_support_world_position.y):
		var support_screen_position := Vector2(
			terrain_left + _latest_support_world_position.x,
			config.mining_face_screen_y
				+ _latest_support_world_position.y
				- _current_view_y * cell_size
		)
		draw_circle(
			support_screen_position,
			4.0,
			Color(1.0, 0.15, 0.85, 0.95)
		)


## Draws one sharp dark crack instead of repeating the full hole artwork.
func _punch_narrow_path(
	destination: Image,
	chunk_index: int,
	stamp: ImpactStamp,
	layer_index: int
) -> bool:
	# The foreground is cut for the full branch, the second layer is cut only
	# near the blast, and the third layer receives dark scoring without a cut.
	if layer_index > 2 or stamp.narrow_path_points.is_empty():
		return false
	var layer_offset := profile.get_layer_impact_offset(layer_index) * 0.25
	if stamp.flip_x:
		layer_offset.x *= -1.0
	if stamp.flip_y:
		layer_offset.y *= -1.0

	var full_point_count := stamp.narrow_path_points.size()
	var powered_point_count := clampi(
		ceili(
			float(full_point_count)
				* stamp.narrow_path_two_layer_fraction
		),
		1,
		full_point_count
	)
	var fracture_point_count := (
		powered_point_count if layer_index == 2 else full_point_count
	)
	var cut_point_count := (
		full_point_count
		if layer_index == 0
		else powered_point_count if layer_index == 1 else 0
	)
	var mask_pixels_per_world_unit := (
		float(profile.mask_pixels_per_cell)
		/ float(terrain_manager.config.terrain_cell_world_size)
	)
	var chunk_mask_top := (
		chunk_index
		* terrain_manager.config.chunk_height_cells
		* profile.mask_pixels_per_cell
	)
	var fracture_radius := maxf(
		1.25,
		float(profile.mask_pixels_per_cell)
			* 0.24
			* stamp.narrow_path_radius_scale
	)
	var cut_radius := 0.8 if layer_index == 0 else 0.55
	# Branch scoring fades with the same per-stratum falloff as the authored
	# masks, so a hit never leaves one crack repeated once per visible layer.
	var line_scale := profile.get_fracture_line_layer_scale(layer_index)
	var dark_value := 1.0 - profile.fracture_line_strength * line_scale
	if line_scale <= 0.0 and cut_point_count <= 0:
		return false
	var image_size := destination.get_size()
	var changed := false
	var segment_count := maxi(fracture_point_count - 1, 1)
	for point_index in range(segment_count):
		var next_point_index := mini(
			point_index + 1,
			fracture_point_count - 1
		)
		var start_point := (
			stamp.narrow_path_points[point_index] + layer_offset
		) * mask_pixels_per_world_unit
		var end_point := (
			stamp.narrow_path_points[next_point_index] + layer_offset
		) * mask_pixels_per_world_unit
		start_point.y -= float(chunk_mask_top)
		end_point.y -= float(chunk_mask_top)
		var segment_steps := maxi(
			ceili(start_point.distance_to(end_point) * 2.0),
			1
		)
		for step_index in range(segment_steps + 1):
			var segment_progress := (
				float(step_index) / float(segment_steps)
			)
			var line_center := start_point.lerp(
				end_point,
				segment_progress
			)
			var path_progress := float(point_index) + segment_progress
			var can_cut := (
				cut_point_count > 0
				and path_progress <= float(cut_point_count - 1)
			)
			var minimum_pixel := Vector2i(
				maxi(floori(line_center.x - fracture_radius - 1.0), 0),
				maxi(floori(line_center.y - fracture_radius - 1.0), 0)
			)
			var maximum_pixel := Vector2i(
				mini(ceili(line_center.x + fracture_radius + 1.0), image_size.x - 1),
				mini(ceili(line_center.y + fracture_radius + 1.0), image_size.y - 1)
			)
			for pixel_y in range(minimum_pixel.y, maximum_pixel.y + 1):
				for pixel_x in range(minimum_pixel.x, maximum_pixel.x + 1):
					var pixel_center := Vector2(
						float(pixel_x) + 0.5,
						float(pixel_y) + 0.5
					)
					var distance_to_line := pixel_center.distance_to(
						line_center
					)
					var fracture_coverage := clampf(
						fracture_radius + 0.75 - distance_to_line,
						0.0,
						1.0
					)
					if fracture_coverage > 0.0:
						var current_mask := destination.get_pixel(
							pixel_x,
							pixel_y
						)
						var fracture_value := lerpf(
							1.0,
							dark_value,
							fracture_coverage
						)
						if fracture_value < current_mask.r:
							destination.set_pixel(
								pixel_x,
								pixel_y,
								Color(
									fracture_value,
									fracture_value,
									fracture_value,
									current_mask.a
								)
							)
							changed = true
					if not can_cut:
						continue
					var cut_coverage := clampf(
						cut_radius + 0.75 - distance_to_line,
						0.0,
						1.0
					)
					if cut_coverage <= 0.0:
						continue
					var current_mask := destination.get_pixel(
						pixel_x,
						pixel_y
					)
					current_mask.a *= 1.0 - cut_coverage
					destination.set_pixel(pixel_x, pixel_y, current_mask)
					changed = true
	return changed


## Clears the transparent part of one authored mask from a chunk layer.
func _punch_hole(
	destination: Image,
	chunk_index: int,
	opening_world_rect: Rect2,
	mask_data: HoleMaskData,
	flip_x: bool,
	flip_y: bool,
	rotation_quarters: int
) -> bool:
	var source_bounds := _get_oriented_transparent_bounds(
		mask_data,
		flip_x,
		flip_y,
		rotation_quarters
	)
	if source_bounds.size.x <= 0.0 or source_bounds.size.y <= 0.0:
		return false

	var full_stamp_size := Vector2(
		opening_world_rect.size.x
		/ source_bounds.size.x,
		opening_world_rect.size.y
		/ source_bounds.size.y
	)
	var full_stamp_position := (
		opening_world_rect.position
		- source_bounds.position * full_stamp_size
	)
	var full_stamp_rect := Rect2(
		full_stamp_position,
		full_stamp_size
	)
	var chunk_world_size := _get_chunk_world_size()
	var chunk_world_rect := Rect2(
		Vector2(
			0.0,
			float(chunk_index) * chunk_world_size.y
		),
		chunk_world_size
	)
	var affected_world_rect := full_stamp_rect.intersection(
		chunk_world_rect
	)
	if affected_world_rect.size.x <= 0.0 or affected_world_rect.size.y <= 0.0:
		return false

	var mask_pixels_per_world_unit := (
		float(profile.mask_pixels_per_cell)
		/ float(terrain_manager.config.terrain_cell_world_size)
	)
	var stamp_size := Vector2i(
		maxi(
			ceili(
				full_stamp_size.x * mask_pixels_per_world_unit
			),
			1
		),
		maxi(
			ceili(
				full_stamp_size.y * mask_pixels_per_world_unit
			),
			1
		)
	)
	var stamp_images := _get_resized_stamp_images(
		mask_data,
		stamp_size,
		flip_x,
		flip_y,
		rotation_quarters
	)
	var chunk_mask_top := (
		chunk_index
		* terrain_manager.config.chunk_height_cells
		* profile.mask_pixels_per_cell
	)
	var destination_position := Vector2i(
		floori(
			full_stamp_position.x
				* mask_pixels_per_world_unit
		),
		floori(
			full_stamp_position.y
				* mask_pixels_per_world_unit
			) - chunk_mask_top
	)
	# The mask artwork carries its crack strokes as opaque pixels, and blending
	# them onto a row that holds no terrain would turn a stroke into solid
	# ground. Clip the stamp to the real strata so cracks can never draw against
	# open sky above the surface or past the world floor.
	var source_rect := Rect2i(Vector2i.ZERO, stamp_size)
	var config := terrain_manager.config
	var surface_local_y := (
		config.initial_surface_row * profile.mask_pixels_per_cell
		- chunk_mask_top
	)
	if destination_position.y < surface_local_y:
		var clipped_rows := surface_local_y - destination_position.y
		if clipped_rows >= source_rect.size.y:
			return false
		source_rect.position.y += clipped_rows
		source_rect.size.y -= clipped_rows
		destination_position.y = surface_local_y
	var floor_local_y := (
		(config.get_bottom_surface_row() + 1) * profile.mask_pixels_per_cell
		- chunk_mask_top
	)
	if destination_position.y + source_rect.size.y > floor_local_y:
		source_rect.size.y = floor_local_y - destination_position.y
		if source_rect.size.y <= 0:
			return false

	# Each mask image packs crack strokes in luminance and terrain coverage in
	# alpha. blend_rect alpha-composites, so blending strokes straight in also
	# RAISES alpha, and a stamp overlapping an older opening would re-solidify
	# pixels that opening already cleared - leaving black cracks floating inside
	# open rock.
	#
	# So blend into a stamp-sized copy of what is already there, then blit that
	# result back masked by the pre-blend alpha. Strokes darken only rock that is
	# still solid, and no already-cleared pixel is ever touched. The two copies
	# are bounded by the stamp, not the chunk, and are freed with the call.
	var affected_rect := Rect2i(destination_position, source_rect.size)
	var solid_before_stamp := destination.get_region(affected_rect)
	var shaded_region := destination.get_region(affected_rect)
	shaded_region.blend_rect(
		stamp_images.fracture_source,
		source_rect,
		Vector2i.ZERO
	)
	destination.blit_rect_mask(
		shaded_region,
		solid_before_stamp,
		Rect2i(Vector2i.ZERO, source_rect.size),
		destination_position
	)

	# Only now carve this stamp's own cavity.
	destination.blit_rect_mask(
		stamp_images.transparent_source,
		stamp_images.erase_mask,
		source_rect,
		destination_position
	)
	return true


## Maps the mask's real transparent cavity through its authored orientation.
## The normalized result lets every big or small stamp share one exact visible
## center and edge, even after a non-square texture is flipped or quarter-turned.
func _get_oriented_transparent_bounds(
	mask_data: HoleMaskData,
	flip_x: bool,
	flip_y: bool,
	rotation_quarters: int
) -> Rect2:
	var source_size := Vector2(mask_data.erase_mask.get_size())
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return Rect2()
	var bounds := Rect2(
		Vector2(mask_data.transparent_bounds.position) / source_size,
		Vector2(mask_data.transparent_bounds.size) / source_size
	)
	if flip_x:
		bounds.position.x = 1.0 - bounds.end.x
	if flip_y:
		bounds.position.y = 1.0 - bounds.end.y
	match posmod(rotation_quarters, 4):
		1:
			bounds = Rect2(
				Vector2(1.0 - bounds.end.y, bounds.position.x),
				Vector2(bounds.size.y, bounds.size.x)
			)
		2:
			bounds.position = Vector2.ONE - bounds.end
		3:
			bounds = Rect2(
				Vector2(bounds.position.y, 1.0 - bounds.end.x),
				Vector2(bounds.size.y, bounds.size.x)
			)
	return bounds


## Reuses resized, mirrored, and quarter-turned masks for web performance.
func _get_resized_stamp_images(
	mask_data: HoleMaskData,
	stamp_size: Vector2i,
	flip_x: bool,
	flip_y: bool,
	rotation_quarters: int
) -> ResizedStampImages:
	var orientation_flags := (
		(1 if flip_x else 0)
		| (2 if flip_y else 0)
		| (posmod(rotation_quarters, 4) << 2)
	)
	var cache_key := Vector4i(
		mask_data.cache_id,
		stamp_size.x,
		stamp_size.y,
		orientation_flags
	)
	var can_cache := (
		resized_stamp_cache_limit > 0
		and stamp_size.x * stamp_size.y
			<= resized_stamp_cache_max_pixels
	)
	var cached_images: ResizedStampImages = _resized_stamp_cache.get(
		cache_key
	)
	if cached_images != null:
		if can_cache:
			_resized_stamp_cache_order.erase(cache_key)
			_resized_stamp_cache_order.append(cache_key)
		return cached_images

	var stamp_images := ResizedStampImages.new()
	# blit_rect_mask cuts wherever the mask alpha is not exactly zero, so an
	# interpolated erase mask cuts its whole feathered skirt at full strength and
	# the opening creeps about a third of a pixel past the drawing - taking the
	# inked rim, which is only about one pixel wide at this scale, with it.
	# Nearest keeps the cut on the silhouette the artist drew. Nothing is lost by
	# it: the cut was already hard-edged, because that same test discards every
	# partial value bilinear produced.
	stamp_images.erase_mask = _transform_stamp_image(
		mask_data.erase_mask,
		stamp_size,
		flip_x,
		flip_y,
		rotation_quarters,
		Image.INTERPOLATE_NEAREST
	)
	stamp_images.fracture_source = _transform_stamp_image(
		mask_data.fracture_source,
		stamp_size,
		flip_x,
		flip_y,
		rotation_quarters,
		Image.INTERPOLATE_BILINEAR
	)
	stamp_images.transparent_source = Image.create(
		stamp_size.x,
		stamp_size.y,
		false,
		Image.FORMAT_LA8
	)
	stamp_images.transparent_source.fill(EMPTY_MASK_COLOR)

	if not can_cache:
		_resized_stamp_cache[cache_key] = stamp_images
		_temporary_stamp_cache_keys.append(cache_key)
		return stamp_images
	while _resized_stamp_cache_order.size() >= resized_stamp_cache_limit:
		var expired_key: Vector4i = (
			_resized_stamp_cache_order.pop_front()
		)
		_resized_stamp_cache.erase(expired_key)
	_resized_stamp_cache[cache_key] = stamp_images
	_resized_stamp_cache_order.append(cache_key)
	return stamp_images


## Releases one-operation oversized masks after all touched chunks reuse them.
func _clear_temporary_stamp_cache() -> void:
	for cache_key: Vector4i in _temporary_stamp_cache_keys:
		_resized_stamp_cache.erase(cache_key)
	_temporary_stamp_cache_keys.clear()


## Applies one cached orientation identically to the hole and its drawn cracks.
## The cavity and the strokes take different filters for the reason given at the
## call site, so the caller states which one it wants rather than sharing a
## default that is only correct for one of them.
func _transform_stamp_image(
	source: Image,
	stamp_size: Vector2i,
	flip_x: bool,
	flip_y: bool,
	rotation_quarters: int,
	interpolation: Image.Interpolation
) -> Image:
	var transformed := source.duplicate()
	transformed.resize(
		stamp_size.x,
		stamp_size.y,
		interpolation
	)
	if flip_x:
		transformed.flip_x()
	if flip_y:
		transformed.flip_y()
	var normalized_rotation := posmod(rotation_quarters, 4)
	if normalized_rotation == 1:
		transformed.rotate_90(CLOCKWISE)
	elif normalized_rotation == 2:
		transformed.flip_x()
		transformed.flip_y()
	elif normalized_rotation == 3:
		transformed.rotate_90(COUNTERCLOCKWISE)
	if transformed.get_size() != stamp_size:
		transformed.resize(
			stamp_size.x,
			stamp_size.y,
			interpolation
		)
	return transformed


## Precomputes stable organic openings around every chamber ceiling.
func _prepare_chamber_transition_stamps() -> void:
	_chamber_stamps_by_chunk.clear()
	var encounter_config := terrain_manager.encounter_config
	if encounter_config == null or chamber_circle_count <= 0:
		return

	var config := terrain_manager.config
	var cell_size := float(config.terrain_cell_world_size)
	var minimum_radius_cells := mini(
		chamber_circle_min_radius_cells,
		chamber_circle_max_radius_cells
	)
	var maximum_radius_cells := maxi(
		chamber_circle_min_radius_cells,
		chamber_circle_max_radius_cells
	)
	for encounter in encounter_config.encounters:
		if encounter == null:
			continue
		var encounter_depth := encounter.resolve_depth(
			config.total_run_depth
		)
		var chamber_bounds := (
			encounter_config.get_chamber_horizontal_bounds(
				encounter_depth - 1,
				config.total_run_depth,
				config.terrain_width_cells
			)
		)
		var chamber_left_cells := float(chamber_bounds.x)
		var chamber_right_cells := float(chamber_bounds.y)
		var chamber_ceiling_row := (
			config.initial_surface_row
			+ encounter_depth
			- encounter_config.chamber_height_rows
		)
		var random := RandomNumberGenerator.new()
		random.seed = encounter_depth * 104_729 + 17
		for circle_index in range(chamber_circle_count):
			var ceiling_progress := (
				(float(circle_index) + 0.5)
				/ float(chamber_circle_count)
			)
			var center_cell_x := lerpf(
				chamber_left_cells,
				chamber_right_cells,
				ceiling_progress
			)
			center_cell_x += random.randf_range(
				-chamber_circle_jitter_cells,
				chamber_circle_jitter_cells
			)
			var center_cell_y := (
				float(chamber_ceiling_row)
				+ random.randf_range(
					-chamber_circle_jitter_cells,
					chamber_circle_jitter_cells
				)
			)
			var stamp := ImpactStamp.new()
			stamp.center = Vector2(
				center_cell_x * cell_size,
				center_cell_y * cell_size
			)
			stamp.core_radius = float(random.randi_range(
				minimum_radius_cells,
				maximum_radius_cells
			)) * cell_size
			stamp.use_big_hole = (
				stamp.core_radius * 2.0
				>= float(profile.big_hole_minimum_size)
			)
			stamp.flip_x = random.randi_range(0, 1) == 1
			stamp.flip_y = random.randi_range(0, 1) == 1
			stamp.rotation_quarters = random.randi_range(0, 3)
			stamp.size_variation = random.randf_range(0.92, 1.08)

			for chunk_index in _get_stamp_chunk_indices(stamp):
				var chunk_stamps: Array = _chamber_stamps_by_chunk.get(
					chunk_index,
					[]
				)
				chunk_stamps.append(stamp)
				_chamber_stamps_by_chunk[chunk_index] = chunk_stamps


## Caches authored mask images and their transparent bounds.
func _prepare_hole_masks() -> void:
	_small_mask_data.clear()
	_big_mask_data.clear()
	_resized_stamp_cache.clear()
	_resized_stamp_cache_order.clear()
	var prepared_masks: Dictionary[String, HoleMaskData] = {}
	for layer_index in range(profile.get_layer_count()):
		if (
			profile.keep_back_layer_solid
			and layer_index == profile.get_gameplay_layer_count() - 1
		):
			# The immutable backing layer is never stamped, so preparing two
			# masks for it only delays the opening scene.
			_small_mask_data.append(null)
			_big_mask_data.append(null)
			continue
		var line_scale := profile.get_fracture_line_layer_scale(layer_index)
		for use_big_hole in [false, true]:
			var texture := profile.get_hole_mask(
				layer_index,
				use_big_hole
			)
			var cache_key := "%s|%.4f" % [
				texture.resource_path if texture != null else "",
				line_scale,
			]
			if not prepared_masks.has(cache_key):
				prepared_masks[cache_key] = _create_hole_mask_data(
					texture,
					prepared_masks.size(),
					line_scale
				)
			var mask_data := prepared_masks[cache_key]
			if use_big_hole:
				_big_mask_data.append(mask_data)
			else:
				_small_mask_data.append(mask_data)


## Loads one mask and measures the opening the artist authored.
## The authored strokes are collected here but printed by _write_fracture_lines,
## which needs the finished cavity before it can tell a rim outline from a crack.
func _create_hole_mask_data(
	texture: Texture2D,
	cache_id: int,
	fracture_line_scale: float
) -> HoleMaskData:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null

	var mask_width := image.get_width()
	var mask_height := image.get_height()
	var minimum := Vector2i(mask_width, mask_height)
	var maximum := Vector2i(-1, -1)
	var content_minimum := minimum
	var content_maximum := maximum
	var erase_mask := Image.create(
		mask_width,
		mask_height,
		false,
		Image.FORMAT_LA8
	)
	erase_mask.fill(EMPTY_MASK_COLOR)
	var fracture_source := Image.create(
		mask_width,
		mask_height,
		false,
		Image.FORMAT_LA8
	)
	# Carry the stroke value in the unwritten pixels too. Coverage lives in
	# alpha, and the per-hit resize interpolates luminance and alpha separately,
	# so a white backing would mix a shrinking stroke toward white before its
	# coverage ever reached blend_rect - fading the same line twice.
	var line_value := 1.0 - profile.fracture_line_strength
	fracture_source.fill(Color(line_value, line_value, line_value, 0.0))
	var writes_fracture_lines := fracture_line_scale > 0.0
	# Three temporary buffers the size of one authored mask. They are local to
	# this call and released with it; nothing accumulates per hit or per chunk.
	var cell_count := mask_width * mask_height
	var cavity_cells := PackedByteArray()
	cavity_cells.resize(cell_count)
	var stroke_cells := PackedByteArray()
	var stroke_coverage := PackedFloat32Array()
	if writes_fracture_lines:
		stroke_cells.resize(cell_count)
		stroke_coverage.resize(cell_count)
	for source_y in range(mask_height):
		var cell_row := source_y * mask_width
		for source_x in range(mask_width):
			var source_pixel := image.get_pixel(source_x, source_y)
			if source_pixel.a > profile.transparent_alpha_threshold:
				if not writes_fracture_lines:
					continue
				var luminance := (
					source_pixel.r * 0.2126
					+ source_pixel.g * 0.7152
					+ source_pixel.b * 0.0722
				)
				var line_alpha := clampf(
					(
						profile.fracture_line_luminance_threshold
						- luminance
					)
					/ maxf(
						profile.fracture_line_luminance_threshold,
						0.001
					),
					0.0,
					1.0
				) * source_pixel.a
				if line_alpha > 0.0:
					stroke_cells[cell_row + source_x] = 1
					stroke_coverage[cell_row + source_x] = line_alpha
					content_minimum.x = mini(content_minimum.x, source_x)
					content_minimum.y = mini(content_minimum.y, source_y)
					content_maximum.x = maxi(content_maximum.x, source_x)
					content_maximum.y = maxi(content_maximum.y, source_y)
				continue
			minimum.x = mini(minimum.x, source_x)
			minimum.y = mini(minimum.y, source_y)
			maximum.x = maxi(maximum.x, source_x)
			maximum.y = maxi(maximum.y, source_y)
			content_minimum.x = mini(content_minimum.x, source_x)
			content_minimum.y = mini(content_minimum.y, source_y)
			content_maximum.x = maxi(content_maximum.x, source_x)
			content_maximum.y = maxi(content_maximum.y, source_y)
			cavity_cells[cell_row + source_x] = 1
			erase_mask.set_pixel(
				source_x,
				source_y,
				SOLID_MASK_COLOR
			)
	if maximum.x < minimum.x or maximum.y < minimum.y:
		return null
	if writes_fracture_lines:
		_write_fracture_lines(
			fracture_source,
			cavity_cells,
			stroke_cells,
			stroke_coverage,
			mask_width,
			mask_height,
			fracture_line_scale
		)

	# Remove opaque margins before any per-hit resize. Mirroring the crop around
	# the authored image center retains the exact flip and quarter-turn pivot.
	var crop_minimum := Vector2i(
		mini(
			content_minimum.x,
			mask_width - 1 - content_maximum.x
		),
		mini(
			content_minimum.y,
			mask_height - 1 - content_maximum.y
		)
	)
	var crop_maximum := Vector2i(
		mask_width - 1 - crop_minimum.x,
		mask_height - 1 - crop_minimum.y
	)
	var crop_rect := Rect2i(
		crop_minimum,
		crop_maximum - crop_minimum + Vector2i.ONE
	)
	erase_mask = erase_mask.get_region(crop_rect)
	fracture_source = fracture_source.get_region(crop_rect)

	var data := HoleMaskData.new()
	data.erase_mask = erase_mask
	data.fracture_source = fracture_source
	data.cache_id = cache_id
	data.transparent_bounds = Rect2i(
		minimum - crop_rect.position,
		maximum - minimum + Vector2i.ONE
	)
	return data


## Prints one mask's authored strokes into its fracture channel.
##
## The artwork draws two different things: an inked outline hugging its own
## cavity, and loose scribbles standing off in the surrounding rock. The outline
## is the broken edge and matches the characters' inked silhouettes, so it is
## kept; the scribbles read as marks lying on top of the dirt, so anything
## further out than the authored reach fades away. Each configured cuttable
## stratum prints the stroke against its own smaller opening, while strata
## behind the authored depth print nothing.
func _write_fracture_lines(
	fracture_source: Image,
	cavity_cells: PackedByteArray,
	stroke_cells: PackedByteArray,
	stroke_coverage: PackedFloat32Array,
	mask_width: int,
	mask_height: int,
	line_scale: float
) -> void:
	# Fading across the last quarter of the reach keeps the cutoff off any single
	# stroke, so a kept line never ends in a hard stub.
	const REACH_FADE_RATIO: float = 0.75
	var cavity_distance := _build_distance_field(
		cavity_cells,
		mask_width,
		mask_height
	)
	var reach := maxf(profile.fracture_rim_reach_px, 1.0)
	var line_value := 1.0 - profile.fracture_line_strength
	for source_y in range(mask_height):
		var cell_row := source_y * mask_width
		for source_x in range(mask_width):
			var cell_index := cell_row + source_x
			if stroke_cells[cell_index] == 0:
				continue
			var line_alpha := (
				stroke_coverage[cell_index]
				* line_scale
				* (
					1.0
					- smoothstep(
						reach * REACH_FADE_RATIO,
						reach,
						cavity_distance[cell_index]
					)
				)
			)
			if line_alpha <= 0.004:
				continue
			fracture_source.set_pixel(
				source_x,
				source_y,
				Color(
					line_value,
					line_value,
					line_value,
					line_alpha
				)
			)


## Returns each cell's chamfer distance in pixels to the nearest seeded cell.
## Two linear sweeps keep this proportional to the mask area, so it can run
## while masks load without the neighbourhood search a exact metric would need.
func _build_distance_field(
	seed_cells: PackedByteArray,
	mask_width: int,
	mask_height: int
) -> PackedFloat32Array:
	const UNREACHED_DISTANCE: float = 1.0e9
	const DIAGONAL_STEP: float = 1.4142135
	var field := PackedFloat32Array()
	field.resize(seed_cells.size())
	for cell_index in range(seed_cells.size()):
		field[cell_index] = (
			0.0
			if seed_cells[cell_index] != 0
			else UNREACHED_DISTANCE
		)
	for source_y in range(mask_height):
		var cell_row := source_y * mask_width
		var above_row := cell_row - mask_width
		for source_x in range(mask_width):
			var cell_index := cell_row + source_x
			var best := field[cell_index]
			if best == 0.0:
				continue
			if source_x > 0:
				best = minf(best, field[cell_index - 1] + 1.0)
			if source_y > 0:
				best = minf(best, field[above_row + source_x] + 1.0)
				if source_x > 0:
					best = minf(
						best,
						field[above_row + source_x - 1] + DIAGONAL_STEP
					)
				if source_x < mask_width - 1:
					best = minf(
						best,
						field[above_row + source_x + 1] + DIAGONAL_STEP
					)
			field[cell_index] = best
	for source_y in range(mask_height - 1, -1, -1):
		var cell_row := source_y * mask_width
		var below_row := cell_row + mask_width
		for source_x in range(mask_width - 1, -1, -1):
			var cell_index := cell_row + source_x
			var best := field[cell_index]
			if best == 0.0:
				continue
			if source_x < mask_width - 1:
				best = minf(best, field[cell_index + 1] + 1.0)
			if source_y < mask_height - 1:
				best = minf(best, field[below_row + source_x] + 1.0)
				if source_x > 0:
					best = minf(
						best,
						field[below_row + source_x - 1] + DIAGONAL_STEP
					)
				if source_x < mask_width - 1:
					best = minf(
						best,
						field[below_row + source_x + 1] + DIAGONAL_STEP
					)
			field[cell_index] = best
	return field


## Returns the cached opening for one layer and impact size.
func _get_hole_mask_data(
	layer_index: int,
	use_big_hole: bool
) -> HoleMaskData:
	var mask_data := (
		_big_mask_data
		if use_big_hole
		else _small_mask_data
	)
	if layer_index < 0 or layer_index >= mask_data.size():
		return null
	return mask_data[layer_index]


## Builds one shader material for a terrain stratum.
func _create_layer_material(
	layer_index: int,
	world_origin: Vector2,
	chunk_world_size: Vector2
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = LAYER_SHADER
	var fill_texture := profile.get_fill_texture(layer_index)
	material.set_shader_parameter(&"fill_texture", fill_texture)
	material.set_shader_parameter(
		&"use_fill_texture",
		fill_texture != null
	)
	material.set_shader_parameter(
		&"layer_tint",
		profile.layer_tints[layer_index]
	)
	material.set_shader_parameter(&"world_origin", world_origin)
	material.set_shader_parameter(
		&"chunk_world_size",
		chunk_world_size
	)
	material.set_shader_parameter(
		&"fill_texture_world_size",
		profile.fill_texture_world_size
	)
	material.set_shader_parameter(
		&"use_strata_texture",
		profile.layer_dirt_texture_enabled
	)
	material.set_shader_parameter(
		&"dirt_detail_scale",
		profile.layer_dirt_detail_scales_px[layer_index]
	)
	material.set_shader_parameter(
		&"dirt_detail_color",
		profile.layer_dirt_detail_colors[layer_index]
	)
	material.set_shader_parameter(
		&"dirt_variance_strength",
		profile.layer_dirt_variance_strengths[layer_index]
	)
	material.set_shader_parameter(
		&"rock_density",
		profile.layer_rock_densities[layer_index]
	)
	material.set_shader_parameter(
		&"rock_detail_strength",
		profile.layer_rock_detail_strengths[layer_index]
	)
	# Drawn rock scatter. One atlas is shared by every stratum; the palette and
	# density change per layer so surface stones read tan and bedrock reads dark.
	material.set_shader_parameter(&"rock_texture", profile.rock_texture)
	material.set_shader_parameter(
		&"use_rock_texture",
		profile.rock_texture != null
	)
	material.set_shader_parameter(
		&"rock_atlas_count",
		profile.rock_atlas_count
	)
	material.set_shader_parameter(
		&"rock_body_color",
		profile.get_rock_body_color(layer_index)
	)
	material.set_shader_parameter(
		&"rock_outline_color",
		profile.get_rock_outline_color(layer_index)
	)
	material.set_shader_parameter(
		&"rock_cluster_world_px",
		profile.rock_cluster_world_px
	)
	material.set_shader_parameter(
		&"rock_cluster_coverage",
		profile.rock_cluster_coverage
	)
	material.set_shader_parameter(
		&"rock_loner_scale",
		profile.rock_loner_scale
	)
	material.set_shader_parameter(
		&"rock_depth_ramp_world_px",
		profile.rock_depth_ramp_world_px
	)
	material.set_shader_parameter(
		&"rock_depth_ramp_gain",
		profile.rock_depth_ramp_gain
	)
	material.set_shader_parameter(
		&"use_rock_shadows",
		profile.rock_shadows_enabled
	)
	material.set_shader_parameter(
		&"rock_shadow_strength",
		profile.rock_shadow_strength
	)
	material.set_shader_parameter(
		&"fracture_shade_color",
		profile.fracture_shade_color
	)
	# The darkest stroke value this stratum can hold, which is what the shader
	# normalises recovered ink against. Strata past fracture_line_layer_depth
	# print nothing, so this is zero for them and the recovery block is skipped.
	material.set_shader_parameter(
		&"fracture_line_ink",
		profile.fracture_line_strength
			* profile.get_fracture_line_layer_scale(layer_index)
	)
	material.set_shader_parameter(
		&"sharpen_fracture_lines",
		profile.fracture_line_sharpen
	)
	material.set_shader_parameter(
		&"fracture_line_gain",
		profile.fracture_line_gain
	)
	material.set_shader_parameter(
		&"fracture_line_weight_world_px",
		profile.fracture_line_weight_world_px
	)
	material.set_shader_parameter(
		&"dirt_shade_steps",
		profile.dirt_shade_steps
	)
	material.set_shader_parameter(
		&"sharpen_mask_edges",
		profile.sharpen_mask_edges
	)
	material.set_shader_parameter(
		&"use_layer_edge_shading",
		profile.layer_edge_shading_enabled
	)
	material.set_shader_parameter(
		&"edge_shade_world_pixels",
		profile.edge_shade_world_pixels
	)
	material.set_shader_parameter(
		&"edge_shade_strength",
		profile.edge_shade_strength
	)
	material.set_shader_parameter(
		&"edge_light_strength",
		profile.edge_light_strength
	)
	# Only the foreground stratum grows the surface. Deeper layers keep their
	# bare rock, and a mined opening removes grass and crust along with it.
	material.set_shader_parameter(
		&"use_surface_grass",
		profile.surface_grass_enabled and layer_index == 0
	)
	material.set_shader_parameter(
		&"surface_world_y",
		float(terrain_manager.config.initial_surface_row)
			* float(terrain_manager.config.terrain_cell_world_size)
	)
	material.set_shader_parameter(
		&"surface_band_world_px",
		profile.surface_band_world_px
	)
	material.set_shader_parameter(
		&"grass_height_world_px",
		profile.grass_height_world_px
	)
	material.set_shader_parameter(&"grass_texture", profile.grass_texture)
	material.set_shader_parameter(
		&"use_grass_texture",
		profile.grass_texture != null
	)
	material.set_shader_parameter(
		&"grass_clump_count",
		profile.grass_clump_count
	)
	material.set_shader_parameter(
		&"grass_cell_aspect",
		profile.grass_cell_aspect
	)
	material.set_shader_parameter(
		&"grass_cell_world_px",
		profile.grass_cell_world_px
	)
	material.set_shader_parameter(
		&"grass_support_probe_px",
		profile.grass_support_probe_px
	)
	material.set_shader_parameter(
		&"crust_depth_world_px",
		profile.crust_depth_world_px
	)
	material.set_shader_parameter(&"crust_color", profile.crust_color)
	material.set_shader_parameter(
		&"crust_strength",
		profile.crust_strength
	)
	material.set_shader_parameter(
		&"stratum_depth",
		float(mini(
			layer_index,
			profile.get_gameplay_layer_count() - 1
		))
			/ float(maxi(
				profile.get_gameplay_layer_count() - 1,
				1
			))
	)
	return material


## Uploads only the layer textures modified by the current operation.
func _upload_chunk_masks(
	chunk: TerrainChunkVisual,
	changed_layers: int
) -> void:
	for layer_index in range(chunk.mask_images.size()):
		if changed_layers & (1 << layer_index) == 0:
			continue
		chunk.mask_textures[layer_index].update(
			chunk.mask_images[layer_index]
		)


## Returns a conservative area containing every layer opening.
func _get_stamp_broad_rect(stamp: ImpactStamp) -> Rect2:
	var gameplay_layer_count := profile.get_gameplay_layer_count()
	if not stamp.narrow_path_points.is_empty():
		var narrow_growth := (
			float(terrain_manager.config.terrain_cell_world_size) * 0.75
			+ float(profile.core_hole_padding)
			+ float(
				mini(profile.rim_width, 4)
				* maxi(gameplay_layer_count - 1, 0)
			)
		)
		var narrow_offset := 0.0
		for layer_index in range(gameplay_layer_count):
			narrow_offset = maxf(
				narrow_offset,
				profile.get_layer_impact_offset(layer_index).length()
					* 0.25
			)
		return stamp.damage_bounds.grow(
			narrow_growth + narrow_offset
		)
	var layer_growth := (
		profile.core_hole_padding
		+ profile.rim_width * maxi(gameplay_layer_count - 1, 0)
	)
	var maximum_offset := 0.0
	for layer_index in range(gameplay_layer_count):
		maximum_offset = maxf(
			maximum_offset,
			profile.get_layer_impact_offset(layer_index).length()
		)
	var broad_radius := (
		stamp.core_radius
		+ float(layer_growth)
		+ maximum_offset
	)
	var broad_rect := Rect2(
		stamp.center - Vector2.ONE * broad_radius,
		Vector2.ONE * broad_radius * 2.0
	)
	if stamp.damage_bounds.has_area():
		broad_rect = broad_rect.merge(stamp.damage_bounds)
	return broad_rect


## Returns every chunk touched by a stamp's visible or logical bounds.
func _get_stamp_chunk_indices(stamp: ImpactStamp) -> Array[int]:
	var broad_rect := _get_stamp_broad_rect(stamp)
	var chunk_height := _get_chunk_world_size().y
	var first_chunk := maxi(
		floori(broad_rect.position.y / chunk_height),
		0
	)
	var last_chunk := maxi(
		floori(
			(broad_rect.end.y - 0.001) / chunk_height
		),
		first_chunk
	)
	var chunk_indices: Array[int] = []
	for chunk_index in range(first_chunk, last_chunk + 1):
		chunk_indices.append(chunk_index)
	return chunk_indices


## Returns one chunk's dimensions in terrain-local units.
func _get_chunk_world_size() -> Vector2:
	var config := terrain_manager.config
	return Vector2(
		config.terrain_width_cells
			* config.terrain_cell_world_size,
		config.chunk_height_cells
			* config.terrain_cell_world_size
	)


## Returns one chunk's editable mask dimensions.
func _get_chunk_mask_size() -> Vector2i:
	var config := terrain_manager.config
	return Vector2i(
		config.terrain_width_cells
			* profile.mask_pixels_per_cell,
		config.chunk_height_cells
			* profile.mask_pixels_per_cell
	)


## Returns the chunk index containing a terrain row.
func _world_row_to_chunk(world_row: int) -> int:
	return floori(
		float(world_row)
		/ float(terrain_manager.config.chunk_height_cells)
	)


## Connects one signal without creating a duplicate route.
func _connect_once(source_signal: Signal, target: Callable) -> void:
	if not source_signal.is_connected(target):
		source_signal.connect(target)
