@tool
class_name ActorSoleMeasure
extends RefCounted

## How it works:
## - Answers where a CharacterAppearance's sprite must sit so its lowest drawn
##   row lands on the actor node's origin.
## - Actor origins represent feet; terrain placement assigns that origin a floor.
## - Measurements are cached per texture frame because source sheets are large.
## - Runtime presenters and editor stand-ins share this implementation.
## - The invariant is that this reads art and never mutates a node.

## Sole offsets in texture pixels, keyed by texture path and frame.
static var _sole_cache: Dictionary = {}


## Returns the sprite y, in world pixels, that stands this appearance's drawn
## sole on the actor's origin. Empty art remains centred on the origin.
static func get_sprite_y(appearance: CharacterAppearance) -> float:
	if appearance == null or appearance.texture == null:
		return 0.0
	var measured := measure_frame_sole(
		appearance.texture,
		appearance.horizontal_frames,
		appearance.vertical_frames,
		appearance.frame
	)
	if is_nan(measured):
		return 0.0
	return -measured * appearance.sprite_scale.y


## Returns how far one frame's lowest drawn row falls below its centre, in
## texture pixels. NAN means that the selected frame draws nothing.
static func measure_frame_sole(
	texture: Texture2D,
	columns: int,
	rows: int,
	frame_index: int
) -> float:
	if texture == null:
		return NAN
	var column_count := maxi(columns, 1)
	var row_count := maxi(rows, 1)
	var cache_key := "%s#%d/%dx%d" % [
		texture.resource_path,
		frame_index,
		column_count,
		row_count,
	]
	if _sole_cache.has(cache_key):
		return float(_sole_cache[cache_key])

	var image := texture.get_image()
	if image == null:
		return NAN
	var frame_width := image.get_width() / column_count
	var frame_height := image.get_height() / row_count
	if frame_width <= 0 or frame_height <= 0:
		return NAN
	var index := clampi(frame_index, 0, column_count * row_count - 1)
	var frame_image := (
		image
		if column_count * row_count == 1
		else image.get_region(Rect2i(
			(index % column_count) * frame_width,
			(index / column_count) * frame_height,
			frame_width,
			frame_height
		))
	)
	var opaque := frame_image.get_used_rect()
	if opaque.size.y <= 0:
		return NAN
	var sole := (
		float(opaque.position.y + opaque.size.y)
		- float(frame_height) * 0.5
	)
	_sole_cache[cache_key] = sole
	return sole
