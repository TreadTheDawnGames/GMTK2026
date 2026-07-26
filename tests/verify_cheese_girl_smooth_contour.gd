extends SceneTree

## How it works:
## - Rasterizes the same stepped room with contour rounding disabled and enabled.
## - Compares the bounded transition band produced by the shared room renderer.
## - Verifies Encounter 1 explicitly opts in while shared defaults remain off.
## - The invariant is that smoothing changes presentation only, never collision.

const _ENCOUNTER_SCULPT_PATH := (
	"res://resources/cinematics/sculpts/cheese_girl_first_room.tres"
)
const _PROFILE_PATH := (
	"res://resources/mining/default_terrain_layer_profile.tres"
)

var _failures: PackedStringArray = []


func _initialize() -> void:
	var shipped_sculpt := load(_ENCOUNTER_SCULPT_PATH) as CutsceneTerrainSculpt
	_expect(shipped_sculpt != null, "Encounter 1 sculpt must load.")
	if shipped_sculpt != null:
		_expect(
			is_equal_approx(shipped_sculpt.contour_rounding_cells, 2.0),
			"Encounter 1 must opt into two-cell contour rounding."
		)
	_verify_raster_rounding()
	if _failures.is_empty():
		print("CHEESE_GIRL_SMOOTH_CONTOUR_PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _verify_raster_rounding() -> void:
	var renderer := TerrainLayerRenderer.new()
	renderer.profile = load(_PROFILE_PATH) as TerrainLayerProfile
	var sculpt := _build_stepped_sculpt()
	var logical_bits := sculpt.solid_bits.duplicate()
	var square_mask := renderer.call(
		"_rasterize_sculpt_mask",
		sculpt,
		-1
	) as Image
	sculpt.contour_rounding_cells = 2.0
	var rounded_mask := renderer.call(
		"_rasterize_sculpt_mask",
		sculpt,
		-1
	) as Image
	_expect(square_mask != null, "Square contour raster must be produced.")
	_expect(rounded_mask != null, "Rounded contour raster must be produced.")
	if square_mask != null and rounded_mask != null:
		_expect(
			_count_transition_pixels(rounded_mask)
				> _count_transition_pixels(square_mask),
			"Contour rounding must widen the sub-cell transition band."
		)
	_expect(
		sculpt.solid_bits == logical_bits,
		"Contour rounding must not mutate logical collision bits."
	)
	renderer.free()


func _build_stepped_sculpt() -> CutsceneTerrainSculpt:
	var sculpt := CutsceneTerrainSculpt.new()
	sculpt.grid_size = Vector2i(16, 16)
	sculpt.protected_floor_rows = 0
	sculpt.edge_smoothing = 1.0
	for local_y in range(sculpt.grid_size.y):
		var open_until_x := 3 + local_y / 2
		for local_x in range(sculpt.grid_size.x):
			sculpt.set_solid_local(
				Vector2i(local_x, local_y),
				local_x >= open_until_x
			)
	return sculpt


func _count_transition_pixels(image: Image) -> int:
	var transition_pixels := 0
	for image_y in range(image.get_height()):
		for image_x in range(image.get_width()):
			var alpha := image.get_pixel(image_x, image_y).a
			if alpha > 0.05 and alpha < 0.95:
				transition_pixels += 1
	return transition_pixels


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
