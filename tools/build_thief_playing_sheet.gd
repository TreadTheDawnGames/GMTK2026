extends SceneTree

## Prepares the Thief finale's art and reports the numbers it has to be placed by.
##
## How it works:
## - Zephan's frames arrive as separate 1668x2224 PNGs that are almost entirely
##   transparent. Trimming them to their opaque content and packing the figure's
##   three frames into one sheet is what lets the shot animate at all, and takes
##   roughly nine tenths of the texture off a web export that has to hold it.
## - The three figure frames are trimmed to their SHARED opaque rect, not to
##   their own. Trimming each to its own bounds would re-centre every frame and
##   the hands would jump around the keyboard between them.
## - It prints the measured opaque size of everything it writes, because the
##   house rule is that spacing is measured rather than guessed, and these are
##   the only numbers the stage can be authored against.
## - Re-running is safe: it reads the individual frames, which stay in the repo
##   as the source the sheet is built from, and rewrites the outputs.

const FIGURE_FRAME_PATHS: PackedStringArray = [
	"res://Assets/Characters/thief/thief_playing_0.png",
	"res://Assets/Characters/thief/thief_playing_1.png",
	"res://Assets/Characters/thief/thief_playing_2.png",
]
const FIGURE_SHEET_PATH: String = (
	"res://Assets/Characters/thief/thief_playing_sheet.png"
)
const ORGAN_SOURCE_PATH: String = "res://Assets/Props/organ.png"


func _initialize() -> void:
	if not _build_figure_sheet():
		quit(1)
		return
	if not _trim_organ():
		quit(1)
		return
	quit(0)


## Packs the figure's frames into one trimmed horizontal sheet.
func _build_figure_sheet() -> bool:
	var frames: Array[Image] = []
	var shared_rect := Rect2i()
	for frame_path in FIGURE_FRAME_PATHS:
		var frame := _load_image(frame_path)
		if frame == null:
			return false
		frames.append(frame)
		var used := frame.get_used_rect()
		shared_rect = (
			used if shared_rect.size == Vector2i.ZERO else shared_rect.merge(used)
		)
	if shared_rect.size == Vector2i.ZERO:
		push_error("Every thief frame is fully transparent.")
		return false

	var sheet := Image.create_empty(
		shared_rect.size.x * frames.size(),
		shared_rect.size.y,
		false,
		Image.FORMAT_RGBA8
	)
	for frame_index in range(frames.size()):
		sheet.blit_rect(
			frames[frame_index],
			shared_rect,
			Vector2i(shared_rect.size.x * frame_index, 0)
		)
	var save_error := sheet.save_png(FIGURE_SHEET_PATH)
	if save_error != OK:
		push_error(
			"Could not write the thief sheet: %s" % error_string(save_error)
		)
		return false
	print("THIEF_ART sheet=%s" % FIGURE_SHEET_PATH)
	print(
		"  frames=%d frame_size=%dx%d sheet_size=%dx%d"
		% [
			frames.size(),
			shared_rect.size.x,
			shared_rect.size.y,
			sheet.get_width(),
			sheet.get_height(),
		]
	)
	print(
		"  widest_opaque_row=%d (this is the body width to space against)"
		% _get_widest_opaque_row(frames[0], shared_rect)
	)
	return true


## Trims the organ to its own opaque content in place.
func _trim_organ() -> bool:
	var organ := _load_image(ORGAN_SOURCE_PATH)
	if organ == null:
		return false
	var used := organ.get_used_rect()
	if used.size == Vector2i.ZERO:
		push_error("The organ image is fully transparent.")
		return false
	if used.position == Vector2i.ZERO and used.size == organ.get_size():
		print("THIEF_ART organ already trimmed: %dx%d" % [used.size.x, used.size.y])
		return true
	var trimmed := Image.create_empty(
		used.size.x,
		used.size.y,
		false,
		Image.FORMAT_RGBA8
	)
	trimmed.blit_rect(organ, used, Vector2i.ZERO)
	var save_error := trimmed.save_png(ORGAN_SOURCE_PATH)
	if save_error != OK:
		push_error("Could not write the organ: %s" % error_string(save_error))
		return false
	print("THIEF_ART organ=%s" % ORGAN_SOURCE_PATH)
	print("  trimmed to %dx%d" % [used.size.x, used.size.y])
	return true


## Returns the widest single row of opaque pixels, which is the body width the
## authoring guide's spacing table is built from. A bounding box is not the same
## number: it unions the widest point at one height with the tallest at another.
func _get_widest_opaque_row(source: Image, region: Rect2i) -> int:
	var widest := 0
	for row in range(region.position.y, region.end.y):
		var first_opaque := -1
		var last_opaque := -1
		for column in range(region.position.x, region.end.x):
			if source.get_pixel(column, row).a <= 0.0:
				continue
			if first_opaque < 0:
				first_opaque = column
			last_opaque = column
		if first_opaque >= 0:
			widest = maxi(widest, last_opaque - first_opaque + 1)
	return widest


## Loads one PNG straight off disk, bypassing the import cache.
func _load_image(path: String) -> Image:
	var absolute_path := ProjectSettings.globalize_path(path)
	var image := Image.new()
	if image.load(absolute_path) != OK:
		push_error("Could not read %s" % path)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image
