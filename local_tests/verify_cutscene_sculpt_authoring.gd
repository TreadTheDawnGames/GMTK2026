extends SceneTree

## How it works:
## - Exercises every terrain gesture against small in-memory sculpt resources.
## - Checks exact drag geometry, selection copying/transforms, stratum targeting,
##   guarded-floor reads, and the five fixed room stamps.
## - Writes no project resources and exits nonzero with actionable failures.
## The invariant is that identical authoring input changes the same bounded cells.

const GRID_SIZE := Vector2i(64, 64)
const FLOOR_ROW: int = 56
var _failures: Array[String] = []
var _brush := CutsceneSculptBrush.new()

func _initialize() -> void:
	_verify_drag_shapes()
	_verify_selection_tools()
	_verify_layer_and_floor_contracts()
	_verify_builtin_stamps()
	_verify_panel_contract()
	_report()
func _verify_drag_shapes() -> void:
	var rectangle_sculpt := _new_sculpt(true)
	var rectangle_changed := _brush.stamp_shape(
		rectangle_sculpt,
		Vector2(5.0, 6.0),
		Vector2(14.0, 11.0),
		CutsceneSculptBrush.OP_CARVE,
		CutsceneSculptBrush.SHAPE_RECTANGLE
	)
	_expect_equal(rectangle_changed, 60, "Rectangle changed-cell count")
	_expect(
		not rectangle_sculpt.is_solid_local(Vector2i(5, 6)),
		"Rectangle missed its first corner."
	)
	_expect(
		not rectangle_sculpt.is_solid_local(Vector2i(14, 11)),
		"Rectangle missed its opposite corner."
	)
	_expect(
		rectangle_sculpt.is_solid_local(Vector2i(15, 11)),
		"Rectangle wrote outside its inclusive drag bounds."
	)

	var ellipse_sculpt := _new_sculpt(true)
	var ellipse_cells := _brush.preview_shape_cells(
		ellipse_sculpt,
		Vector2(20.0, 18.0),
		Vector2(30.0, 24.0),
		CutsceneSculptBrush.SHAPE_ELLIPSE
	)
	for cell: Vector2i in ellipse_cells:
		var reflected := Vector2i(50 - cell.x, 42 - cell.y)
		_expect(
			reflected in ellipse_cells,
			"Ellipse is not symmetric at %s." % cell
		)
	var ellipse_changed := _brush.stamp_shape(
		ellipse_sculpt,
		Vector2(20.0, 18.0),
		Vector2(30.0, 24.0),
		CutsceneSculptBrush.OP_CARVE,
		CutsceneSculptBrush.SHAPE_ELLIPSE
	)
	_expect_equal(
		ellipse_changed,
		ellipse_cells.size(),
		"Ellipse preview/apply parity"
	)

	_brush.radius_cells = 2.0
	var line_sculpt := _new_sculpt(true)
	var line_cells := _brush.preview_shape_cells(
		line_sculpt,
		Vector2(8.0, 8.0),
		Vector2(25.0, 13.0),
		CutsceneSculptBrush.SHAPE_LINE
	)
	var unique_line_cells: Dictionary = {}
	for cell: Vector2i in line_cells:
		unique_line_cells[cell] = true
	_expect_equal(
		unique_line_cells.size(),
		line_cells.size(),
		"Line preview contains no duplicate cells"
	)
	_brush.stamp_shape(
		line_sculpt,
		Vector2(8.0, 8.0),
		Vector2(25.0, 13.0),
		CutsceneSculptBrush.OP_CARVE,
		CutsceneSculptBrush.SHAPE_LINE
	)
	for cell: Vector2i in line_cells:
		_expect(
			not line_sculpt.is_solid_local(cell),
			"Line previewed cell %s was not carved." % cell
		)

func _verify_selection_tools() -> void:
	var sculpt := _new_sculpt(false)
	var source_region := Rect2i(2, 3, 3, 2)
	var source_values: Array[bool] = [
		true, false, false,
		false, true, false,
	]
	for source_index in range(source_values.size()):
		var source_cell := source_region.position + Vector2i(
			source_index % source_region.size.x,
			source_index / source_region.size.x
		)
		sculpt.set_solid_local(source_cell, source_values[source_index])

	var copied := _brush.copy_region(sculpt, source_region)
	var paste_origin := Vector2i(12, 10)
	var pasted := _brush.paste_region(sculpt, paste_origin, copied)
	_expect_equal(pasted, 2, "Selection paste changed-cell count")
	for source_index in range(source_values.size()):
		var pasted_cell := paste_origin + Vector2i(
			source_index % source_region.size.x,
			source_index / source_region.size.x
		)
		_expect_equal(
			sculpt.is_solid_local(pasted_cell),
			source_values[source_index],
			"Selection paste cell %s" % pasted_cell
		)

	_brush.mirror_region_horizontal(
		sculpt,
		Rect2i(paste_origin, source_region.size)
	)
	for source_index in range(source_values.size()):
		var local_x := source_index % source_region.size.x
		var local_y := source_index / source_region.size.x
		var mirrored_source_index := (
			local_y * source_region.size.x
			+ source_region.size.x - 1 - local_x
		)
		var mirrored_cell := paste_origin + Vector2i(local_x, local_y)
		_expect_equal(
			sculpt.is_solid_local(mirrored_cell),
			source_values[mirrored_source_index],
			"Selection mirror cell %s" % mirrored_cell
		)

	var fill_region := Rect2i(35, 8, 4, 5)
	var filled := _brush.fill_region(
		sculpt,
		fill_region,
		CutsceneSculptBrush.OP_FILL
	)
	_expect_equal(filled, 20, "Selection fill changed-cell count")

func _verify_layer_and_floor_contracts() -> void:
	var sculpt := _new_sculpt(true)
	sculpt.ensure_layer_masks(2)
	_brush.target_layer = 1
	var layer_changed := _brush.fill_region(
		sculpt,
		Rect2i(7, 7, 5, 5),
		CutsceneSculptBrush.OP_CARVE
	)
	_expect_equal(layer_changed, 25, "Layer-only changed-cell count")
	var layer_cell := Vector2i(8, 8)
	_expect(
		sculpt.is_solid_local(layer_cell),
		"Layer-only edit changed logical terrain."
	)
	_expect(
		sculpt.is_layer_solid_local(0, layer_cell),
		"Layer-only edit changed an unselected stratum."
	)
	_expect(
		not sculpt.is_layer_solid_local(1, layer_cell),
		"Layer-only edit missed the selected stratum."
	)

	_brush.target_layer = -1
	_brush.fill_region(
		sculpt,
		Rect2i(0, FLOOR_ROW, GRID_SIZE.x, 3),
		CutsceneSculptBrush.OP_CARVE
	)
	for local_y in range(FLOOR_ROW, FLOOR_ROW + 3):
		for local_x in range(GRID_SIZE.x):
			var floor_cell := Vector2i(local_x, local_y)
			_expect(
				sculpt.is_solid_local(floor_cell),
				"Guarded floor became logically open at %s." % floor_cell
			)
			_expect(
				sculpt.is_layer_solid_local(1, floor_cell),
				"Guarded floor disappeared from a stratum at %s." % floor_cell
			)

func _verify_builtin_stamps() -> void:
	var carve_stamps: Array[StringName] = [
		CutsceneSculptBrush.STAMP_DOORWAY,
		CutsceneSculptBrush.STAMP_ALCOVE,
		CutsceneSculptBrush.STAMP_TUNNEL,
	]
	for stamp: StringName in carve_stamps:
		var sculpt := _new_sculpt(true)
		var cells := _brush.preview_builtin_stamp_cells(
			sculpt,
			Vector2i(32, 28),
			stamp
		)
		var changed := _brush.apply_builtin_stamp(
			sculpt,
			Vector2i(32, 28),
			stamp
		)
		_expect(not cells.is_empty(), "Stamp '%s' has no cells." % stamp)
		_expect_equal(
			changed,
			cells.size(),
			"Carving stamp '%s' preview/apply parity" % stamp
		)

	var fill_stamps: Array[StringName] = [
		CutsceneSculptBrush.STAMP_PLATFORM,
		CutsceneSculptBrush.STAMP_PILLAR,
	]
	for stamp: StringName in fill_stamps:
		var sculpt := _new_sculpt(false)
		var cells := _brush.preview_builtin_stamp_cells(
			sculpt,
			Vector2i(32, 28),
			stamp
		)
		var changed := _brush.apply_builtin_stamp(
			sculpt,
			Vector2i(32, 28),
			stamp
		)
		_expect_equal(
			changed,
			cells.size(),
			"Filling stamp '%s' preview/apply parity" % stamp
		)

func _verify_panel_contract() -> void:
	var panel := CutsceneSculptPanel.new()
	root.add_child(panel)
	panel.select_shape_tool(CutsceneSculptBrush.SHAPE_RECTANGLE)
	_expect_equal(
		panel.get_shape_tool(), CutsceneSculptBrush.SHAPE_RECTANGLE,
		"Panel shape selection",
	)
	panel.set_selection(Rect2i(3, 4, 6, 7))
	_expect(panel.has_selection(), "Panel did not retain its selection.")
	_expect_equal(
		panel.get_selection(), Rect2i(3, 4, 6, 7),
		"Panel selection rectangle",
	)
	panel.set_selection_clipboard({
		"size": Vector2i(2, 2),
		"cells": PackedByteArray([1, 0, 0, 1]),
	})
	_expect(
		panel.has_selection_clipboard(),
		"Panel did not retain its bounded selection clipboard."
	)
	panel.clear_selection()
	_expect(not panel.has_selection(), "Panel did not clear its selection.")
	panel.free()

func _new_sculpt(solid: bool) -> CutsceneTerrainSculpt:
	var sculpt := CutsceneTerrainSculpt.new()
	sculpt.grid_size = GRID_SIZE
	sculpt.anchor_offset_cells = Vector2i(-32, -FLOOR_ROW)
	sculpt.protected_floor_rows = 3
	sculpt.fill_all(solid)
	return sculpt

func _expect(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)

func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures.append(
			"%s: expected %s, got %s." % [label, expected, actual]
		)

func _report() -> void:
	if _failures.is_empty():
		print("CUTSCENE_SCULPT_AUTHORING_VERIFY: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("CUTSCENE_SCULPT_AUTHORING_FAIL: %s" % failure)
	print(
		"CUTSCENE_SCULPT_AUTHORING_VERIFY: FAIL (%d)"
		% _failures.size()
	)
	quit(1)
