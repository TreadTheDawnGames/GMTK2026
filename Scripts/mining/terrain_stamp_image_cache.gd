extends RefCounted

## How it works:
## - Accepts authored erase/fracture images plus one requested orientation.
## - Resizes both channels with the filtering appropriate to their purpose.
## - Keeps bounded reusable results under deterministic stamp keys.
## - Keeps oversized results only for the current synchronous terrain update.
## - Exposes entries read-only for renderer diagnostics and benchmark checks.
## - The invariant is that erase masks remain hard-edged after transformation.

class StampImages:
	var erase_mask: Image
	var transparent_source: Image
	var fracture_source: Image


var entries: Dictionary[Vector4i, StampImages] = {}
var _entry_order: Array[Vector4i] = []
var _temporary_keys: Array[Vector4i] = []
var _entry_limit: int = 0
var _maximum_entry_pixels: int = 1


## Starts a fresh cache with the renderer's authored web-performance bounds.
func reset(entry_limit: int, maximum_entry_pixels: int) -> void:
	entries.clear()
	_entry_order.clear()
	_temporary_keys.clear()
	_entry_limit = maxi(entry_limit, 0)
	_maximum_entry_pixels = maxi(maximum_entry_pixels, 1)


## Returns identically transformed erase and fracture channels for one stamp.
func get_images(
	cache_id: int,
	erase_mask: Image,
	fracture_source: Image,
	stamp_size: Vector2i,
	flip_x: bool,
	flip_y: bool,
	rotation_quarters: int
) -> StampImages:
	var orientation_flags := (
		(1 if flip_x else 0)
		| (2 if flip_y else 0)
		| (posmod(rotation_quarters, 4) << 2)
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
	var cached_images: StampImages = entries.get(cache_key)
	if cached_images != null:
		if can_cache:
			_entry_order.erase(cache_key)
			_entry_order.append(cache_key)
		return cached_images

	var stamp_images := StampImages.new()
	# blit_rect_mask treats every nonzero alpha as a full cut. Nearest-neighbor
	# keeps the erase channel on the artist's hard silhouette; bilinear filtering
	# remains correct for the independently blended fracture artwork.
	stamp_images.erase_mask = _transform_image(
		erase_mask,
		stamp_size,
		flip_x,
		flip_y,
		rotation_quarters,
		Image.INTERPOLATE_NEAREST
	)
	stamp_images.fracture_source = _transform_image(
		fracture_source,
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
	stamp_images.transparent_source.fill(Color.TRANSPARENT)

	if not can_cache:
		entries[cache_key] = stamp_images
		_temporary_keys.append(cache_key)
		return stamp_images
	while _entry_order.size() >= _entry_limit:
		var expired_key: Vector4i = _entry_order.pop_front()
		entries.erase(expired_key)
	entries[cache_key] = stamp_images
	_entry_order.append(cache_key)
	return stamp_images


## Releases oversized one-operation images after every touched chunk used them.
func clear_temporary() -> void:
	for cache_key: Vector4i in _temporary_keys:
		entries.erase(cache_key)
	_temporary_keys.clear()


func _transform_image(
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
