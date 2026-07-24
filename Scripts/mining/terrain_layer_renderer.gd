class_name TerrainLayerRenderer
extends Node2D

## Streams layered terrain art and reveals organic openings at mining impacts.
## Visual cutouts intentionally retain one colored backdrop over logical holes.
## Normal hits stop at orange; big hits may expose the solid brown back layer.
## Chamber antialiasing may differ by less than one logical cell at a side edge;
## neither mismatch affects support. Press F3 to compare the logical opening.

class TerrainChunkVisual:
	var root: Node2D
	var mask_images: Array[Image] = []
	var mask_textures: Array[ImageTexture] = []


class HoleMaskData:
	var erase_mask: Image
	var transparent_bounds: Rect2i
	var cache_id: int


class ImpactStamp:
	var center: Vector2
	var core_radius: float
	var damage_bounds: Rect2
	var narrow_path_points: PackedVector2Array
	var use_big_hole: bool
	var flip_x: bool
	var flip_y: bool
	var offset_rotation: float


class ResizedStampImages:
	var erase_mask: Image
	var transparent_source: Image


const LAYER_SHADER: Shader = preload(
	"res://Shaders/terrain_layer.gdshader"
)
const SOLID_MASK_COLOR := Color.WHITE
const EMPTY_MASK_COLOR := Color.TRANSPARENT
# A landing samples at most 64 rows (256 mask pixels at the default profile).
# The query runs once per landing and never grows with run depth or hit count.
const MAX_SUPPORT_SCAN_ROWS: int = 64

@export_category("References")
@export var terrain_manager: TerrainManager
@export var profile: TerrainLayerProfile

@export_category("Impact Reveal")
## Layer four remains covered until the active hit reaches this combo.
@export_range(1, 100, 1) var deepest_layer_combo_threshold: int = 7

@export_category("Web Performance")
## Limits reusable resized masks so repeated hit sizes avoid image allocations.
@export_range(0, 48, 1) var resized_stamp_cache_limit: int = 12

@export_category("Chamber Integration")
## Places overlapping organic openings across each encounter-room ceiling.
@export_range(0, 32, 1) var chamber_circle_count: int = 8
@export_range(1, 16, 1) var chamber_circle_min_radius_cells: int = 5
@export_range(1, 16, 1) var chamber_circle_max_radius_cells: int = 8
@export_range(0.0, 8.0, 0.5) var chamber_circle_jitter_cells: float = 3.0

@export_category("Debug")
## Toggles the logical opening overlay without affecting terrain presentation.
@export var logical_overlay_key: Key = KEY_F3
@export var logical_overlay_color := Color(0.2, 1.0, 0.35, 0.45)

var _active_chunks: Dictionary[int, TerrainChunkVisual] = {}
var _impact_stamps_by_chunk: Dictionary = {}
var _chamber_stamps_by_chunk: Dictionary = {}
var _small_mask_data: Array[HoleMaskData] = []
var _big_mask_data: Array[HoleMaskData] = []
var _resized_stamp_cache: Dictionary[Vector4i, ResizedStampImages] = {}
var _resized_stamp_cache_order: Array[Vector4i] = []
var _current_view_x: float
var _current_view_y: float
var _loaded_first_chunk: int = -1
var _loaded_last_chunk: int = -1
var _latest_foreground_opening_rect := Rect2()
var _latest_support_world_position := Vector2(NAN, NAN)
var _show_logical_overlay: bool = false
var _active_impact_combo: int = 0


## Connects terrain events and loads the initial visible strata.
func _ready() -> void:
	if terrain_manager == null or profile == null:
		push_error(
			"TerrainLayerRenderer requires terrain_manager and profile."
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
	horizontal_direction: int
) -> void:
	if destroyed_cells.is_empty():
		return
	var stamp := _create_impact_stamp(
		destroyed_cells,
		horizontal_direction
	)
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

	var base_mask := _build_chunk_base_mask(chunk_index, false)
	var back_layer_mask: Image
	if profile.keep_back_layer_solid:
		back_layer_mask = _build_chunk_base_mask(chunk_index, true)
	var chunk_world_size := _get_chunk_world_size()
	var world_origin := Vector2(
		0.0,
		float(chunk_index) * chunk_world_size.y
	)
	for layer_index in range(layer_count):
		var is_solid_back_layer := (
			profile.keep_back_layer_solid
			and layer_index == layer_count - 1
		)
		var source_mask := (
			back_layer_mask
			if is_solid_back_layer
			else base_mask
		)
		chunk.mask_images.append(source_mask.duplicate())

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
		sprite.material = _create_layer_material(
			layer_index,
			world_origin,
			chunk_world_size
		)
		chunk.root.add_child(sprite)
		chunk.mask_textures.append(mask_texture)
	_active_chunks[chunk_index] = chunk


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
	preserve_chamber_backdrop: bool
) -> Image:
	var config := terrain_manager.config
	var mask_cell_size := profile.mask_pixels_per_cell
	var mask_size := _get_chunk_mask_size()
	var image := Image.create(
		mask_size.x,
		mask_size.y,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(EMPTY_MASK_COLOR)
	var chunk_start_row := chunk_index * config.chunk_height_cells
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
	is_narrow_path: bool = false
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
	stamp.center = damage_rect.get_center()
	stamp.damage_bounds = damage_rect
	if is_narrow_path:
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
	stamp.offset_rotation = (
		float(posmod(variation_hash, 4))
		* PI * 0.5
	)
	return stamp


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


## Punches offset circular holes so every stratum has a distinct rim.
func _apply_impact_stamp(
	chunk: TerrainChunkVisual,
	chunk_index: int,
	stamp: ImpactStamp
) -> int:
	var layer_count := profile.get_layer_count()
	var changed_layers := 0
	for layer_index in range(layer_count):
		if (
			profile.keep_back_layer_solid
			and layer_index == layer_count - 1
		):
			continue
		var is_layer_covering_backdrop := (
			profile.keep_back_layer_solid
			and layer_index == layer_count - 2
		)
		# Orange remains the decorative tunnel backdrop below combo seven.
		# At or above the combo gate, the size threshold still prevents a
		# physically small secondary path from exposing the brown back wall.
		if is_layer_covering_backdrop and not stamp.use_big_hole:
			continue
		var layer_changed := false
		var mask_data := _get_hole_mask_data(
			layer_index,
			stamp.use_big_hole
		)
		if mask_data == null:
			if layer_changed:
				changed_layers |= 1 << layer_index
			continue
		if not stamp.narrow_path_points.is_empty():
			if _punch_narrow_path(
				chunk.mask_images[layer_index],
				chunk_index,
				stamp,
				layer_index,
				mask_data
			):
				layer_changed = true
			if layer_changed:
				changed_layers |= 1 << layer_index
			continue
		var opening_rect := _get_layer_opening_rect(
			stamp,
			layer_index
		)
		if _punch_hole(
			chunk.mask_images[layer_index],
			chunk_index,
			opening_rect,
			mask_data,
			stamp.flip_x,
			stamp.flip_y
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
	var layers_below := profile.get_layer_count() - layer_index - 1
	var opening_growth := (
		profile.core_hole_padding
		+ profile.rim_width * layers_below
	)
	var opening_radius := stamp.core_radius + float(opening_growth)
	var layer_offset := (
		profile.get_layer_impact_offset(layer_index)
		.rotated(stamp.offset_rotation)
	)
	if stamp.flip_x:
		layer_offset.x *= -1.0
	if stamp.flip_y:
		layer_offset.y *= -1.0
	var opening_center := stamp.center + layer_offset
	# Ordinary mining stamps expand far enough to cover every damaged cell.
	# Authored chamber stamps intentionally have no logical damage bounds; an
	# empty Rect2 sits at the world origin. Measuring its corners would make
	# the opening radius grow with depth and request enormous mask textures.
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
	var first_mask_y: int = maxi(
		landing_world_row * profile.mask_pixels_per_cell,
		0
	)
	var sample_count: int = (
		MAX_SUPPORT_SCAN_ROWS * profile.mask_pixels_per_cell
	)
	var saw_opening: bool = false
	for sample_offset: int in range(sample_count):
		var world_mask_y: int = first_mask_y + sample_offset
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
			saw_opening = true
			continue
		if not saw_opening:
			continue

		var support_world_y: float = (
			(float(world_mask_y) + 0.5)
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


## Traces a thin organic opening along one branching damage path.
func _punch_narrow_path(
	destination: Image,
	chunk_index: int,
	stamp: ImpactStamp,
	layer_index: int,
	mask_data: HoleMaskData
) -> bool:
	var layer_count := profile.get_layer_count()
	var layers_below := layer_count - layer_index - 1
	var opening_radius := (
		float(terrain_manager.config.terrain_cell_world_size) * 0.75
		+ float(profile.core_hole_padding)
		+ float(mini(profile.rim_width, 4) * layers_below)
	)
	var layer_offset := (
		profile.get_layer_impact_offset(layer_index)
		.rotated(stamp.offset_rotation)
		* 0.25
	)
	if stamp.flip_x:
		layer_offset.x *= -1.0
	if stamp.flip_y:
		layer_offset.y *= -1.0

	var changed := false
	for path_point in stamp.narrow_path_points:
		var opening_center := path_point + layer_offset
		if _punch_hole(
			destination,
			chunk_index,
			Rect2(
				opening_center - Vector2.ONE * opening_radius,
				Vector2.ONE * opening_radius * 2.0
			),
			mask_data,
			stamp.flip_x,
			stamp.flip_y
		):
			changed = true
	return changed


## Clears the transparent part of one authored mask from a chunk layer.
func _punch_hole(
	destination: Image,
	chunk_index: int,
	opening_world_rect: Rect2,
	mask_data: HoleMaskData,
	flip_x: bool,
	flip_y: bool
) -> bool:
	var source_size := Vector2(mask_data.erase_mask.get_size())
	var source_bounds := Rect2(mask_data.transparent_bounds)
	if source_bounds.size.x <= 0.0 or source_bounds.size.y <= 0.0:
		return false

	var full_stamp_size := Vector2(
		opening_world_rect.size.x
		* source_size.x / source_bounds.size.x,
		opening_world_rect.size.y
		* source_size.y / source_bounds.size.y
	)
	var full_stamp_position := (
		opening_world_rect.position
		- Vector2(source_bounds.position)
		* full_stamp_size / source_size
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
		flip_y
	)
	var chunk_mask_top := (
		chunk_index
		* terrain_manager.config.chunk_height_cells
		* profile.mask_pixels_per_cell
	)
	destination.blit_rect_mask(
		stamp_images.transparent_source,
		stamp_images.erase_mask,
		Rect2i(Vector2i.ZERO, stamp_size),
		Vector2i(
			floori(
				full_stamp_position.x
				* mask_pixels_per_world_unit
			),
			floori(
				full_stamp_position.y
				* mask_pixels_per_world_unit
			) - chunk_mask_top
		)
	)
	return true


## Reuses the images needed for repeated hit sizes and orientations.
func _get_resized_stamp_images(
	mask_data: HoleMaskData,
	stamp_size: Vector2i,
	flip_x: bool,
	flip_y: bool
) -> ResizedStampImages:
	var flip_flags := (1 if flip_x else 0) | (2 if flip_y else 0)
	var cache_key := Vector4i(
		mask_data.cache_id,
		stamp_size.x,
		stamp_size.y,
		flip_flags
	)
	var cached_images: ResizedStampImages = _resized_stamp_cache.get(
		cache_key
	)
	if cached_images != null:
		_resized_stamp_cache_order.erase(cache_key)
		_resized_stamp_cache_order.append(cache_key)
		return cached_images

	var stamp_images := ResizedStampImages.new()
	stamp_images.erase_mask = mask_data.erase_mask.duplicate()
	stamp_images.erase_mask.resize(
		stamp_size.x,
		stamp_size.y,
		Image.INTERPOLATE_BILINEAR
	)
	if flip_x:
		stamp_images.erase_mask.flip_x()
	if flip_y:
		stamp_images.erase_mask.flip_y()
	stamp_images.transparent_source = Image.create(
		stamp_size.x,
		stamp_size.y,
		false,
		Image.FORMAT_RGBA8
	)
	stamp_images.transparent_source.fill(EMPTY_MASK_COLOR)

	if resized_stamp_cache_limit <= 0:
		return stamp_images
	while _resized_stamp_cache_order.size() >= resized_stamp_cache_limit:
		var expired_key: Vector4i = (
			_resized_stamp_cache_order.pop_front()
		)
		_resized_stamp_cache.erase(expired_key)
	_resized_stamp_cache[cache_key] = stamp_images
	_resized_stamp_cache_order.append(cache_key)
	return stamp_images


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
			stamp.offset_rotation = (
				float(random.randi_range(0, 3)) * PI * 0.5
			)

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
	for layer_index in range(profile.get_layer_count()):
		_small_mask_data.append(
			_create_hole_mask_data(
				profile.get_hole_mask(layer_index, false),
				layer_index * 2
			)
		)
		_big_mask_data.append(
			_create_hole_mask_data(
				profile.get_hole_mask(layer_index, true),
				layer_index * 2 + 1
			)
		)


## Loads one mask and measures the opening the artist authored.
func _create_hole_mask_data(
	texture: Texture2D,
	cache_id: int
) -> HoleMaskData:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null

	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i(-1, -1)
	var erase_mask := Image.create(
		image.get_width(),
		image.get_height(),
		false,
		Image.FORMAT_RGBA8
	)
	erase_mask.fill(EMPTY_MASK_COLOR)
	for source_y in range(image.get_height()):
		for source_x in range(image.get_width()):
			if (
				image.get_pixel(source_x, source_y).a
				> profile.transparent_alpha_threshold
			):
				continue
			minimum.x = mini(minimum.x, source_x)
			minimum.y = mini(minimum.y, source_y)
			maximum.x = maxi(maximum.x, source_x)
			maximum.y = maxi(maximum.y, source_y)
			erase_mask.set_pixel(
				source_x,
				source_y,
				SOLID_MASK_COLOR
			)
	if maximum.x < minimum.x or maximum.y < minimum.y:
		return null

	var data := HoleMaskData.new()
	data.erase_mask = erase_mask
	data.cache_id = cache_id
	data.transparent_bounds = Rect2i(
		minimum,
		maximum - minimum + Vector2i.ONE
	)
	return data


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
	if not stamp.narrow_path_points.is_empty():
		var narrow_growth := (
			float(terrain_manager.config.terrain_cell_world_size) * 0.75
			+ float(profile.core_hole_padding)
			+ float(
				mini(profile.rim_width, 4)
				* maxi(profile.get_layer_count() - 1, 0)
			)
		)
		var narrow_offset := 0.0
		for layer_index in range(profile.get_layer_count()):
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
		+ profile.rim_width * maxi(profile.get_layer_count() - 1, 0)
	)
	var maximum_offset := 0.0
	for layer_index in range(profile.get_layer_count()):
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
