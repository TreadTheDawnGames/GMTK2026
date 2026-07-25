extends RefCounted

## How it works:
## - Accepts authored erase/fracture images plus one requested orientation.
## - Resizes both channels with the filtering appropriate to their purpose.
## - Keeps bounded reusable results under deterministic stamp keys.
## - Pins at most five predicted candidates until contact or target regeneration.
## - Keeps oversized results only for the current synchronous terrain update.
## - Exposes entries read-only for renderer diagnostics and benchmark checks.
## - The invariant is that erase masks remain hard-edged after transformation.

class StampImages:
	var erase_mask: Image
	var transparent_source: Image
	var fracture_source: Image


class OrientedSources:
	var erase_mask: Image
	var fracture_source: Image


class ImagePreparation:
	var cache_key: Vector4i
	var can_cache: bool
	var is_speculative: bool
	var stamp_size: Vector2i
	var oriented: OrientedSources
	var stamp_images: StampImages
	var horizontal_source: Image
	var next_row: int = 0
	var phase: int = 0
	var completed: bool = false


var entries: Dictionary[Vector4i, StampImages] = {}
var _entry_order: Array[Vector4i] = []
var _temporary_keys: Array[Vector4i] = []
# A prediction contains at most one entry per writable gameplay stratum. The
# renderer replaces the entire set at the next swing, so misses and long runs
# cannot grow this dictionary.
var _prepared_entries: Dictionary[Vector4i, StampImages] = {}
# Oriented sources share the resized-entry LRU limit and use the same eviction
# order. Setting the limit to zero disables both reusable caches.
var _oriented_sources: Dictionary[Vector2i, OrientedSources] = {}
var _oriented_source_order: Array[Vector2i] = []
var _entry_limit: int = 0
var _maximum_entry_pixels: int = 1


## Starts a fresh cache with the renderer's authored web-performance bounds.
func reset(entry_limit: int, maximum_entry_pixels: int) -> void:
	entries.clear()
	_entry_order.clear()
	_temporary_keys.clear()
	_prepared_entries.clear()
	_oriented_sources.clear()
	_oriented_source_order.clear()
	_entry_limit = maxi(entry_limit, 0)
	_maximum_entry_pixels = maxi(maximum_entry_pixels, 1)


## Starts another candidate batch. An exact swing can keep completed candidate
## entries and promote its matching keys to committed ownership at impact.
func begin_preparation(clear_completed: bool = true) -> void:
	if clear_completed:
		_prepared_entries.clear()


## Drops unmatched candidates after authoritative keys have been promoted.
func discard_prepared() -> void:
	_prepared_entries.clear()


## Returns identically transformed erase and fracture channels for one stamp.
func get_images(
	cache_id: int,
	erase_mask: Image,
	fracture_source: Image,
	include_fracture_lines: bool,
	stamp_size: Vector2i,
	flip_x: bool,
	flip_y: bool,
	rotation_quarters: int,
	is_preparation: bool = false
) -> StampImages:
	var preparation := start_image_preparation(
		cache_id,
		erase_mask,
		fracture_source,
		include_fracture_lines,
		stamp_size,
		flip_x,
		flip_y,
		rotation_quarters,
		is_preparation
	)
	while not advance_image_preparation(preparation):
		pass
	return preparation.stamp_images


## Starts one portable, incrementally resizable image set. Horizontal resize and
## bounded row-copy phases let the renderer yield between pieces on web builds.
func start_image_preparation(
	cache_id: int,
	erase_mask: Image,
	fracture_source: Image,
	include_fracture_lines: bool,
	stamp_size: Vector2i,
	flip_x: bool,
	flip_y: bool,
	rotation_quarters: int,
	is_preparation: bool = false
) -> ImagePreparation:
	var orientation_flags := (
		(1 if flip_x else 0)
		| (2 if flip_y else 0)
		| (posmod(rotation_quarters, 4) << 2)
		| (16 if include_fracture_lines else 0)
	)
	var cache_key := Vector4i(
		cache_id,
		stamp_size.x,
		stamp_size.y,
		orientation_flags
	)
	var can_cache := (
		_entry_limit > 0
		and stamp_size.x * stamp_size.y <= _maximum_entry_pixels
	)
	var prepared_images: StampImages = _prepared_entries.get(cache_key)
	if prepared_images != null:
		if not is_preparation:
			_store_committed_images(
				cache_key,
				prepared_images,
				can_cache
			)
		var prepared_result := ImagePreparation.new()
		prepared_result.stamp_images = prepared_images
		prepared_result.completed = true
		return prepared_result
	var cached_images: StampImages = entries.get(cache_key)
	if cached_images != null:
		if can_cache:
			_entry_order.erase(cache_key)
			_entry_order.append(cache_key)
		var cached_result := ImagePreparation.new()
		cached_result.stamp_images = cached_images
		cached_result.completed = true
		return cached_result

	var preparation := ImagePreparation.new()
	preparation.cache_key = cache_key
	preparation.can_cache = can_cache
	preparation.is_speculative = is_preparation
	preparation.stamp_size = stamp_size
	preparation.oriented = _get_oriented_sources(
		cache_id,
		orientation_flags,
		erase_mask,
		fracture_source,
		include_fracture_lines,
		flip_x,
		flip_y,
		rotation_quarters
	)
	preparation.stamp_images = StampImages.new()
	return preparation


## Advances one bounded resize phase. Returns true only after the exact image
## set has entered its speculative or committed cache generation.
func advance_image_preparation(
	preparation: ImagePreparation,
	row_budget: int = 192
) -> bool:
	if preparation.completed:
		return true
	match preparation.phase:
		0:
			preparation.stamp_images.erase_mask = Image.create(
				preparation.stamp_size.x,
				preparation.stamp_size.y,
				false,
				Image.FORMAT_LA8
			)
			preparation.horizontal_source = (
				preparation.oriented.erase_mask.duplicate()
			)
			if (
				preparation.horizontal_source.get_width()
				!= preparation.stamp_size.x
			):
				preparation.horizontal_source.resize(
					preparation.stamp_size.x,
					preparation.horizontal_source.get_height(),
					Image.INTERPOLATE_NEAREST
				)
			preparation.phase = 1
			return false
		1:
			preparation.next_row = _copy_resized_rows(
				preparation.horizontal_source,
				preparation.stamp_images.erase_mask,
				preparation.next_row,
				row_budget
			)
			if preparation.next_row < preparation.stamp_size.y:
				return false
			preparation.horizontal_source = null
			preparation.next_row = 0
			preparation.phase = 2
			return false
		2:
			if preparation.oriented.fracture_source == null:
				preparation.phase = 4
				return false
			preparation.stamp_images.fracture_source = Image.create(
				preparation.stamp_size.x,
				preparation.stamp_size.y,
				false,
				Image.FORMAT_LA8
			)
			preparation.horizontal_source = (
				preparation.oriented.fracture_source.duplicate()
			)
			if (
				preparation.horizontal_source.get_width()
				!= preparation.stamp_size.x
			):
				preparation.horizontal_source.resize(
					preparation.stamp_size.x,
					preparation.horizontal_source.get_height(),
					Image.INTERPOLATE_NEAREST
				)
			preparation.phase = 3
			return false
		3:
			preparation.next_row = _copy_resized_rows(
				preparation.horizontal_source,
				preparation.stamp_images.fracture_source,
				preparation.next_row,
				row_budget
			)
			if preparation.next_row < preparation.stamp_size.y:
				return false
			preparation.horizontal_source = null
			preparation.next_row = 0
			preparation.phase = 4
			return false
		4:
			preparation.stamp_images.transparent_source = Image.create(
				preparation.stamp_size.x,
				preparation.stamp_size.y,
				false,
				Image.FORMAT_LA8
			)
			# Image.create initializes LA8 storage to zero. Exact dimensions are
			# required because Image.blit_rect_mask validates both full images.
			if preparation.is_speculative:
				_prepared_entries[preparation.cache_key] = (
					preparation.stamp_images
				)
			else:
				_store_committed_images(
					preparation.cache_key,
					preparation.stamp_images,
					preparation.can_cache
				)
			preparation.completed = true
			return true
	return false


## Copies nearest-neighbor output rows from a horizontally resized source. This
## is byte-identical to the source-row mapping used by nearest Image.resize.
func _copy_resized_rows(
	horizontal_source: Image,
	destination: Image,
	first_row: int,
	row_budget: int
) -> int:
	var last_row := mini(
		first_row + maxi(row_budget, 1),
		destination.get_height()
	)
	var source_height := horizontal_source.get_height()
	var destination_height := destination.get_height()
	for destination_y in range(first_row, last_row):
		var source_y := mini(
			floori(
				float(destination_y)
				* float(source_height)
				/ float(destination_height)
			),
			source_height - 1
		)
		destination.blit_rect(
			horizontal_source,
			Rect2i(
				0,
				source_y,
				destination.get_width(),
				1
			),
			Vector2i(0, destination_y)
		)
	return last_row


func _get_oriented_sources(
	cache_id: int,
	orientation_flags: int,
	erase_mask: Image,
	fracture_source: Image,
	include_fracture_lines: bool,
	flip_x: bool,
	flip_y: bool,
	rotation_quarters: int
) -> OrientedSources:
	var oriented_key := Vector2i(cache_id, orientation_flags)
	var oriented: OrientedSources = _oriented_sources.get(oriented_key)
	if oriented == null:
		oriented = OrientedSources.new()
		oriented.erase_mask = _orient_source(
			erase_mask,
			flip_x,
			flip_y,
			rotation_quarters
		)
		if include_fracture_lines and fracture_source != null:
			oriented.fracture_source = _orient_source(
				fracture_source,
				flip_x,
				flip_y,
				rotation_quarters
			)
		if _entry_limit > 0:
			while _oriented_source_order.size() >= _entry_limit:
				var expired_orientation: Vector2i = (
					_oriented_source_order.pop_front()
				)
				_oriented_sources.erase(expired_orientation)
			_oriented_sources[oriented_key] = oriented
			_oriented_source_order.append(oriented_key)
	elif _entry_limit > 0:
		_oriented_source_order.erase(oriented_key)
		_oriented_source_order.append(oriented_key)
	return oriented


## Releases oversized one-operation images after every touched chunk used them.
func clear_temporary() -> void:
	for cache_key: Vector4i in _temporary_keys:
		entries.erase(cache_key)
	_temporary_keys.clear()


func _orient_source(
	source: Image,
	flip_x: bool,
	flip_y: bool,
	rotation_quarters: int
) -> Image:
	var transformed := source.duplicate()
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
	return transformed


## Gives an image set normal cache lifetime before deferred bands consume it.
func _store_committed_images(
	cache_key: Vector4i,
	stamp_images: StampImages,
	can_cache: bool
) -> void:
	if entries.has(cache_key):
		return
	if not can_cache:
		entries[cache_key] = stamp_images
		_temporary_keys.append(cache_key)
		return
	while _entry_order.size() >= _entry_limit:
		var expired_key: Vector4i = _entry_order.pop_front()
		entries.erase(expired_key)
	entries[cache_key] = stamp_images
	_entry_order.append(cache_key)
