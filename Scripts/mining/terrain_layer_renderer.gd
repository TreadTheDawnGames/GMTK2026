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
	var mask_texture_tiles: Array[Array] = []
	var dirty_mask_tiles: PackedInt32Array = PackedInt32Array()
	var layer_revisions: PackedInt32Array = PackedInt32Array()
	var layer_sprites: Array[Sprite2D] = []
	## One bit per stratum still drawing the shared intact mask. A shared stratum
	## owns no image and no texture, so streaming untouched rock allocates
	## nothing; the bit is cleared the moment a stamp needs to write into it.
	var shared_layers: int = 0
	## A layer that just left any shared base must create private GPU tiles on
	## its next publish. This bit prevents an update from mutating its sibling.
	var needs_private_texture: int = 0


class HoleMaskData:
	var erase_mask: Image
	var fracture_source: Image
	var has_fracture_lines: bool = false
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
	var include_fracture_lines: bool = true
	## Seeds this hit's per-stratum orientation and size jitter. Kept on the
	## stamp so a chunk streamed back in redraws the exact same rims.
	var variation_hash: int = 0
	## Exact logical inputs shared by prediction and authoritative damage. Only
	## ordinary primary impacts set it; aftershocks always use the cold path.
	var preparation_key: String = ""


class PreparedLayerPatch:
	var image: Image
	var destination_position: Vector2i
	var source_revision: int
	var dirty_tile_bits: int


class ImpactRasterWork:
	var chunk: TerrainChunkVisual
	var chunk_index: int
	var stamp: ImpactStamp
	var layer_index: int
	var raster_band_index: int
	var raster_band_count: int
	var prepare_only: bool = false
	var finish_preparation: bool = false
	var prepared_patch: PreparedLayerPatch
	var image_preparation


class ImpactStampPreparation:
	var stamp: ImpactStamp
	var layer_index: int
	var chunk: TerrainChunkVisual
	var chunk_index: int = -1
	var raster_band_index: int = 0
	var raster_band_count: int = 1
	var prepares_patch: bool = false
	var image_preparation


class ChunkTexturePublishWork:
	var chunk: TerrainChunkVisual
	var chunk_index: int
	var layer_indices: PackedInt32Array


const TerrainStampImageCache = preload(
	"res://Scripts/mining/terrain_stamp_image_cache.gd"
)
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
# Retired chunk nodes are kept so streaming reuses their sprites and fully
# configured materials instead of rebuilding both per crossed chunk boundary.
# The window is three to five chunks tall, so a handful covers every crossing.
const CHUNK_VISUAL_POOL_LIMIT: int = 4
# A structural chunk needs at most two distinct base masks and six tiled
# textures. One spare chunk's storage is retained so adjacent streaming updates
# existing buffers instead of allocating multi-megabyte images at the boundary.
const CHUNK_MASK_IMAGE_POOL_LIMIT: int = 4
const CHUNK_MASK_TEXTURE_POOL_LIMIT: int = 12
# Deferred web raster work is capped and pooled. The 192 slots cover the
# configured fully-stacked hit (currently under 150 jobs). If mining ever fills
# them, the oldest single layer completes before another is accepted, so memory
# cannot grow with hit count and the renderer never drops an opening.
const MAX_PENDING_IMPACT_WORK_ITEMS: int = 192
# A run has far fewer authored structural groups than this. Stale work is
# skipped if its chunk streams out, and descriptors are recycled after use.
const MAX_PENDING_CHUNK_TEXTURE_PUBLISH_ITEMS: int = 192
const MAX_PREDICTED_IMPACT_CANDIDATES: int = 5
# Every terrain mask is published as three 128-cell GPU tiles. The usual mining
# x=192 lies inside the middle tile rather than on a seam, and 16 px/cell stays
# below 4096 while leaving one sampler free on minimum WebGL hardware.
const MASK_HORIZONTAL_TILE_COUNT: int = 3
const MASK_TILE_GUTTER_PIXELS: int = 1
const ALL_MASK_TILES_DIRTY: int = (
	(1 << MASK_HORIZONTAL_TILE_COUNT) - 1
)
# The authored hole sheets are 512x384. Upsampling their packed erase/ink
# channels once gives the shader finer diagonal coverage without raising every
# streamed terrain mask or repeating interpolation on each predicted hit.
const AUTHORED_MASK_SOURCE_SUPERSAMPLE: int = 2
# Authored fracture spurs are optional detail inside the shader's continuous cut
# outline. Cap them at a 32-cell radius so a theoretical fully-stacked impact
# cannot turn sparse line art into a full-stamp blend whose area grows 4x.
const MAX_FRACTURE_RADIUS_CELLS: float = 32.0
# High-density transform work is its own queue item. Raster bands remove
# repeated setup while the deferred benchmark protects the unchanged 7 ms
# atomic ceiling; their height remains benchmark-protected at every density.
# Twelve-pixel profiling leaves enough atomic headroom for 192 rows. The larger
# band removes repeated clipping/blit setup while the 7 ms benchmark still
# guards the final band plus its one dirty-tile upload.
const MAX_IMPACT_RASTER_BAND_HEIGHT: int = 192
@export_category("References")
@export var terrain_manager: TerrainManager
@export var profile: TerrainLayerProfile

@export_category("Impact Reveal")
## Layer four remains covered until the active hit reaches this combo.
@export_range(1, 100, 1) var deepest_layer_combo_threshold: int = 7

@export_category("Web Performance")
## Maximum CPU time spent starting queued mask layers in one rendered frame.
## A layer already in progress completes atomically so textures never tear.
@export_range(1.0, 16.0, 0.5) var web_impact_frame_budget_ms: float = 3.0
## Limits reusable resized masks so repeated hit sizes avoid image allocations.
@export_range(0, 48, 1) var resized_stamp_cache_limit: int = 48
## Oversized combo openings are one-off and must not occupy the reusable cache.
@export_range(1, 1_048_576, 1) var resized_stamp_cache_max_pixels: int = 65_536

@export_category("Chamber Integration")
## The sub-cell logical taper is the shipped chamber edge. Runtime decorative
## circles are disabled because each one replays impact rasters while streaming;
## authored sculpt contours provide variation without softening that sharp rim.
@export_range(0, 32, 1) var chamber_circle_count: int = 0
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
# Nodes, sprites, and materials of chunks the view has left, waiting to be
# refilled by the next chunk it reaches.
var _chunk_visual_pool: Array[TerrainChunkVisual] = []
var _chunk_mask_image_pool: Array[Image] = []
var _chunk_mask_texture_pool: Array[ImageTexture] = []
# One solid mask every untouched stratum draws. Sharing it is what makes an
# ordinary streamed chunk cost no image allocation and no texture upload.
var _pristine_mask_image: Image
var _pristine_mask_texture: ImageTexture
var _pristine_mask_size := Vector2i.ZERO
# The three upload images are reused for every stratum. Their one-pixel gutters
# duplicate the neighboring CPU columns so shader filtering stays continuous at
# all tile seams; memory is bounded by one tiled copy of a chunk mask.
var _mask_upload_images: Array[Image] = []
# One authored room rasterized at mask resolution, keyed by its sculpt and
# indexed by stratum plus one, where index zero is the shared logical shape.
var _sculpt_mask_images: Dictionary[CutsceneTerrainSculpt, Array] = {}
# Historical stamps are retained so review mode can rebuild old terrain.
# Growth is bounded by the configured run and accepted hit count; only the
# viewport-sized _active_chunks set owns Image and ImageTexture allocations.
var _impact_stamps_by_chunk: Dictionary = {}
var _chamber_stamps_by_chunk: Dictionary = {}
var _small_mask_data: Array[HoleMaskData] = []
var _big_mask_data: Array[HoleMaskData] = []
var _stamp_image_cache := TerrainStampImageCache.new()
# Stores at most resized_stamp_cache_limit transformed hole-and-line pairs,
# each no larger than resized_stamp_cache_max_pixels; least-recently-used
# entries are pruned before another pair is inserted.
var _resized_stamp_cache: Dictionary:
	get:
		return _stamp_image_cache.entries
# Two sequential LA8 scratch bands replace per-band Image.get_region
# allocations. They grow only to one chunk width x the 128-row work ceiling
# and every consumed rectangle is overwritten before blending.
var _fracture_band_scratch: Image
var _solid_band_scratch: Image
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
# Web hits queue one bounded work item per visible chunk and stratum. Completed
# items are recycled, so steady-state mining adds no work-object allocations.
var _pending_impact_work: Array[ImpactRasterWork] = []
var _pending_impact_work_head: int = 0
var _impact_work_pool: Array[ImpactRasterWork] = []
var _pending_chunk_texture_publishes: Array[ChunkTexturePublishWork] = []
var _pending_chunk_texture_publish_head: int = 0
var _chunk_texture_publish_pool: Array[ChunkTexturePublishWork] = []
var _defer_impact_rasterization: bool = false
# Five timing targets produce at most five candidates, each with one transform
# per writable gameplay stratum. A new target batch replaces this bounded queue;
# completed images live in the cache's equally bounded prepared generation.
var _pending_stamp_preparation: Array[ImpactStampPreparation] = []
var _pending_stamp_preparation_head: int = 0
var _stamp_preparation_pool: Array[ImpactStampPreparation] = []
var _preparation_candidate_count: int = 0
# Candidate patches are keyed by exact swing plan, chunk, and layer. Partial
# patches never enter this dictionary; cancellation drops their bounded working
# images, while completed patches live only until contact or target replacement.
var _prepared_layer_patches: Dictionary[String, PreparedLayerPatch] = {}
var _preparing_layer_patches: Dictionary[String, PreparedLayerPatch] = {}


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
		_prepare_sculpt_masks()
		_on_view_position_changed(terrain_manager.get_view_position())
		return
	if terrain_manager == null or profile == null:
		push_error(
			"TerrainLayerRenderer requires terrain_manager and profile."
		)
		return
	# One scheduler now owns impact work on every platform. Native/editor used
	# to run an immediate legacy path, which hid web-only queue bugs and made
	# the same sharp mask produce a contact hitch during local playtesting.
	_defer_impact_rasterization = true
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
	_prepare_sculpt_masks()
	_on_view_position_changed(terrain_manager.get_view_position())


## Spreads prediction and browser mask rasterization across rendered frames.
## Prediction only fills CPU caches; gameplay cells and visible textures remain
## unchanged until the real impact signal arrives.
func _process(_delta: float) -> void:
	var has_preparation := (
		_pending_stamp_preparation_head
		< _pending_stamp_preparation.size()
	)
	var has_impact_work := (
		_defer_impact_rasterization
		and _pending_impact_work_head < _pending_impact_work.size()
	)
	var has_chunk_texture_publish := (
		_pending_chunk_texture_publish_head
		< _pending_chunk_texture_publishes.size()
	)
	if (
		not has_preparation
		and not has_impact_work
		and not has_chunk_texture_publish
	):
		return
	var frame_started_at: int = Time.get_ticks_usec()
	var frame_budget_usec: int = roundi(
		web_impact_frame_budget_ms * 1000.0
	)
	# Committed terrain always wins the shared budget. Authoritative preparation
	# work is inserted into this same queue immediately before its raster bands,
	# so a partial prediction can never delay an older visible hit.
	while (
		_defer_impact_rasterization
		and _pending_impact_work_head < _pending_impact_work.size()
	):
		_process_next_pending_impact_work()
		if (
			Time.get_ticks_usec() - frame_started_at
			>= frame_budget_usec
		):
			return
	_compact_pending_impact_work()
	# Streamed structure is already in CPU memory and may be below the visible
	# margin. Publish one bounded copy-on-write group at a time before spending
	# spare terrain time on predictions.
	while (
		_pending_chunk_texture_publish_head
		< _pending_chunk_texture_publishes.size()
	):
		_process_next_chunk_texture_publish()
		if (
			Time.get_ticks_usec() - frame_started_at
			>= frame_budget_usec
		):
			return
	_compact_pending_chunk_texture_publishes()
	# Only unused terrain time prepares future candidates. If contact arrives
	# mid-calculation, the authoritative queue above takes ownership next frame.
	while (
		_pending_stamp_preparation_head
		< _pending_stamp_preparation.size()
	):
		_prepare_next_pending_stamp_layer()
		if (
			Time.get_ticks_usec() - frame_started_at
			>= frame_budget_usec
		):
			break
	_compact_pending_stamp_preparation()


## Rasterizes every authored room before the run starts. Reaching one mid-run
## then costs a clipped copy instead of the build, which is what keeps a room's
## chunk streaming in at the same cost as the rock around it.
func _prepare_sculpt_masks() -> void:
	for placement in terrain_manager.get_sculpt_placements():
		_get_sculpt_mask_image(placement.sculpt, -1)
		if not placement.sculpt.has_layer_masks():
			continue
		for layer_index in range(profile.get_gameplay_layer_count()):
			_get_sculpt_mask_image(placement.sculpt, layer_index)


## Captures the combo used by synchronous damage stamps for one resolved hit.
func _on_dig_presentation_started(combo: int) -> void:
	_active_impact_combo = maxi(combo, 0)


## Replaces unfinished candidate work. Exact success keeps completed candidate
## images so contact can promote the matching keys without recomputing them.
func _on_dig_visuals_preparation_started(
	keep_completed: bool
) -> void:
	for work_index in range(
		_pending_stamp_preparation_head,
		_pending_stamp_preparation.size()
	):
		var work := _pending_stamp_preparation[work_index]
		work.stamp = null
		work.chunk = null
		work.chunk_index = -1
		work.raster_band_index = 0
		work.raster_band_count = 1
		work.prepares_patch = false
		work.image_preparation = null
		if (
			_stamp_preparation_pool.size()
			< MAX_PENDING_IMPACT_WORK_ITEMS
		):
			_stamp_preparation_pool.append(work)
	_pending_stamp_preparation.clear()
	_pending_stamp_preparation_head = 0
	_preparation_candidate_count = 0
	_stamp_image_cache.begin_preparation(not keep_completed)
	_preparing_layer_patches.clear()
	if not keep_completed:
		_prepared_layer_patches.clear()


## Adds one of at most five fresh primary openings to the current target batch.
## Existing holes or encounter geometry may shorten authoritative damage; the
## actual stamp then uses a different key and the queued contact path prepares it.
func _on_dig_visuals_preparation_requested(
	start_cell: Vector2i,
	depth_rows: int,
	half_width_cells: int,
	target_cell_x: int,
	combo: int
) -> void:
	if (
		depth_rows <= 0
		or _preparation_candidate_count
			>= MAX_PREDICTED_IMPACT_CANDIDATES
	):
		return
	var config := terrain_manager.config
	var safe_target_cell_x := clampi(
		target_cell_x,
		0,
		config.terrain_width_cells - 1
	)
	var safe_half_width := maxi(half_width_cells, 0)
	var tunnel_end_row := mini(
		start_cell.y + depth_rows,
		config.get_bottom_surface_row()
	)
	var row_count := tunnel_end_row - start_cell.y
	if row_count <= 0:
		return
	var row_left := maxi(safe_target_cell_x - safe_half_width, 0)
	var row_right := mini(
		safe_target_cell_x + safe_half_width,
		config.terrain_width_cells - 1
	)
	var first_left := mini(row_left, start_cell.x)
	var first_right := maxi(row_right, start_cell.x)
	var predicted_cell_count := (
		first_right - first_left + 1
		+ maxi(row_count - 1, 0) * (row_right - row_left + 1)
	)
	var stamp := _create_ordinary_impact_stamp_from_bounds(
		Vector2i(first_left, start_cell.y),
		Vector2i(first_right, tunnel_end_row - 1),
		predicted_cell_count,
		signi(safe_target_cell_x - start_cell.x),
		safe_target_cell_x,
		maxi(combo, 0)
	)
	_preparation_candidate_count += 1
	for layer_index in range(profile.get_gameplay_layer_count()):
		if not _can_apply_impact_stamp_layer(stamp, layer_index):
			continue
		var work := _obtain_stamp_preparation_work()
		work.stamp = stamp
		work.layer_index = layer_index
		_pending_stamp_preparation.append(work)


## Prepares either one exact transform or one band of a composited candidate
## patch. Only the completed patch is published to the candidate dictionary.
func _prepare_next_pending_stamp_layer() -> void:
	if (
		_pending_stamp_preparation_head
		>= _pending_stamp_preparation.size()
	):
		return
	var work := _pending_stamp_preparation[
		_pending_stamp_preparation_head
	]
	_pending_stamp_preparation_head += 1
	var stamp := work.stamp
	var layer_index := work.layer_index
	if work.prepares_patch:
		_prepare_stamp_layer_patch_band(work)
		return
	if not _advance_speculative_stamp_images(work):
		_pending_stamp_preparation_head -= 1
		return
	for chunk_index in _get_stamp_chunk_indices(stamp):
		if not _active_chunks.has(chunk_index):
			continue
		var chunk: TerrainChunkVisual = _active_chunks[chunk_index]
		_queue_stamp_layer_patch_preparation(
			stamp,
			layer_index,
			chunk,
			chunk_index
		)


func _advance_speculative_stamp_images(
	work: ImpactStampPreparation
) -> bool:
	if work.image_preparation == null:
		work.image_preparation = _create_stamp_image_preparation(
			work.stamp,
			work.layer_index,
			true
		)
	if work.image_preparation == null:
		return true
	return _stamp_image_cache.advance_image_preparation(
		work.image_preparation,
		MAX_IMPACT_RASTER_BAND_HEIGHT
	)


func _advance_committed_stamp_images(
	work: ImpactRasterWork
) -> bool:
	if work.image_preparation == null:
		work.image_preparation = _create_stamp_image_preparation(
			work.stamp,
			work.layer_index,
			false
		)
	if work.image_preparation == null:
		return true
	return _stamp_image_cache.advance_image_preparation(
		work.image_preparation,
		MAX_IMPACT_RASTER_BAND_HEIGHT
	)


## Creates one destination-agnostic transform state shared by speculative and
## authoritative queues. Each caller advances it under the same frame budget.
func _create_stamp_image_preparation(
	stamp: ImpactStamp,
	layer_index: int,
	is_speculative: bool
) -> Variant:
	var mask_data := _get_hole_mask_data(
		layer_index,
		stamp.use_big_hole
	)
	if mask_data == null:
		return null
	var opening_rect := _get_layer_opening_rect(stamp, layer_index)
	var layer_variation := _get_layer_stamp_variation(
		stamp,
		layer_index
	)
	var full_stamp_rect := _get_full_stamp_world_rect(
		opening_rect,
		mask_data,
		layer_variation.x == 1,
		layer_variation.y == 1,
		layer_variation.z
	)
	if not full_stamp_rect.has_area():
		return null
	return _stamp_image_cache.start_image_preparation(
		mask_data.cache_id,
		mask_data.erase_mask,
		mask_data.fracture_source,
		mask_data.has_fracture_lines
			and stamp.include_fracture_lines,
		_get_stamp_pixel_size(full_stamp_rect.size),
		layer_variation.x == 1,
		layer_variation.y == 1,
		layer_variation.z,
		is_speculative,
		AUTHORED_MASK_SOURCE_SUPERSAMPLE
	)


## Reuses one bounded descriptor for transform and patch preparation.
func _obtain_stamp_preparation_work() -> ImpactStampPreparation:
	var work: ImpactStampPreparation = (
		_stamp_preparation_pool.pop_back()
		if not _stamp_preparation_pool.is_empty()
		else ImpactStampPreparation.new()
	)
	work.chunk_index = -1
	work.raster_band_index = 0
	work.raster_band_count = 1
	work.prepares_patch = false
	work.image_preparation = null
	return work


## Queues the exact candidate pixels for one visible chunk/layer. Completed
## patches at the current terrain revision are retained across the exact swing.
func _queue_stamp_layer_patch_preparation(
	stamp: ImpactStamp,
	layer_index: int,
	chunk: TerrainChunkVisual,
	chunk_index: int
) -> void:
	var patch_key := _get_prepared_layer_patch_key(
		stamp,
		chunk_index,
		layer_index
	)
	var completed_patch: PreparedLayerPatch = (
		_prepared_layer_patches.get(patch_key)
	)
	if (
		completed_patch != null
		and completed_patch.source_revision
			== chunk.layer_revisions[layer_index]
	):
		return
	var affected_rect := _get_stamp_layer_chunk_mask_rect(
		stamp,
		layer_index,
		chunk_index
	)
	if not affected_rect.has_area():
		return
	var raster_band_count := maxi(
		ceili(
			float(affected_rect.size.y)
			/ float(MAX_IMPACT_RASTER_BAND_HEIGHT)
		),
		1
	)
	for raster_band_index in range(raster_band_count):
		var work := _obtain_stamp_preparation_work()
		work.stamp = stamp
		work.layer_index = layer_index
		work.chunk = chunk
		work.chunk_index = chunk_index
		work.raster_band_index = raster_band_index
		work.raster_band_count = raster_band_count
		work.prepares_patch = true
		_pending_stamp_preparation.append(work)


## Builds one immutable patch from a terrain revision. If contact or streaming
## changes that revision mid-build, the partial image is discarded.
func _prepare_stamp_layer_patch_band(
	work: ImpactStampPreparation
) -> void:
	if (
		_active_chunks.get(work.chunk_index) != work.chunk
		or work.stamp.preparation_key.is_empty()
	):
		return
	var patch_key := _get_prepared_layer_patch_key(
		work.stamp,
		work.chunk_index,
		work.layer_index
	)
	var patch: PreparedLayerPatch = _preparing_layer_patches.get(
		patch_key
	)
	if patch == null:
		var affected_rect := _get_stamp_layer_chunk_mask_rect(
			work.stamp,
			work.layer_index,
			work.chunk_index
		)
		if not affected_rect.has_area():
			return
		# Leaving the shared pristine CPU image is itself density-scaled work.
		# Do it during wind-up without changing any pixels or bound textures;
		# ownership then remains bounded to this active chunk/layer on a miss.
		_make_layer_writable(work.chunk, work.layer_index)
		patch = PreparedLayerPatch.new()
		patch.image = work.chunk.mask_images[
			work.layer_index
		].get_region(affected_rect)
		patch.destination_position = affected_rect.position
		patch.source_revision = work.chunk.layer_revisions[
			work.layer_index
		]
		patch.dirty_tile_bits = _get_stamp_dirty_tile_bits(
			work.stamp,
			work.layer_index
		)
		_preparing_layer_patches[patch_key] = patch
	if (
		patch.source_revision
		!= work.chunk.layer_revisions[work.layer_index]
	):
		_preparing_layer_patches.erase(patch_key)
		return
	var mask_data := _get_hole_mask_data(
		work.layer_index,
		work.stamp.use_big_hole
	)
	if mask_data == null:
		return
	var opening_rect := _get_layer_opening_rect(
		work.stamp,
		work.layer_index
	)
	var layer_variation := _get_layer_stamp_variation(
		work.stamp,
		work.layer_index
	)
	_punch_hole(
		patch.image,
		work.chunk_index,
		opening_rect,
		mask_data,
		layer_variation.x == 1,
		layer_variation.y == 1,
		layer_variation.z,
		work.stamp.include_fracture_lines,
		work.raster_band_index,
		work.raster_band_count,
		patch.destination_position
	)
	if work.raster_band_index == work.raster_band_count - 1:
		_preparing_layer_patches.erase(patch_key)
		_prepared_layer_patches[patch_key] = patch


func _get_prepared_layer_patch_key(
	stamp: ImpactStamp,
	chunk_index: int,
	layer_index: int
) -> String:
	return "%s|%d|%d" % [
		stamp.preparation_key,
		chunk_index,
		layer_index,
	]


## Returns a candidate only while both its logical plan and source terrain
## revision still match the authoritative chunk.
func _get_valid_prepared_layer_patch(
	stamp: ImpactStamp,
	chunk: TerrainChunkVisual,
	chunk_index: int,
	layer_index: int
) -> PreparedLayerPatch:
	if stamp.preparation_key.is_empty():
		return null
	var patch: PreparedLayerPatch = _prepared_layer_patches.get(
		_get_prepared_layer_patch_key(
			stamp,
			chunk_index,
			layer_index
		)
	)
	if (
		patch == null
		or patch.source_revision != chunk.layer_revisions[layer_index]
	):
		return null
	return patch


## Recycles completed candidate descriptors; transformed images remain in the
## cache's bounded prepared generation until contact or a target regeneration.
func _compact_pending_stamp_preparation() -> void:
	if _pending_stamp_preparation_head <= 0:
		return
	for work_index in range(_pending_stamp_preparation_head):
		var work := _pending_stamp_preparation[work_index]
		work.stamp = null
		work.chunk = null
		work.chunk_index = -1
		work.raster_band_index = 0
		work.raster_band_count = 1
		work.prepares_patch = false
		work.image_preparation = null
		if (
			_stamp_preparation_pool.size()
			< MAX_PENDING_IMPACT_WORK_ITEMS
		):
			_stamp_preparation_pool.append(work)
	_pending_stamp_preparation = _pending_stamp_preparation.slice(
		_pending_stamp_preparation_head
	)
	_pending_stamp_preparation_head = 0


## Saves and applies one organic opening for newly destroyed terrain.
func _on_terrain_damaged(
	destroyed_cells: Array[Vector2i],
	horizontal_direction: int,
	impact_origin_cell: Vector2i,
	destroyed_bounds: Rect2i
) -> void:
	if destroyed_cells.is_empty():
		return
	# Contact owns the queue now. Completed speculative keys remain available for
	# promotion, while unfinished candidates cannot run ahead of real terrain.
	_on_dig_visuals_preparation_started(true)
	var stamp := _create_impact_stamp(
		destroyed_cells,
		horizontal_direction,
		false,
		impact_origin_cell.x,
		destroyed_bounds
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
	var chunk_indices_by_stamp: Array[Array] = []
	for stamp in stamps:
		var stamp_chunk_indices: Array[int] = _register_impact_stamp(
			stamp
		)
		chunk_indices_by_stamp.append(stamp_chunk_indices)
		for chunk_index in stamp_chunk_indices:
			affected_chunk_lookup[chunk_index] = true
	if _defer_impact_rasterization:
		var layer_count: int = profile.get_gameplay_layer_count()
		var queued_authoritative_preparation := false
		var prepared_patches_by_stamp: Array[Dictionary] = []
		prepared_patches_by_stamp.resize(stamps.size())
		for stamp_index in range(stamps.size()):
			prepared_patches_by_stamp[stamp_index] = {}
		# The authoritative transform is a first-class queue item immediately
		# before fallback raster bands. Fully prepared layers skip both costs and
		# promote their immutable terrain patch instead.
		for stamp_index in range(stamps.size()):
			var stamp := stamps[stamp_index]
			if not stamp.narrow_path_points.is_empty():
				continue
			var preparation_layers: Array[int] = []
			var prepared_patches: Dictionary = (
				prepared_patches_by_stamp[stamp_index]
			)
			for layer_index in range(layer_count):
				if not _can_apply_impact_stamp_layer(stamp, layer_index):
					continue
				for chunk_index in chunk_indices_by_stamp[stamp_index]:
					if not _active_chunks.has(chunk_index):
						continue
					var chunk: TerrainChunkVisual = _active_chunks[
						chunk_index
					]
					var prepared_patch := (
						_get_valid_prepared_layer_patch(
							stamp,
							chunk,
							chunk_index,
							layer_index
						)
					)
					if prepared_patch == null:
						preparation_layers.append(layer_index)
						break
					prepared_patches[
						chunk_index * layer_count + layer_index
					] = prepared_patch
			for preparation_index in range(preparation_layers.size()):
				queued_authoritative_preparation = true
				_append_impact_work(
					stamp,
					preparation_layers[preparation_index],
					null,
					-1,
					0,
					1,
					true,
					preparation_index
						== preparation_layers.size() - 1
				)
		for chunk_index in affected_chunk_lookup:
			if not _active_chunks.has(chunk_index):
				continue
			var chunk: TerrainChunkVisual = _active_chunks[chunk_index]
			for stamp_index in range(stamps.size()):
				var stamp := stamps[stamp_index]
				if (
					chunk_index
					not in chunk_indices_by_stamp[stamp_index]
				):
					continue
				for layer_index in range(layer_count):
					# Do not allocate queue capacity for strata the production
					# stamp contract will reject. At high mask density these
					# no-op bands otherwise create artificial queue backpressure.
					if not _can_apply_impact_stamp_layer(
						stamp,
						layer_index
					):
						continue
					var prepared_patch: PreparedLayerPatch = (
						prepared_patches_by_stamp[stamp_index].get(
							chunk_index * layer_count + layer_index
						)
					)
					if prepared_patch != null:
						_append_impact_work(
							stamp,
							layer_index,
							chunk,
							chunk_index,
							0,
							1,
							false,
							false,
							prepared_patch
						)
						continue
					var raster_band_count := 1
					if stamp.narrow_path_points.is_empty():
						var affected_rect := (
							_get_stamp_layer_chunk_mask_rect(
								stamp,
								layer_index,
								chunk_index
							)
						)
						if not affected_rect.has_area():
							continue
						raster_band_count = maxi(
							ceili(
								float(affected_rect.size.y)
								/ float(
									MAX_IMPACT_RASTER_BAND_HEIGHT
								)
							),
							1
						)
					for raster_band_index in range(raster_band_count):
						_append_impact_work(
							stamp,
							layer_index,
							chunk,
							chunk_index,
							raster_band_index,
							raster_band_count
						)
		_prepared_layer_patches.clear()
		_preparing_layer_patches.clear()
		if not queued_authoritative_preparation:
			_stamp_image_cache.discard_prepared()
		return
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
	_stamp_image_cache.discard_prepared()


## Appends one bounded authoritative item, applying queue backpressure without
## dropping either preparation or pixels.
func _append_impact_work(
	stamp: ImpactStamp,
	layer_index: int,
	chunk: TerrainChunkVisual,
	chunk_index: int,
	raster_band_index: int,
	raster_band_count: int,
	prepare_only: bool = false,
	finish_preparation: bool = false,
	prepared_patch: PreparedLayerPatch = null
) -> void:
	while (
		_pending_impact_work.size()
		- _pending_impact_work_head
		>= MAX_PENDING_IMPACT_WORK_ITEMS
	):
		_process_next_pending_impact_work()
		_compact_pending_impact_work()
	var work: ImpactRasterWork = (
		_impact_work_pool.pop_back()
		if not _impact_work_pool.is_empty()
		else ImpactRasterWork.new()
	)
	work.chunk = chunk
	work.chunk_index = chunk_index
	work.stamp = stamp
	work.layer_index = layer_index
	work.raster_band_index = raster_band_index
	work.raster_band_count = raster_band_count
	work.prepare_only = prepare_only
	work.finish_preparation = finish_preparation
	work.prepared_patch = prepared_patch
	work.image_preparation = null
	_pending_impact_work.append(work)


## Completes one queued stratum and publishes only that texture. Work targeting
## a chunk that streamed out is discarded because loading it again replays the
## registered stamp history.
func _process_next_pending_impact_work() -> void:
	if _pending_impact_work_head >= _pending_impact_work.size():
		return
	var work := _pending_impact_work[_pending_impact_work_head]
	_pending_impact_work_head += 1
	if work.prepared_patch != null:
		if _active_chunks.get(work.chunk_index) == work.chunk:
			_make_layer_writable(work.chunk, work.layer_index)
			if (
				work.prepared_patch.source_revision
				== work.chunk.layer_revisions[work.layer_index]
			):
				work.chunk.mask_images[
					work.layer_index
				].blit_rect(
					work.prepared_patch.image,
					Rect2i(
						Vector2i.ZERO,
						work.prepared_patch.image.get_size()
					),
					work.prepared_patch.destination_position
				)
				work.chunk.dirty_mask_tiles[work.layer_index] |= (
					work.prepared_patch.dirty_tile_bits
				)
				work.chunk.layer_revisions[work.layer_index] += 1
				_publish_layer_texture(work.chunk, work.layer_index)
			else:
				# A non-mining terrain mutation invalidated the candidate after
				# queue construction. This rare path stays authoritative.
				_apply_impact_stamp_layer(
					work.chunk,
					work.chunk_index,
					work.stamp,
					work.layer_index
				)
				_publish_layer_texture(work.chunk, work.layer_index)
	elif work.prepare_only:
		if not _advance_committed_stamp_images(work):
			_pending_impact_work_head -= 1
			return
		if work.finish_preparation:
			_stamp_image_cache.discard_prepared()
	elif _active_chunks.get(work.chunk_index) == work.chunk:
		_apply_impact_stamp_layer(
			work.chunk,
			work.chunk_index,
			work.stamp,
			work.layer_index,
			work.raster_band_index,
			work.raster_band_count
		)
		if work.raster_band_index == work.raster_band_count - 1:
			_publish_layer_texture(work.chunk, work.layer_index)
	work.chunk = null
	work.stamp = null
	work.raster_band_index = 0
	work.raster_band_count = 1
	work.prepare_only = false
	work.finish_preparation = false
	work.prepared_patch = null
	work.image_preparation = null
	if _impact_work_pool.size() < MAX_PENDING_IMPACT_WORK_ITEMS:
		_impact_work_pool.append(work)


## Prunes completed queue slots and releases temporary oversized stamp images
## as soon as every pending stratum has consumed them.
func _compact_pending_impact_work() -> void:
	if _pending_impact_work_head <= 0:
		return
	if _pending_impact_work_head >= _pending_impact_work.size():
		_pending_impact_work.clear()
		_pending_impact_work_head = 0
		_clear_temporary_stamp_cache()
		return
	if _pending_impact_work_head < 32:
		return
	_pending_impact_work = _pending_impact_work.slice(
		_pending_impact_work_head
	)
	_pending_impact_work_head = 0


## Drops every streamed chunk and its stamp history so the next refresh draws
## intact terrain again. The editor preview needs this because moving a test
## impact has to un-break the rock the previous position broke.
func rebuild_all_chunks() -> void:
	_impact_stamps_by_chunk.clear()
	for work_index in range(
		_pending_impact_work_head,
		_pending_impact_work.size()
	):
		var pending_work := _pending_impact_work[work_index]
		pending_work.chunk = null
		pending_work.stamp = null
		pending_work.raster_band_index = 0
		pending_work.raster_band_count = 1
		pending_work.prepared_patch = null
		pending_work.image_preparation = null
		if _impact_work_pool.size() < MAX_PENDING_IMPACT_WORK_ITEMS:
			_impact_work_pool.append(pending_work)
	_pending_impact_work.clear()
	_pending_impact_work_head = 0
	_clear_temporary_stamp_cache()
	_on_dig_visuals_preparation_started(false)
	# A rebuild invalidates the chunk identity captured by every unpublished
	# structural upload. Recycle those descriptors now instead of retaining
	# stale multi-megabyte chunk masks until later frames happen to skip them.
	for work_index in range(
		_pending_chunk_texture_publish_head,
		_pending_chunk_texture_publishes.size()
	):
		var publish_work := _pending_chunk_texture_publishes[work_index]
		publish_work.chunk = null
		publish_work.chunk_index = -1
		publish_work.layer_indices = PackedInt32Array()
		if (
			_chunk_texture_publish_pool.size()
			< MAX_PENDING_CHUNK_TEXTURE_PUBLISH_ITEMS
		):
			_chunk_texture_publish_pool.append(publish_work)
	_pending_chunk_texture_publishes.clear()
	_pending_chunk_texture_publish_head = 0
	for chunk_index in _active_chunks.keys():
		_unload_chunk(chunk_index)
	# A rebuild is how an authored edit reaches the screen, so nothing built from
	# the previous profile or room may survive it.
	_clear_chunk_visual_pool()
	_sculpt_mask_images.clear()
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


## Fills one terrain chunk's strata, reusing a retired chunk's nodes when the
## view has already left one. Untouched rock starts on the shared intact mask and
## only allocates a stratum of its own when a stamp writes into it.
func _load_chunk(chunk_index: int) -> void:
	var layer_count := profile.get_layer_count()
	if layer_count <= 0:
		return

	var chunk := _acquire_chunk_visual(chunk_index, layer_count)
	_active_chunks[chunk_index] = chunk
	var chunk_contains_chamber := _chunk_contains_chamber(chunk_index)
	# A sculpted room may sit in a chunk the encounter schedule alone would call
	# ordinary rock, so streaming has to ask about rooms as well as chambers.
	var chunk_contains_sculpt := _chunk_contains_sculpt(chunk_index)
	if _is_chunk_intact_rock(
		chunk_index,
		chunk_contains_chamber,
		chunk_contains_sculpt
	):
		_share_intact_masks(chunk, layer_count)
	else:
		_build_chunk_masks(
			chunk,
			chunk_index,
			layer_count,
			chunk_contains_chamber,
			chunk_contains_sculpt
		)
	# The authored reveal band belongs to the foreground alone, so a chunk whose
	# only departure from intact rock is that band keeps three shared strata.
	if not _get_chunk_floor_reveal_rects(chunk_index).is_empty():
		_make_layer_writable(chunk, 0)
		_clear_chamber_foreground_floor_bands(
			chunk.mask_images[0],
			chunk_index
		)
		chunk.dirty_mask_tiles[0] = ALL_MASK_TILES_DIRTY

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
	# The first window must be complete before it is shown. Later structural
	# chunks enter below the viewport margin and publish through the frame
	# scheduler so a sharp multi-layer room cannot monopolize one traversal.
	if _loaded_first_chunk < 0:
		_publish_chunk_textures(chunk)
	else:
		_queue_chunk_textures(chunk, chunk_index)


## Reuses a retired chunk's nodes, or builds the strata this chunk needs once.
func _acquire_chunk_visual(
	chunk_index: int,
	layer_count: int
) -> TerrainChunkVisual:
	var chunk: TerrainChunkVisual = null
	while not _chunk_visual_pool.is_empty():
		var candidate: TerrainChunkVisual = _chunk_visual_pool.pop_back()
		if (
			is_instance_valid(candidate.root)
			and candidate.layer_sprites.size() == layer_count
		):
			chunk = candidate
			break
		if is_instance_valid(candidate.root):
			candidate.root.free()
	if chunk == null:
		chunk = _create_chunk_visual(layer_count)
	chunk.root.name = "LayeredTerrainChunk_%d" % chunk_index
	chunk.root.visible = true
	var world_origin := Vector2(
		0.0,
		float(chunk_index) * _get_chunk_world_size().y
	)
	for layer_index in range(layer_count):
		var sprite := chunk.layer_sprites[layer_index]
		# The rock the shader draws is placed in world space, so moving a reused
		# stratum to another depth is the one parameter that has to follow it.
		(sprite.material as ShaderMaterial).set_shader_parameter(
			&"world_origin",
			world_origin
		)
		# Editor stratum isolation. Nothing at runtime sets an override, so this
		# reads 1.0 during play and the sprite is untouched. Applying it on every
		# acquire is what makes an isolated stratum survive streaming.
		sprite.modulate.a = get_layer_display_opacity(layer_index)
	return chunk


## Builds one chunk's nodes, sprites, and fully configured layer materials.
func _create_chunk_visual(layer_count: int) -> TerrainChunkVisual:
	var chunk := TerrainChunkVisual.new()
	chunk.root = Node2D.new()
	add_child(chunk.root)
	var chunk_world_size := _get_chunk_world_size()
	chunk.dirty_mask_tiles.resize(layer_count)
	chunk.dirty_mask_tiles.fill(ALL_MASK_TILES_DIRTY)
	chunk.layer_revisions.resize(layer_count)
	chunk.layer_revisions.fill(0)
	for layer_index in range(layer_count):
		var sprite := Sprite2D.new()
		sprite.name = "TerrainLayer_%d" % layer_index
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		# One sprite spans the full chunk while its two mask samplers each own
		# half the pixels. Doubling only X preserves the exact world dimensions.
		sprite.scale = Vector2(
			float(MASK_HORIZONTAL_TILE_COUNT),
			1.0
		) * (
			float(terrain_manager.config.terrain_cell_world_size)
			/ float(profile.mask_pixels_per_cell)
		)
		sprite.z_index = profile.get_layer_z_index(layer_index)
		sprite.material = _create_layer_material(
			layer_index,
			Vector2.ZERO,
			chunk_world_size
		)
		chunk.root.add_child(sprite)
		chunk.layer_sprites.append(sprite)
		chunk.mask_images.append(null)
		var texture_tiles: Array[ImageTexture] = []
		texture_tiles.resize(MASK_HORIZONTAL_TILE_COUNT)
		chunk.mask_texture_tiles.append(texture_tiles)
	return chunk


## Reports whether a chunk is ordinary rock with nothing authored inside it.
func _is_chunk_intact_rock(
	chunk_index: int,
	chunk_contains_chamber: bool,
	chunk_contains_sculpt: bool
) -> bool:
	if chunk_contains_chamber or chunk_contains_sculpt:
		return false
	var config: MiningConfig = terrain_manager.config
	var chunk_start_row := chunk_index * config.chunk_height_cells
	return (
		chunk_start_row >= config.initial_surface_row
		and chunk_start_row + config.chunk_height_cells - 1
			<= config.get_bottom_surface_row()
	)


## Reports whether the encounter schedule opens a chamber inside a chunk.
func _chunk_contains_chamber(chunk_index: int) -> bool:
	var encounter_config := terrain_manager.encounter_config
	if encounter_config == null:
		return false
	var config: MiningConfig = terrain_manager.config
	var chunk_start_row := chunk_index * config.chunk_height_cells
	for local_row in range(config.chunk_height_cells):
		if encounter_config.is_chamber_row(
			chunk_start_row + local_row - config.initial_surface_row,
			config.total_run_depth
		):
			return true
	return false


## Points every stratum at the shared intact mask, allocating nothing.
func _share_intact_masks(
	chunk: TerrainChunkVisual,
	layer_count: int
) -> void:
	var intact_image := _get_pristine_mask_image()
	for layer_index in range(layer_count):
		chunk.mask_images[layer_index] = intact_image
		var texture_tiles: Array[ImageTexture] = []
		texture_tiles.resize(MASK_HORIZONTAL_TILE_COUNT)
		texture_tiles.fill(_pristine_mask_texture)
		chunk.mask_texture_tiles[layer_index] = texture_tiles
		_set_sprite_mask_textures(
			chunk.layer_sprites[layer_index],
			texture_tiles
		)
		chunk.dirty_mask_tiles[layer_index] = 0
		chunk.layer_revisions[layer_index] = 0
	chunk.shared_layers = (1 << layer_count) - 1
	chunk.needs_private_texture = 0


## Builds this chunk's own strata for chambers, rooms, and the run's edges.
## Identical starting strata share one CPU mask and GPU tile set copy-on-write;
## this keeps sharp structural rooms from multiplying streaming work per layer.
func _build_chunk_masks(
	chunk: TerrainChunkVisual,
	chunk_index: int,
	layer_count: int,
	chunk_contains_chamber: bool,
	chunk_contains_sculpt: bool
) -> void:
	var chunk_has_per_layer_sculpt := (
		chunk_contains_sculpt and _chunk_has_per_layer_sculpt(chunk_index)
	)
	var base_mask: Image
	# Per-layer rooms replace every foreground source. A chamber backdrop has
	# its own source below, so building the logical full-resolution mask here
	# would allocate and fill an image no stratum ever consumes.
	if (
		not chunk_has_per_layer_sculpt
		or (
			profile.keep_back_layer_solid
			and not chunk_contains_chamber
		)
	):
		base_mask = _build_chunk_base_mask(
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
	var first_backdrop_source_layer := (
		profile.get_gameplay_layer_count() - 1
	)
	chunk.shared_layers = 0
	for layer_index in range(layer_count):
		# The fourth gameplay stratum begins intact as the tunnel back wall.
		var uses_backdrop_source := (
			profile.keep_back_layer_solid
			and layer_index >= first_backdrop_source_layer
		)
		var source_mask := (
			back_layer_mask
			if uses_backdrop_source
			else base_mask
		)
		var layer_mask := source_mask
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
		chunk.mask_images[layer_index] = layer_mask
		chunk.dirty_mask_tiles[layer_index] = ALL_MASK_TILES_DIRTY
	# Mark every image used by more than one stratum as copy-on-write. A later
	# impact detaches only the layer it changes.
	for layer_index in range(layer_count):
		for previous_layer_index in range(layer_index):
			if (
				chunk.mask_images[layer_index]
				== chunk.mask_images[previous_layer_index]
			):
				chunk.shared_layers |= (
					(1 << layer_index)
					| (1 << previous_layer_index)
				)
				break
	chunk.needs_private_texture = 0


## Gives one stratum an image of its own before a stamp writes into it.
func _make_layer_writable(
	chunk: TerrainChunkVisual,
	layer_index: int
) -> void:
	if chunk.shared_layers & (1 << layer_index) == 0:
		return
	chunk.mask_images[layer_index] = (
		chunk.mask_images[layer_index].duplicate()
	)
	chunk.shared_layers &= ~(1 << layer_index)
	chunk.needs_private_texture |= 1 << layer_index


## Publishes every distinct stratum mask once. Copy-on-write siblings bind the
## same immutable tiles until one receives an impact.
func _publish_chunk_textures(chunk: TerrainChunkVisual) -> void:
	var shared_tiles_by_image_id: Dictionary[int, Array] = {}
	for layer_index in range(chunk.mask_images.size()):
		var mask_image: Image = chunk.mask_images[layer_index]
		var image_id := mask_image.get_instance_id()
		if (
			chunk.shared_layers & (1 << layer_index) != 0
			and shared_tiles_by_image_id.has(image_id)
		):
			var shared_tiles: Array = (
				shared_tiles_by_image_id[image_id] as Array
			)
			chunk.mask_texture_tiles[layer_index] = (
				shared_tiles.duplicate()
			)
			_set_sprite_mask_textures(
				chunk.layer_sprites[layer_index],
				chunk.mask_texture_tiles[layer_index]
			)
			chunk.dirty_mask_tiles[layer_index] = 0
			continue
		_publish_layer_texture(chunk, layer_index)
		if chunk.shared_layers & (1 << layer_index) != 0:
			shared_tiles_by_image_id[image_id] = (
				chunk.mask_texture_tiles[layer_index]
			)


## Queues one upload per distinct copy-on-write mask in a streamed chunk.
func _queue_chunk_textures(
	chunk: TerrainChunkVisual,
	chunk_index: int
) -> void:
	var layers_by_image_id: Dictionary[int, PackedInt32Array] = {}
	for layer_index in range(chunk.mask_images.size()):
		if chunk.dirty_mask_tiles[layer_index] == 0:
			continue
		var image_id := chunk.mask_images[layer_index].get_instance_id()
		if chunk.shared_layers & (1 << layer_index) == 0:
			image_id = -1 - layer_index
		var layer_indices: PackedInt32Array = layers_by_image_id.get(
			image_id,
			PackedInt32Array()
		)
		layer_indices.append(layer_index)
		layers_by_image_id[image_id] = layer_indices
	for layer_indices in layers_by_image_id.values():
		while (
			_pending_chunk_texture_publishes.size()
			- _pending_chunk_texture_publish_head
			>= MAX_PENDING_CHUNK_TEXTURE_PUBLISH_ITEMS
		):
			_process_next_chunk_texture_publish()
			_compact_pending_chunk_texture_publishes()
		var work: ChunkTexturePublishWork = (
			_chunk_texture_publish_pool.pop_back()
			if not _chunk_texture_publish_pool.is_empty()
			else ChunkTexturePublishWork.new()
		)
		work.chunk = chunk
		work.chunk_index = chunk_index
		work.layer_indices = layer_indices
		_pending_chunk_texture_publishes.append(work)


## Publishes one distinct mask and binds its immutable tiles to every sibling.
func _process_next_chunk_texture_publish() -> void:
	if (
		_pending_chunk_texture_publish_head
		>= _pending_chunk_texture_publishes.size()
	):
		return
	var work := _pending_chunk_texture_publishes[
		_pending_chunk_texture_publish_head
	]
	_pending_chunk_texture_publish_head += 1
	if (
		_active_chunks.get(work.chunk_index) == work.chunk
		and not work.layer_indices.is_empty()
	):
		var source_layer_index := work.layer_indices[0]
		_publish_layer_texture(work.chunk, source_layer_index)
		var source_tiles: Array = work.chunk.mask_texture_tiles[
			source_layer_index
		]
		for index in range(1, work.layer_indices.size()):
			var layer_index := work.layer_indices[index]
			work.chunk.mask_texture_tiles[layer_index] = (
				source_tiles.duplicate()
			)
			_set_sprite_mask_textures(
				work.chunk.layer_sprites[layer_index],
				work.chunk.mask_texture_tiles[layer_index]
			)
			work.chunk.dirty_mask_tiles[layer_index] = 0
	work.chunk = null
	work.chunk_index = -1
	work.layer_indices = PackedInt32Array()
	if (
		_chunk_texture_publish_pool.size()
		< MAX_PENDING_CHUNK_TEXTURE_PUBLISH_ITEMS
	):
		_chunk_texture_publish_pool.append(work)


func _compact_pending_chunk_texture_publishes() -> void:
	if _pending_chunk_texture_publish_head <= 0:
		return
	if (
		_pending_chunk_texture_publish_head
		>= _pending_chunk_texture_publishes.size()
	):
		_pending_chunk_texture_publishes.clear()
		_pending_chunk_texture_publish_head = 0
		return
	if _pending_chunk_texture_publish_head < 32:
		return
	_pending_chunk_texture_publishes = (
		_pending_chunk_texture_publishes.slice(
			_pending_chunk_texture_publish_head
		)
	)
	_pending_chunk_texture_publish_head = 0


## Uploads one stratum, reusing its texture unless the mask it draws changed
## identity. A stratum that just left the shared intact mask needs a texture of
## its own; one that was already its own is updated in place.
func _publish_layer_texture(
	chunk: TerrainChunkVisual,
	layer_index: int
) -> void:
	var mask_image: Image = chunk.mask_images[layer_index]
	if mask_image == null:
		return
	var sprite := chunk.layer_sprites[layer_index]
	if (
		chunk.shared_layers & (1 << layer_index) != 0
		and chunk.dirty_mask_tiles[layer_index] == 0
	):
		return
	var dirty_tiles: int = chunk.dirty_mask_tiles[layer_index]
	if dirty_tiles == 0:
		return
	var texture_tiles: Array = chunk.mask_texture_tiles[layer_index]
	var requires_private_tiles := (
		chunk.needs_private_texture & (1 << layer_index) != 0
	)
	if requires_private_tiles:
		texture_tiles = texture_tiles.duplicate()
	for tile_index in range(MASK_HORIZONTAL_TILE_COUNT):
		if dirty_tiles & (1 << tile_index) == 0:
			continue
		_prepare_mask_upload_tile(mask_image, tile_index)
		var upload_image := _mask_upload_images[tile_index]
		var mask_texture: ImageTexture = texture_tiles[tile_index]
		if (
			mask_texture == null
			or mask_texture == _pristine_mask_texture
			or requires_private_tiles
			or Vector2i(mask_texture.get_size())
				!= upload_image.get_size()
		):
			var reusable_texture: ImageTexture
			for pool_index in range(
				_chunk_mask_texture_pool.size() - 1,
				-1,
				-1
			):
				var candidate := _chunk_mask_texture_pool[pool_index]
				if Vector2i(candidate.get_size()) == upload_image.get_size():
					reusable_texture = candidate
					_chunk_mask_texture_pool.remove_at(pool_index)
					break
			if reusable_texture == null:
				reusable_texture = ImageTexture.create_from_image(
					upload_image
				)
			else:
				reusable_texture.update(upload_image)
			texture_tiles[tile_index] = reusable_texture
		else:
			mask_texture.update(upload_image)
	chunk.mask_texture_tiles[layer_index] = texture_tiles
	_set_sprite_mask_textures(sprite, texture_tiles)
	chunk.dirty_mask_tiles[layer_index] = 0
	chunk.needs_private_texture &= ~(1 << layer_index)


## Binds one layer's fixed tile set to its single full-width sprite.
func _set_sprite_mask_textures(
	sprite: Sprite2D,
	texture_tiles: Array
) -> void:
	sprite.texture = texture_tiles[0]
	sprite.scale.x = (
		_get_chunk_world_size().x
		/ float((texture_tiles[0] as Texture2D).get_width())
	)
	var material := sprite.material as ShaderMaterial
	for tile_index in range(MASK_HORIZONTAL_TILE_COUNT):
		material.set_shader_parameter(
			"mask_tile_%d" % tile_index,
			texture_tiles[tile_index]
		)


## Copies one dirty CPU column into its reusable GPU upload image. Its gutters
## carry neighboring authoritative columns, so updating one tile preserves
## bilinear continuity without copying or uploading the other two.
func _prepare_mask_upload_tile(
	mask_image: Image,
	tile_index: int
) -> void:
	assert(
		mask_image.get_width() % MASK_HORIZONTAL_TILE_COUNT == 0,
		"Terrain mask width must divide evenly across its GPU tiles."
	)
	var tile_content_width := (
		mask_image.get_width() / MASK_HORIZONTAL_TILE_COUNT
	)
	var tile_size := Vector2i(
		tile_content_width + MASK_TILE_GUTTER_PIXELS * 2,
		mask_image.get_height()
	)
	if (
		_mask_upload_images.size() != MASK_HORIZONTAL_TILE_COUNT
		or _mask_upload_images[0] == null
		or _mask_upload_images[0].get_size() != tile_size
	):
		_mask_upload_images.clear()
		for _upload_index in range(MASK_HORIZONTAL_TILE_COUNT):
			_mask_upload_images.append(
				Image.create(
					tile_size.x,
					tile_size.y,
					false,
					Image.FORMAT_LA8
				)
			)
	var tile_start_x := tile_index * tile_content_width
	var upload_image := _mask_upload_images[tile_index]
	upload_image.blit_rect(
		mask_image,
		Rect2i(
			tile_start_x,
			0,
			tile_content_width,
			tile_size.y
		),
		Vector2i(MASK_TILE_GUTTER_PIXELS, 0)
	)
	upload_image.blit_rect(
		mask_image,
		Rect2i(
			maxi(tile_start_x - 1, 0),
			0,
			1,
			tile_size.y
		),
		Vector2i.ZERO
	)
	upload_image.blit_rect(
		mask_image,
		Rect2i(
			mini(
				tile_start_x + tile_content_width,
				mask_image.get_width() - 1
			),
			0,
			1,
			tile_size.y
		),
		Vector2i(tile_size.x - 1, 0)
	)


## Returns the one solid mask every intact stratum draws.
func _get_pristine_mask_image() -> Image:
	var mask_size := _get_chunk_mask_size()
	if _pristine_mask_image != null and _pristine_mask_size == mask_size:
		return _pristine_mask_image
	_pristine_mask_size = mask_size
	_pristine_mask_image = Image.create(
		mask_size.x,
		mask_size.y,
		false,
		Image.FORMAT_LA8
	)
	_pristine_mask_image.fill(SOLID_MASK_COLOR)
	_prepare_mask_upload_tile(_pristine_mask_image, 0)
	_pristine_mask_texture = ImageTexture.create_from_image(
		_mask_upload_images[0]
	)
	return _pristine_mask_image


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


## Retires a chunk's nodes for reuse while retaining their impact records.
func _unload_chunk(chunk_index: int) -> void:
	var chunk := _active_chunks[chunk_index]
	_active_chunks.erase(chunk_index)
	if _chunk_visual_pool.size() >= CHUNK_VISUAL_POOL_LIMIT:
		# Streaming can cross many chunk boundaries in one frame during a fast
		# review or fall. Deferred deletion would retain every old ImageTexture
		# until the frame ends and can exhaust memory before Godot flushes it.
		chunk.root.free()
		return
	# The nodes and their configured materials are what the next chunk reuses.
	# Masks are released here for the same reason: a pooled chunk must not hold
	# a departed chunk's image and texture memory.
	_release_chunk_masks(chunk)
	chunk.root.visible = false
	chunk.root.name = "PooledTerrainChunk"
	_chunk_visual_pool.append(chunk)


## Drops a retired chunk's owned masks back onto the shared intact mask.
func _release_chunk_masks(chunk: TerrainChunkVisual) -> void:
	var released_image_ids: Dictionary[int, bool] = {}
	var released_texture_ids: Dictionary[int, bool] = {}
	for layer_index in range(chunk.mask_images.size()):
		var released_image: Image = chunk.mask_images[layer_index]
		if (
			released_image != null
			and released_image != _pristine_mask_image
			and not released_image_ids.has(
				released_image.get_instance_id()
			)
			and (
				_chunk_mask_image_pool.size()
				< CHUNK_MASK_IMAGE_POOL_LIMIT
			)
		):
			released_image_ids[released_image.get_instance_id()] = true
			_chunk_mask_image_pool.append(released_image)
		for released_texture in chunk.mask_texture_tiles[layer_index]:
			if (
				released_texture != null
				and released_texture != _pristine_mask_texture
				and not released_texture_ids.has(
					released_texture.get_instance_id()
				)
				and (
					_chunk_mask_texture_pool.size()
					< CHUNK_MASK_TEXTURE_POOL_LIMIT
				)
			):
				released_texture_ids[
					released_texture.get_instance_id()
				] = true
				_chunk_mask_texture_pool.append(released_texture)
	var intact_image := _get_pristine_mask_image()
	for layer_index in range(chunk.mask_images.size()):
		chunk.mask_images[layer_index] = intact_image
		var texture_tiles: Array[ImageTexture] = []
		texture_tiles.resize(MASK_HORIZONTAL_TILE_COUNT)
		texture_tiles.fill(_pristine_mask_texture)
		chunk.mask_texture_tiles[layer_index] = texture_tiles
		_set_sprite_mask_textures(
			chunk.layer_sprites[layer_index],
			texture_tiles
		)
		chunk.dirty_mask_tiles[layer_index] = 0
		chunk.layer_revisions[layer_index] = 0
	chunk.shared_layers = (1 << chunk.mask_images.size()) - 1
	chunk.needs_private_texture = 0


## Frees every retired chunk, so a profile or room edit cannot hand stale
## materials to the next streamed chunk.
func _clear_chunk_visual_pool() -> void:
	for chunk in _chunk_visual_pool:
		if is_instance_valid(chunk.root):
			chunk.root.free()
	_chunk_visual_pool.clear()
	_chunk_mask_image_pool.clear()
	_chunk_mask_texture_pool.clear()


## Builds one layer's undamaged terrain before applying organic openings.
func _build_chunk_base_mask(
	chunk_index: int,
	preserve_chamber_backdrop: bool,
	chunk_contains_chamber: bool,
	chunk_contains_sculpt: bool = false,
	sculpt_layer_index: int = -1
) -> Image:
	var config := terrain_manager.config
	# Sculpt caches retain one authored sample per logical cell. Expand only the
	# active chunk; the shader's linear sampling reconstructs the same threshold
	# contour without keeping every full-room layer at gameplay density.
	var mask_cell_size := (
		1 if chunk_contains_sculpt else profile.mask_pixels_per_cell
	)
	var mask_size := _get_chunk_mask_size()
	var chunk_start_row := chunk_index * config.chunk_height_cells
	var chunk_end_row := (
		chunk_start_row + config.chunk_height_cells - 1
	)
	var raster_size := Vector2i(
		config.terrain_width_cells * mask_cell_size,
		config.chunk_height_cells * mask_cell_size
	)
	var image: Image
	if raster_size == mask_size:
		while not _chunk_mask_image_pool.is_empty():
			var candidate: Image = _chunk_mask_image_pool.pop_back()
			if candidate.get_size() == mask_size:
				image = candidate
				break
	if image == null:
		image = Image.create(
			raster_size.x,
			raster_size.y,
			false,
			Image.FORMAT_LA8
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
					Rect2i(0, row_mask_y, raster_size.x, mask_cell_size),
					SOLID_MASK_COLOR
				)
			continue
		if not is_chamber_row:
			image.fill_rect(
				Rect2i(
					0,
					row_mask_y,
					raster_size.x,
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
	if chunk_contains_sculpt and not preserve_chamber_backdrop:
		_blit_sculpt_rooms(
			image,
			chunk_index,
			sculpt_layer_index,
			mask_cell_size
		)
	if raster_size != mask_size:
		image.resize(
			mask_size.x,
			mask_size.y,
			Image.INTERPOLATE_NEAREST
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


## Prints every authored room reaching into one chunk over the terrain already
## drawn beneath it. The room arrives as a mask rasterized once, so a streamed
## chunk pays a clipped copy rather than rebuilding the room's rim per row.
func _blit_sculpt_rooms(
	image: Image,
	chunk_index: int,
	sculpt_layer_index: int,
	mask_cell_size: int
) -> void:
	var config: MiningConfig = terrain_manager.config
	var chunk_start_row := chunk_index * config.chunk_height_cells
	var chunk_end_row := chunk_start_row + config.chunk_height_cells
	for placement in terrain_manager.get_sculpt_placements():
		var room_rect: Rect2i = placement.world_rect
		if (
			room_rect.position.y >= chunk_end_row
			or room_rect.end.y <= chunk_start_row
		):
			continue
		var room_mask := _get_sculpt_mask_image(
			placement.sculpt,
			sculpt_layer_index
		)
		if room_mask == null:
			continue
		var first_row := maxi(room_rect.position.y, chunk_start_row)
		var last_row := mini(room_rect.end.y, chunk_end_row)
		var source_rect := Rect2i(
			0,
			(first_row - room_rect.position.y) * mask_cell_size,
			room_mask.get_width(),
			(last_row - first_row) * mask_cell_size
		)
		var destination := Vector2i(
			room_rect.position.x * mask_cell_size,
			(first_row - chunk_start_row) * mask_cell_size
		)
		# A room reaching past either edge of the run is clipped there rather
		# than wrapped around to the opposite wall.
		if destination.x < 0:
			source_rect.position.x -= destination.x
			source_rect.size.x += destination.x
			destination.x = 0
		var overflow_x := (
			destination.x + source_rect.size.x - image.get_width()
		)
		if overflow_x > 0:
			source_rect.size.x -= overflow_x
		if source_rect.size.x <= 0 or source_rect.size.y <= 0:
			continue
		image.blit_rect(room_mask, source_rect, destination)


## Returns one room's rock at mask resolution, rasterizing it on first use.
func _get_sculpt_mask_image(
	sculpt: CutsceneTerrainSculpt,
	sculpt_layer_index: int
) -> Image:
	if sculpt == null:
		return null
	var cache_index := sculpt_layer_index + 1
	var layer_masks: Array = _sculpt_mask_images.get(sculpt, [])
	if layer_masks.size() > cache_index and layer_masks[cache_index] != null:
		return layer_masks[cache_index]
	var room_mask := _rasterize_sculpt_mask(sculpt, sculpt_layer_index)
	while layer_masks.size() <= cache_index:
		layer_masks.append(null)
	layer_masks[cache_index] = room_mask
	_sculpt_mask_images[sculpt] = layer_masks
	return room_mask


## Draws one authored room once, at mask resolution.
##
## The room is written at one pixel per cell and then upscaled: Godot's bilinear
## filter samples the same cell centers a hand-written rim sampler would, so the
## visible contour is the sub-cell one, produced in a single pass instead of per
## mask pixel. Luminance stays full across the room because the shader reads it
## as crack ink; only alpha carries the shape the room was carved into.
func _rasterize_sculpt_mask(
	sculpt: CutsceneTerrainSculpt,
	sculpt_layer_index: int
) -> Image:
	var mask_cell_size := 1
	var grid := sculpt.grid_size
	if grid.x <= 0 or grid.y <= 0 or mask_cell_size <= 0:
		return null
	# One solid cell of padding stands in for the untouched rock around the room,
	# which is what a cell on the room's own edge interpolates against.
	var padded_size := grid + Vector2i(2, 2)
	var cell_bytes := PackedByteArray()
	cell_bytes.resize(padded_size.x * padded_size.y * 2)
	var byte_index := 0
	for padded_y in range(padded_size.y):
		for padded_x in range(padded_size.x):
			cell_bytes[byte_index] = 255
			cell_bytes[byte_index + 1] = (
				255
				if _is_sculpt_cell_solid(
					sculpt,
					sculpt_layer_index,
					Vector2i(padded_x - 1, padded_y - 1)
				)
				else 0
			)
			byte_index += 2
	var cell_image := Image.create_from_data(
		padded_size.x,
		padded_size.y,
		false,
		Image.FORMAT_LA8,
		cell_bytes
	)
	cell_image.resize(
		padded_size.x * mask_cell_size,
		padded_size.y * mask_cell_size,
		(
			Image.INTERPOLATE_BILINEAR
			if sculpt.edge_smoothing > 0.0
			else Image.INTERPOLATE_NEAREST
		)
	)
	var room_mask := cell_image.get_region(
		Rect2i(
			Vector2i(mask_cell_size, mask_cell_size),
			grid * mask_cell_size
		)
	)
	if sculpt.edge_smoothing > 0.0 and sculpt.edge_smoothing < 1.0:
		_harden_sculpt_mask_rims(room_mask, sculpt, sculpt_layer_index)
	return room_mask


## Pulls a partly smoothed room's rim back toward the cells it was painted on.
## Only cells on a solid/open boundary can differ from their own cell value, so
## only those pay per-pixel work, and only when a room asks for a harder edge.
func _harden_sculpt_mask_rims(
	room_mask: Image,
	sculpt: CutsceneTerrainSculpt,
	sculpt_layer_index: int
) -> void:
	var mask_cell_size := maxi(
		room_mask.get_width() / maxi(sculpt.grid_size.x, 1),
		1
	)
	var smoothing := sculpt.edge_smoothing
	for local_y in range(sculpt.grid_size.y):
		for local_x in range(sculpt.grid_size.x):
			var local_cell := Vector2i(local_x, local_y)
			if not _is_sculpt_boundary_cell(
				sculpt,
				sculpt_layer_index,
				local_cell
			):
				continue
			var hard_value := (
				1.0
				if _is_sculpt_cell_solid(
					sculpt,
					sculpt_layer_index,
					local_cell
				)
				else 0.0
			)
			for sub_y in range(mask_cell_size):
				var mask_y := local_y * mask_cell_size + sub_y
				for sub_x in range(mask_cell_size):
					var mask_x := local_x * mask_cell_size + sub_x
					var smoothed := room_mask.get_pixel(mask_x, mask_y)
					smoothed.a = lerpf(hard_value, smoothed.a, smoothing)
					room_mask.set_pixel(mask_x, mask_y, smoothed)


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


## Lowers only layer one beneath each room's unchanged layer-two support.
func _clear_chamber_foreground_floor_bands(
	image: Image,
	chunk_index: int
) -> void:
	for reveal_rect in _get_chunk_floor_reveal_rects(chunk_index):
		image.fill_rect(reveal_rect, EMPTY_MASK_COLOR)


## Returns the authored reveal bands one chunk's foreground has to drop. Asking
## for the rectangles rather than clearing them directly is what lets streaming
## tell an ordinary chunk from one carrying a band before it builds any mask.
func _get_chunk_floor_reveal_rects(chunk_index: int) -> Array[Rect2i]:
	var reveal_rects: Array[Rect2i] = []
	var config := terrain_manager.config
	var encounter_config := terrain_manager.encounter_config
	if (
		encounter_config == null
		or profile.chamber_layer_two_floor_reveal_px <= 0.0
		or profile.mask_pixels_per_cell <= 0
	):
		return reveal_rects
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
	var chunk_bounds := Rect2i(Vector2i.ZERO, _get_chunk_mask_size())
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
		).intersection(chunk_bounds)
		if reveal_rect.has_area():
			reveal_rects.append(reveal_rect)
	return reveal_rects


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
	impact_origin_cell_x: int = -1,
	destroyed_bounds: Rect2i = Rect2i()
) -> ImpactStamp:
	var minimum_cell := (
		destroyed_bounds.position
		if destroyed_bounds.has_area()
		else destroyed_cells[0]
	)
	var maximum_cell := (
		destroyed_bounds.end - Vector2i.ONE
		if destroyed_bounds.has_area()
		else destroyed_cells[0]
	)
	if not destroyed_bounds.has_area():
		for cell in destroyed_cells:
			minimum_cell.x = mini(minimum_cell.x, cell.x)
			minimum_cell.y = mini(minimum_cell.y, cell.y)
			maximum_cell.x = maxi(maximum_cell.x, cell.x)
			maximum_cell.y = maxi(maximum_cell.y, cell.y)
	if not is_narrow_path:
		return _create_ordinary_impact_stamp_from_bounds(
			minimum_cell,
			maximum_cell,
			destroyed_cells.size(),
			horizontal_direction,
			impact_origin_cell_x,
			_active_impact_combo
		)

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


## Builds the one ordinary-stamp contract shared by candidates and real damage.
func _create_ordinary_impact_stamp_from_bounds(
	minimum_cell: Vector2i,
	maximum_cell: Vector2i,
	damaged_cell_count: int,
	horizontal_direction: int,
	impact_origin_cell_x: int,
	impact_combo: int
) -> ImpactStamp:
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
	if impact_origin_cell_x >= 0:
		stamp.center.x = (
			float(impact_origin_cell_x) + 0.5
		) * float(cell_size)
	stamp.damage_bounds = damage_rect
	stamp.core_radius = (
		maxf(damage_rect.size.x, damage_rect.size.y) * 0.5
	)
	stamp.include_fracture_lines = (
		stamp.core_radius
		<= MAX_FRACTURE_RADIUS_CELLS * float(cell_size)
	)
	stamp.use_big_hole = (
		impact_combo >= deepest_layer_combo_threshold
		and stamp.core_radius * 2.0
		>= float(profile.big_hole_minimum_size)
	)
	var variation_hash := (
		minimum_cell.x * 73_856_093
		^ minimum_cell.y * 19_349_663
		^ damaged_cell_count * 83_492_791
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
	stamp.preparation_key = "%d,%d:%d,%d:%d:%d:%d:%d" % [
		minimum_cell.x,
		minimum_cell.y,
		maximum_cell.x,
		maximum_cell.y,
		damaged_cell_count,
		horizontal_direction,
		impact_origin_cell_x,
		impact_combo,
	]
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
	var changed_layers := 0
	for layer_index in range(gameplay_layer_count):
		if _apply_impact_stamp_layer(
			chunk,
			chunk_index,
			stamp,
			layer_index
		):
			changed_layers |= 1 << layer_index
	return changed_layers


## Punches exactly one stratum so browser builds can amortize a hit without
## exposing a partially-written texture.
func _apply_impact_stamp_layer(
	chunk: TerrainChunkVisual,
	chunk_index: int,
	stamp: ImpactStamp,
	layer_index: int,
	raster_band_index: int = 0,
	raster_band_count: int = 1
) -> bool:
	if not _can_apply_impact_stamp_layer(stamp, layer_index):
		return false
	_make_layer_writable(chunk, layer_index)
	var changed := false
	if not stamp.narrow_path_points.is_empty():
		changed = _punch_narrow_path(
			chunk.mask_images[layer_index],
			chunk_index,
			stamp,
			layer_index
		)
	else:
		var mask_data := _get_hole_mask_data(
			layer_index,
			stamp.use_big_hole
		)
		if mask_data == null:
			return false
		var opening_rect := _get_layer_opening_rect(stamp, layer_index)
		var layer_variation := _get_layer_stamp_variation(
			stamp,
			layer_index
		)
		changed = _punch_hole(
			chunk.mask_images[layer_index],
			chunk_index,
			opening_rect,
			mask_data,
			layer_variation.x == 1,
			layer_variation.y == 1,
			layer_variation.z,
			stamp.include_fracture_lines,
			raster_band_index,
			raster_band_count
		)
	if changed:
		chunk.dirty_mask_tiles[layer_index] |= (
			_get_stamp_dirty_tile_bits(stamp, layer_index)
		)
		chunk.layer_revisions[layer_index] += 1
	return changed


## Maps one stamp's authored extent onto the fixed tile lattice. Expanding by
## one mask pixel marks both neighbors only when a gutter column can change.
func _get_stamp_dirty_tile_bits(
	stamp: ImpactStamp,
	layer_index: int
) -> int:
	var stamp_rect := _get_stamp_broad_rect(stamp)
	if stamp.narrow_path_points.is_empty():
		var mask_data := _get_hole_mask_data(
			layer_index,
			stamp.use_big_hole
		)
		if mask_data == null:
			return 0
		var opening_rect := _get_layer_opening_rect(stamp, layer_index)
		var layer_variation := _get_layer_stamp_variation(
			stamp,
			layer_index
		)
		stamp_rect = _get_full_stamp_world_rect(
			opening_rect,
			mask_data,
			layer_variation.x == 1,
			layer_variation.y == 1,
			layer_variation.z
		)
	if not stamp_rect.has_area():
		return 0
	var mask_pixels_per_world_unit := (
		float(profile.mask_pixels_per_cell)
		/ float(terrain_manager.config.terrain_cell_world_size)
	)
	var mask_width := _get_chunk_mask_size().x
	var tile_width := mask_width / MASK_HORIZONTAL_TILE_COUNT
	var first_mask_x := clampi(
		floori(stamp_rect.position.x * mask_pixels_per_world_unit) - 1,
		0,
		mask_width - 1
	)
	var last_mask_x := clampi(
		ceili(stamp_rect.end.x * mask_pixels_per_world_unit),
		0,
		mask_width - 1
	)
	var first_tile := clampi(
		floori(float(first_mask_x) / float(tile_width)),
		0,
		MASK_HORIZONTAL_TILE_COUNT - 1
	)
	var last_tile := clampi(
		floori(float(last_mask_x) / float(tile_width)),
		first_tile,
		MASK_HORIZONTAL_TILE_COUNT - 1
	)
	var dirty_tiles := 0
	for tile_index in range(first_tile, last_tile + 1):
		dirty_tiles |= 1 << tile_index
	return dirty_tiles


## Returns the exact full-mask rectangle a primary stamp can change in one
## chunk. Prediction crops this rect before rastering; the normal punch path
## clips against the same integer lattice, so promoted pixels are byte-identical.
func _get_stamp_layer_chunk_mask_rect(
	stamp: ImpactStamp,
	layer_index: int,
	chunk_index: int
) -> Rect2i:
	if not stamp.narrow_path_points.is_empty():
		return Rect2i()
	var mask_data := _get_hole_mask_data(
		layer_index,
		stamp.use_big_hole
	)
	if mask_data == null:
		return Rect2i()
	var opening_rect := _get_layer_opening_rect(stamp, layer_index)
	var layer_variation := _get_layer_stamp_variation(
		stamp,
		layer_index
	)
	var full_stamp_rect := _get_full_stamp_world_rect(
		opening_rect,
		mask_data,
		layer_variation.x == 1,
		layer_variation.y == 1,
		layer_variation.z
	)
	if not full_stamp_rect.has_area():
		return Rect2i()
	var mask_pixels_per_world_unit := (
		float(profile.mask_pixels_per_cell)
		/ float(terrain_manager.config.terrain_cell_world_size)
	)
	var stamp_size := _get_stamp_pixel_size(full_stamp_rect.size)
	var chunk_mask_top := (
		chunk_index
		* terrain_manager.config.chunk_height_cells
		* profile.mask_pixels_per_cell
	)
	var destination_position := Vector2i(
		floori(full_stamp_rect.position.x * mask_pixels_per_world_unit),
		floori(full_stamp_rect.position.y * mask_pixels_per_world_unit)
			- chunk_mask_top
	)
	var config := terrain_manager.config
	var surface_local_y := (
		config.initial_surface_row * profile.mask_pixels_per_cell
		- chunk_mask_top
	)
	var clipped_height := stamp_size.y
	if destination_position.y < surface_local_y:
		var clipped_rows := surface_local_y - destination_position.y
		if clipped_rows >= clipped_height:
			return Rect2i()
		clipped_height -= clipped_rows
		destination_position.y = surface_local_y
	var floor_local_y := (
		(config.get_bottom_surface_row() + 1) * profile.mask_pixels_per_cell
		- chunk_mask_top
	)
	clipped_height = mini(
		clipped_height,
		floor_local_y - destination_position.y
	)
	if clipped_height <= 0:
		return Rect2i()
	return Rect2i(
		destination_position,
		Vector2i(stamp_size.x, clipped_height)
	).intersection(
		Rect2i(Vector2i.ZERO, _get_chunk_mask_size())
	)


## Shares the exact visible-layer contract between synchronous stamping and
## deferred queue construction, so rejected strata never become queued no-ops.
func _can_apply_impact_stamp_layer(
	stamp: ImpactStamp,
	layer_index: int
) -> bool:
	var gameplay_layer_count := profile.get_gameplay_layer_count()
	if (
		layer_index < 0
		or layer_index >= gameplay_layer_count
		or (
			profile.keep_back_layer_solid
			and layer_index == gameplay_layer_count - 1
		)
	):
		return false
	# Orange remains the decorative tunnel backdrop below combo seven. At or
	# above the combo gate, the size threshold still prevents a physically
	# small secondary path from exposing the brown back wall.
	var is_layer_covering_backdrop := (
		profile.keep_back_layer_solid
		and layer_index == gameplay_layer_count - 2
	)
	return not is_layer_covering_backdrop or stamp.use_big_hole


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
	rotation_quarters: int,
	include_fracture_lines: bool = true,
	raster_band_index: int = 0,
	raster_band_count: int = 1,
	destination_mask_origin: Vector2i = Vector2i.ZERO
) -> bool:
	var full_stamp_rect := _get_full_stamp_world_rect(
		opening_world_rect,
		mask_data,
		flip_x,
		flip_y,
		rotation_quarters
	)
	if not full_stamp_rect.has_area():
		return false
	var full_stamp_size := full_stamp_rect.size
	var full_stamp_position := full_stamp_rect.position
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
	var stamp_size := _get_stamp_pixel_size(full_stamp_size)
	var stamp_images := _get_resized_stamp_images(
		mask_data,
		stamp_size,
		flip_x,
		flip_y,
		rotation_quarters,
		false,
		include_fracture_lines
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
	destination_position -= destination_mask_origin
	# The mask artwork carries its crack strokes as opaque pixels, and blending
	# them onto a row that holds no terrain would turn a stroke into solid
	# ground. Clip the stamp to the real strata so cracks can never draw against
	# open sky above the surface or past the world floor.
	var source_rect := Rect2i(Vector2i.ZERO, stamp_size)
	var config := terrain_manager.config
	var surface_local_y := (
		config.initial_surface_row * profile.mask_pixels_per_cell
		- chunk_mask_top
		- destination_mask_origin.y
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
		- destination_mask_origin.y
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
	# Mask the blend with a stamp-sized copy of the pre-impact terrain. Strokes
	# darken only rock that is still solid, and no already-cleared pixel is ever
	# touched. This keeps one bounded allocation on the mining hot path instead
	# of copying the same affected region twice.
	var affected_rect := Rect2i(
		destination_position,
		source_rect.size
	).intersection(Rect2i(Vector2i.ZERO, destination.get_size()))
	if not affected_rect.has_area():
		return false
	if raster_band_count > 1:
		var band_height := ceili(
			float(affected_rect.size.y)
			/ float(raster_band_count)
		)
		var band_top := (
			affected_rect.position.y
			+ band_height * raster_band_index
		)
		var band_bottom := mini(
			band_top + band_height,
			affected_rect.end.y
		)
		if band_top >= band_bottom:
			return false
		affected_rect = Rect2i(
			affected_rect.position.x,
			band_top,
			affected_rect.size.x,
			band_bottom - band_top
		)
	var clipped_source_rect := Rect2i(
		source_rect.position + affected_rect.position - destination_position,
		affected_rect.size
	)
	if stamp_images.fracture_source != null:
		var scratch_size := affected_rect.size
		if (
			_fracture_band_scratch == null
			or _fracture_band_scratch.get_width() < scratch_size.x
			or _fracture_band_scratch.get_height() < scratch_size.y
		):
			var grown_size := Vector2i(
				maxi(
					scratch_size.x,
					_fracture_band_scratch.get_width()
						if _fracture_band_scratch != null
						else 1
				),
				maxi(
					scratch_size.y,
					_fracture_band_scratch.get_height()
						if _fracture_band_scratch != null
						else 1
				)
			)
			_fracture_band_scratch = Image.create(
				grown_size.x,
				grown_size.y,
				false,
				Image.FORMAT_LA8
			)
			_solid_band_scratch = Image.create(
				grown_size.x,
				grown_size.y,
				false,
				Image.FORMAT_LA8
			)
		_fracture_band_scratch.blit_rect(
			stamp_images.fracture_source,
			clipped_source_rect,
			Vector2i.ZERO
		)
		_solid_band_scratch.blit_rect(
			destination,
			affected_rect,
			Vector2i.ZERO
		)
		var scratch_rect := Rect2i(Vector2i.ZERO, scratch_size)
		destination.blend_rect_mask(
			_fracture_band_scratch,
			_solid_band_scratch,
			scratch_rect,
			affected_rect.position
		)

	# Only now carve this stamp's own cavity.
	destination.blit_rect_mask(
		stamp_images.transparent_source,
		stamp_images.erase_mask,
		clipped_source_rect,
		affected_rect.position
	)
	return true


## Resolves the transformed authored stamp once for queue sizing and punching.
## Both callers use this exact rect, so per-chunk bands cover every crack pixel
## without repeating the full multi-chunk height in each touched chunk.
func _get_full_stamp_world_rect(
	opening_world_rect: Rect2,
	mask_data: HoleMaskData,
	flip_x: bool,
	flip_y: bool,
	rotation_quarters: int
) -> Rect2:
	var source_bounds := _get_oriented_transparent_bounds(
		mask_data,
		flip_x,
		flip_y,
		rotation_quarters
	)
	if source_bounds.size.x <= 0.0 or source_bounds.size.y <= 0.0:
		return Rect2()
	var full_stamp_size := Vector2(
		opening_world_rect.size.x / source_bounds.size.x,
		opening_world_rect.size.y / source_bounds.size.y
	)
	return Rect2(
		opening_world_rect.position
			- source_bounds.position * full_stamp_size,
		full_stamp_size
	)


## Converts the shared predicted/authoritative world size into one cache key.
func _get_stamp_pixel_size(stamp_world_size: Vector2) -> Vector2i:
	var mask_pixels_per_world_unit := (
		float(profile.mask_pixels_per_cell)
		/ float(terrain_manager.config.terrain_cell_world_size)
	)
	return Vector2i(
		maxi(
			ceili(stamp_world_size.x * mask_pixels_per_world_unit),
			1
		),
		maxi(
			ceili(stamp_world_size.y * mask_pixels_per_world_unit),
			1
		)
	)


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
	rotation_quarters: int,
	is_preparation: bool = false,
	include_fracture_lines: bool = true
) -> TerrainStampImageCache.StampImages:
	return _stamp_image_cache.get_images(
		mask_data.cache_id,
		mask_data.erase_mask,
		mask_data.fracture_source,
		mask_data.has_fracture_lines and include_fracture_lines,
		stamp_size,
		flip_x,
		flip_y,
		rotation_quarters,
		is_preparation,
		AUTHORED_MASK_SOURCE_SUPERSAMPLE
	)


## Releases one-operation oversized masks after all touched chunks reuse them.
func _clear_temporary_stamp_cache() -> void:
	_stamp_image_cache.clear_temporary()


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
			# Chamber ceilings already receive the continuous shader cut outline.
			# Their eight overlapping transition stamps omit authored fracture
			# spurs so streamed rooms do not repeat the heaviest impact-only blend.
			stamp.include_fracture_lines = false

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
	_stamp_image_cache.reset(
		resized_stamp_cache_limit,
		resized_stamp_cache_max_pixels
	)
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
	var writes_fracture_lines := fracture_line_scale > 0.0
	var fracture_source: Image
	if writes_fracture_lines:
		fracture_source = Image.create(
			mask_width,
			mask_height,
			false,
			Image.FORMAT_LA8
		)
		# Carry the stroke value in unwritten pixels too. Coverage lives in
		# alpha, so a white backing would fade a shrinking line twice.
		var line_value := 1.0 - profile.fracture_line_strength
		fracture_source.fill(
			Color(line_value, line_value, line_value, 0.0)
		)
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

	# Fracture spurs retain their symmetric art canvas because their offset from
	# the cavity is authored. Alpha-only layers need only the tight cavity: the
	# opening rect already defines its final world placement, so resizing empty
	# canvas margins spends CPU without contributing a visible mask pixel.
	var crop_rect := Rect2i(
		minimum,
		maximum - minimum + Vector2i.ONE
	)
	if writes_fracture_lines:
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
		crop_rect = Rect2i(
			crop_minimum,
			crop_maximum - crop_minimum + Vector2i.ONE
		)
	erase_mask = erase_mask.get_region(crop_rect)
	if fracture_source != null:
		fracture_source = fracture_source.get_region(crop_rect)

	var data := HoleMaskData.new()
	data.erase_mask = erase_mask
	data.fracture_source = fracture_source
	data.has_fracture_lines = writes_fracture_lines
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
		&"rock_run_world_px",
		float(terrain_manager.config.total_run_depth)
			* float(terrain_manager.config.terrain_cell_world_size)
	)
	material.set_shader_parameter(
		&"rock_bottom_density_multiplier",
		profile.rock_bottom_density_multiplier
	)
	material.set_shader_parameter(
		&"use_rock_shadows",
		profile.rock_shadows_enabled
	)
	material.set_shader_parameter(
		&"rock_shadow_strength",
		profile.rock_shadow_strength
	)
	# Foreground crystals are part of the intact face, not mined-out outcrops.
	# Only layer zero pays the additional atlas read; its terrain mask clips the
	# crystal automatically when that piece of rock is removed.
	material.set_shader_parameter(
		&"foreground_gem_texture",
		profile.foreground_gem_texture
	)
	material.set_shader_parameter(
		&"use_foreground_gems",
		layer_index == 0
			and profile.foreground_gem_texture != null
			and profile.foreground_gem_density > 0.0
	)
	material.set_shader_parameter(
		&"foreground_gem_atlas_count",
		profile.foreground_gem_atlas_count
	)
	var foreground_gem_aspect := 1.0
	if (
		profile.foreground_gem_texture != null
		and profile.foreground_gem_texture.get_height() > 0
	):
		foreground_gem_aspect = (
			float(profile.foreground_gem_texture.get_width())
			/ float(maxi(profile.foreground_gem_atlas_count, 1))
			/ float(profile.foreground_gem_texture.get_height())
		)
	material.set_shader_parameter(
		&"foreground_gem_cell_aspect",
		foreground_gem_aspect
	)
	material.set_shader_parameter(
		&"foreground_gem_density",
		profile.foreground_gem_density
	)
	material.set_shader_parameter(
		&"foreground_gem_cell_world_px",
		profile.foreground_gem_cell_world_px
	)
	material.set_shader_parameter(
		&"foreground_gem_minimum_height",
		profile.foreground_gem_minimum_height
	)
	material.set_shader_parameter(
		&"foreground_gem_maximum_height",
		profile.foreground_gem_maximum_height
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
		_publish_layer_texture(chunk, layer_index)


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
