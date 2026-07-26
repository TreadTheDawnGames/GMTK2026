@tool
class_name CutsceneSculptBrush
extends RefCounted

## How it works:
## - Samples a deterministic, falloff-weighted disc in local cell coordinates.
## - Owns only brush settings, returns changed-cell counts, and previews cells.
## - Carve/fill change the logical mask, while a selected layer changes only its
##   visible mask; default logical edits keep existing masks synchronized.
## - Smooth and roughen read a brush-sized snapshot before writing any result.
## - Line stamps reuse the same operation and sample no farther than half a cell.
## - Drag shapes, selection transforms, and five fixed room stamps use the same
##   target-layer write path, so shape edits and brush edits cannot disagree.
## The invariant is that every edit is deterministic for its seed and cell, and
## no brush operation writes outside the sculpt grid.

const OP_CARVE: StringName = &"carve"
const OP_FILL: StringName = &"fill"
const OP_SMOOTH: StringName = &"smooth"
const OP_ROUGHEN: StringName = &"roughen"

const SHAPE_FREE: StringName = &"free"
const SHAPE_LINE: StringName = &"line"
const SHAPE_RECTANGLE: StringName = &"rectangle"
const SHAPE_ELLIPSE: StringName = &"ellipse"
const SHAPE_SELECTION: StringName = &"selection"
const SHAPE_STAMP: StringName = &"stamp"

const STAMP_DOORWAY: StringName = &"doorway"
const STAMP_ALCOVE: StringName = &"alcove"
const STAMP_PLATFORM: StringName = &"platform"
const STAMP_PILLAR: StringName = &"pillar"
const STAMP_TUNNEL: StringName = &"tunnel"

const _SELECTION_SALT: int = 17
const _ROUGHEN_SALT: int = 43

const _STAMP_DOORWAY_SIZE := Vector2i(9, 19)
const _STAMP_ALCOVE_SIZE := Vector2i(25, 15)
const _STAMP_PLATFORM_SIZE := Vector2i(25, 3)
const _STAMP_PILLAR_SIZE := Vector2i(5, 21)
const _STAMP_TUNNEL_SIZE := Vector2i(29, 9)

var radius_cells: float = 6.0
var strength: float = 1.0
var falloff: float = 0.5
var target_layer: int = -1
var seed_value: int = 0


func carve(sculpt: CutsceneTerrainSculpt, center: Vector2) -> int:
	sculpt.begin_edit()
	var changed := _apply_direct(sculpt, center, false)
	sculpt.end_edit()
	return changed


func fill(sculpt: CutsceneTerrainSculpt, center: Vector2) -> int:
	sculpt.begin_edit()
	var changed := _apply_direct(sculpt, center, true)
	sculpt.end_edit()
	return changed


func smooth(sculpt: CutsceneTerrainSculpt, center: Vector2) -> int:
	sculpt.begin_edit()
	var changed := _apply_smooth(sculpt, center)
	sculpt.end_edit()
	return changed


func roughen(sculpt: CutsceneTerrainSculpt, center: Vector2) -> int:
	sculpt.begin_edit()
	var changed := _apply_roughen(sculpt, center)
	sculpt.end_edit()
	return changed


func stamp_line(
	sculpt: CutsceneTerrainSculpt,
	from_center: Vector2,
	to_center: Vector2,
	operation: StringName
) -> int:
	sculpt.begin_edit()
	var changed := 0
	var distance := from_center.distance_to(to_center)
	var step_count := maxi(1, ceili(distance * 2.0))
	for step_index in range(step_count + 1):
		var progress := float(step_index) / float(step_count)
		var center := from_center.lerp(to_center, progress)
		changed += _apply_named_operation(sculpt, center, operation)
	sculpt.end_edit()
	return changed


## Applies the concrete drag tools. Selection is deliberately read-only; the
## plugin records its rectangle and calls fill_region when the designer asks
## to apply the armed operation.
func stamp_shape(
	sculpt: CutsceneTerrainSculpt,
	from_center: Vector2,
	to_center: Vector2,
	operation: StringName,
	shape: StringName
) -> int:
	match shape:
		SHAPE_FREE:
			sculpt.begin_edit()
			var changed := _apply_named_operation(
				sculpt,
				to_center,
				operation
			)
			sculpt.end_edit()
			return changed
		SHAPE_LINE:
			return stamp_line(sculpt, from_center, to_center, operation)
		SHAPE_RECTANGLE, SHAPE_ELLIPSE:
			var cells := preview_shape_cells(
				sculpt,
				from_center,
				to_center,
				shape
			)
			return _apply_exact_cells(sculpt, cells, operation)
	return 0


## Returns the exact cells a drag tool will affect. Free and line preserve the
## current round brush; rectangle and ellipse use their inclusive drag bounds.
func preview_shape_cells(
	sculpt: CutsceneTerrainSculpt,
	from_center: Vector2,
	to_center: Vector2,
	shape: StringName
) -> Array[Vector2i]:
	match shape:
		SHAPE_FREE:
			return preview_cells(sculpt, to_center)
		SHAPE_LINE:
			return _preview_line_cells(sculpt, from_center, to_center)
		SHAPE_RECTANGLE:
			return _rectangle_cells(
				sculpt,
				normalize_region(
					Vector2i(floor(from_center)),
					Vector2i(floor(to_center))
				)
			)
		SHAPE_ELLIPSE:
			return _ellipse_cells(
				sculpt,
				normalize_region(
					Vector2i(floor(from_center)),
					Vector2i(floor(to_center))
				)
			)
	return []


## Builds an inclusive cell rectangle regardless of drag direction.
func normalize_region(from_cell: Vector2i, to_cell: Vector2i) -> Rect2i:
	var minimum := Vector2i(
		mini(from_cell.x, to_cell.x),
		mini(from_cell.y, to_cell.y)
	)
	var maximum := Vector2i(
		maxi(from_cell.x, to_cell.x),
		maxi(from_cell.y, to_cell.y)
	)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)


## Applies a carve/fill/smooth/roughen operation once across a selection.
func fill_region(
	sculpt: CutsceneTerrainSculpt,
	region: Rect2i,
	operation: StringName
) -> int:
	return _apply_exact_cells(
		sculpt,
		_rectangle_cells(sculpt, region),
		operation
	)


## Copies the active shape or stratum from one bounded region. The clipboard
## is capped by CutsceneTerrainSculpt's 512 x 512 grid maximum and exists only
## in editor memory; it is never written into a game resource.
func copy_region(
	sculpt: CutsceneTerrainSculpt,
	region: Rect2i
) -> Dictionary:
	var clipped := region.intersection(
		Rect2i(Vector2i.ZERO, sculpt.grid_size)
	)
	var cells := PackedByteArray()
	if not clipped.has_area():
		return {
			"size": Vector2i.ZERO,
			"cells": cells,
		}
	cells.resize(clipped.size.x * clipped.size.y)
	for local_y in range(clipped.size.y):
		for local_x in range(clipped.size.x):
			var source := clipped.position + Vector2i(local_x, local_y)
			cells[local_y * clipped.size.x + local_x] = (
				1 if _target_value(sculpt, source) else 0
			)
	return {
		"size": clipped.size,
		"cells": cells,
	}


## Pastes copied cells at a new top-left corner. Passing true mirrors the copy
## while pasting without mutating the clipboard.
func paste_region(
	sculpt: CutsceneTerrainSculpt,
	top_left: Vector2i,
	copied_region: Dictionary,
	mirror_horizontal: bool = false
) -> int:
	var region_size: Vector2i = copied_region.get("size", Vector2i.ZERO)
	var cells: PackedByteArray = copied_region.get(
		"cells",
		PackedByteArray()
	)
	if (
		region_size.x <= 0
		or region_size.y <= 0
		or cells.size() < region_size.x * region_size.y
	):
		return 0
	sculpt.begin_edit()
	var changed := 0
	for local_y in range(region_size.y):
		for local_x in range(region_size.x):
			var source_x := (
				region_size.x - 1 - local_x
				if mirror_horizontal
				else local_x
			)
			var source_index := local_y * region_size.x + source_x
			var target := top_left + Vector2i(local_x, local_y)
			if (
				sculpt.contains_local(target)
				and _set_target_value(sculpt, target, cells[source_index] != 0)
			):
				changed += 1
	sculpt.end_edit()
	return changed


## Mirrors the selected shape/stratum in place using a snapshot, so every
## source cell is read before its reflected target is written.
func mirror_region_horizontal(
	sculpt: CutsceneTerrainSculpt,
	region: Rect2i
) -> int:
	var clipped := region.intersection(
		Rect2i(Vector2i.ZERO, sculpt.grid_size)
	)
	if not clipped.has_area():
		return 0
	var copied := copy_region(sculpt, clipped)
	return paste_region(sculpt, clipped.position, copied, true)


## Applies one of the five room-authoring stamps. Doorways, alcoves and tunnels
## always carve; platforms and pillars always fill, because those nouns have a
## stable terrain meaning and should not depend on whichever brush was armed.
func apply_builtin_stamp(
	sculpt: CutsceneTerrainSculpt,
	center: Vector2i,
	stamp: StringName
) -> int:
	var operation := get_builtin_stamp_operation(stamp)
	if operation.is_empty():
		return 0
	return _apply_exact_cells(
		sculpt,
		preview_builtin_stamp_cells(sculpt, center, stamp),
		operation
	)


func get_builtin_stamp_operation(stamp: StringName) -> StringName:
	match stamp:
		STAMP_DOORWAY, STAMP_ALCOVE, STAMP_TUNNEL:
			return OP_CARVE
		STAMP_PLATFORM, STAMP_PILLAR:
			return OP_FILL
	return &""


func preview_builtin_stamp_cells(
	sculpt: CutsceneTerrainSculpt,
	center: Vector2i,
	stamp: StringName
) -> Array[Vector2i]:
	match stamp:
		STAMP_DOORWAY:
			return _rectangle_cells(
				sculpt,
				_centered_region(center, _STAMP_DOORWAY_SIZE)
			)
		STAMP_ALCOVE:
			return _ellipse_cells(
				sculpt,
				_centered_region(center, _STAMP_ALCOVE_SIZE)
			)
		STAMP_PLATFORM:
			return _rectangle_cells(
				sculpt,
				_centered_region(center, _STAMP_PLATFORM_SIZE)
			)
		STAMP_PILLAR:
			return _rectangle_cells(
				sculpt,
				_centered_region(center, _STAMP_PILLAR_SIZE)
			)
		STAMP_TUNNEL:
			return _rectangle_cells(
				sculpt,
				_centered_region(center, _STAMP_TUNNEL_SIZE)
			)
	return []


func preview_cells(
	sculpt: CutsceneTerrainSculpt,
	center: Vector2
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var bounds := _brush_bounds(center, 0)
	for local_y in range(bounds.position.y, bounds.end.y):
		for local_x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(local_x, local_y)
			if not sculpt.contains_local(cell):
				continue
			if _brush_weight(center, cell) > 0.0:
				cells.append(cell)
	return cells


func _preview_line_cells(
	sculpt: CutsceneTerrainSculpt,
	from_center: Vector2,
	to_center: Vector2
) -> Array[Vector2i]:
	var unique_cells: Dictionary = {}
	var distance := from_center.distance_to(to_center)
	var step_count := maxi(1, ceili(distance * 2.0))
	for step_index in range(step_count + 1):
		var progress := float(step_index) / float(step_count)
		for cell in preview_cells(
			sculpt,
			from_center.lerp(to_center, progress)
		):
			unique_cells[cell] = true
	var cells: Array[Vector2i] = []
	for cell: Vector2i in unique_cells:
		cells.append(cell)
	cells.sort_custom(
		func(left: Vector2i, right: Vector2i) -> bool:
			return (
				left.y < right.y
				or (left.y == right.y and left.x < right.x)
			)
	)
	return cells


func _rectangle_cells(
	sculpt: CutsceneTerrainSculpt,
	region: Rect2i
) -> Array[Vector2i]:
	var clipped := region.intersection(
		Rect2i(Vector2i.ZERO, sculpt.grid_size)
	)
	var cells: Array[Vector2i] = []
	if not clipped.has_area():
		return cells
	for local_y in range(clipped.position.y, clipped.end.y):
		for local_x in range(clipped.position.x, clipped.end.x):
			cells.append(Vector2i(local_x, local_y))
	return cells


func _ellipse_cells(
	sculpt: CutsceneTerrainSculpt,
	region: Rect2i
) -> Array[Vector2i]:
	var clipped := region.intersection(
		Rect2i(Vector2i.ZERO, sculpt.grid_size)
	)
	var cells: Array[Vector2i] = []
	if not clipped.has_area():
		return cells
	var center := Vector2(region.position) + Vector2(region.size) * 0.5
	var radii := Vector2(region.size) * 0.5
	for local_y in range(clipped.position.y, clipped.end.y):
		for local_x in range(clipped.position.x, clipped.end.x):
			var sample := Vector2(local_x, local_y) + Vector2(0.5, 0.5)
			var normalized := Vector2(
				(sample.x - center.x) / maxf(radii.x, 0.5),
				(sample.y - center.y) / maxf(radii.y, 0.5)
			)
			if normalized.length_squared() <= 1.0:
				cells.append(Vector2i(local_x, local_y))
	return cells


func _centered_region(center: Vector2i, size: Vector2i) -> Rect2i:
	return Rect2i(center - size / 2, size)


func _apply_exact_cells(
	sculpt: CutsceneTerrainSculpt,
	cells: Array[Vector2i],
	operation: StringName
) -> int:
	if cells.is_empty():
		return 0
	sculpt.begin_edit()
	var changed := 0
	match operation:
		OP_CARVE, OP_FILL:
			var solid := operation == OP_FILL
			for cell in cells:
				if _set_target_value(sculpt, cell, solid):
					changed += 1
		OP_SMOOTH, OP_ROUGHEN:
			changed = _apply_filtered_cells(sculpt, cells, operation)
	sculpt.end_edit()
	return changed


func _apply_filtered_cells(
	sculpt: CutsceneTerrainSculpt,
	cells: Array[Vector2i],
	operation: StringName
) -> int:
	var area := _cell_bounds(cells).grow(1)
	var snapshot := _take_snapshot(sculpt, area)
	var changed := 0
	var salt := (
		_SELECTION_SALT
		if operation == OP_SMOOTH
		else _ROUGHEN_SALT
	)
	for cell in cells:
		if (
			not sculpt.contains_local(cell)
			or not _passes_strength(cell, 1.0, salt)
		):
			continue
		if (
			operation == OP_ROUGHEN
			and not _is_snapshot_boundary(snapshot, cell)
		):
			continue
		var result := not _snapshot_value(snapshot, cell)
		if operation == OP_SMOOTH:
			var solid_neighbours := 0
			for offset_y in range(-1, 2):
				for offset_x in range(-1, 2):
					if _snapshot_value(
						snapshot,
						cell + Vector2i(offset_x, offset_y)
					):
						solid_neighbours += 1
			result = solid_neighbours > 4
		if _set_target_value(sculpt, cell, result):
			changed += 1
	return changed


func _cell_bounds(cells: Array[Vector2i]) -> Rect2i:
	var minimum := cells[0]
	var maximum := cells[0]
	for cell in cells:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)


func _apply_named_operation(
	sculpt: CutsceneTerrainSculpt,
	center: Vector2,
	operation: StringName
) -> int:
	match operation:
		OP_CARVE:
			return _apply_direct(sculpt, center, false)
		OP_FILL:
			return _apply_direct(sculpt, center, true)
		OP_SMOOTH:
			return _apply_smooth(sculpt, center)
		OP_ROUGHEN:
			return _apply_roughen(sculpt, center)
	return 0


func _apply_direct(
	sculpt: CutsceneTerrainSculpt,
	center: Vector2,
	solid: bool
) -> int:
	var changed := 0
	var bounds := _brush_bounds(center, 0)
	for local_y in range(bounds.position.y, bounds.end.y):
		for local_x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(local_x, local_y)
			var weight := _brush_weight(center, cell)
			# Carve and fill are deliberately deterministic. Dicing each cell
			# against the falloff ramp leaves unaffected cells scattered
			# through the soft edge, and on terrain those are not a soft edge
			# at all — they are floating debris the miner lands on, and the
			# room fills with speckle. Strength shrinks the cut instead, and
			# the softness of the drawn rim is the sculpt's edge_smoothing.
			if (
				weight <= 0.0
				or not sculpt.contains_local(cell)
				or weight < 1.0 - clampf(strength, 0.0, 1.0)
			):
				continue
			if _set_target_value(sculpt, cell, solid):
				changed += 1
	return changed


func _apply_smooth(
	sculpt: CutsceneTerrainSculpt,
	center: Vector2
) -> int:
	var changed := 0
	var bounds := _brush_bounds(center, 0)
	var snapshot := _take_snapshot(sculpt, bounds.grow(1))
	for local_y in range(bounds.position.y, bounds.end.y):
		for local_x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(local_x, local_y)
			var weight := _brush_weight(center, cell)
			if (
				weight <= 0.0
				or not sculpt.contains_local(cell)
				or not _passes_strength(cell, weight, _SELECTION_SALT)
			):
				continue
			var current := _snapshot_value(snapshot, cell)
			var solid_neighbours := 0
			for offset_y in range(-1, 2):
				for offset_x in range(-1, 2):
					if _snapshot_value(
						snapshot,
						cell + Vector2i(offset_x, offset_y)
					):
						solid_neighbours += 1
			var result := current
			if solid_neighbours > 4:
				result = true
			elif solid_neighbours < 5:
				result = false
			if _set_target_value(sculpt, cell, result):
				changed += 1
	return changed


func _apply_roughen(
	sculpt: CutsceneTerrainSculpt,
	center: Vector2
) -> int:
	var changed := 0
	var bounds := _brush_bounds(center, 0)
	var snapshot := _take_snapshot(sculpt, bounds.grow(1))
	for local_y in range(bounds.position.y, bounds.end.y):
		for local_x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(local_x, local_y)
			var weight := _brush_weight(center, cell)
			if (
				weight <= 0.0
				or not sculpt.contains_local(cell)
				or not _is_snapshot_boundary(snapshot, cell)
				or not _passes_strength(cell, weight, _ROUGHEN_SALT)
			):
				continue
			if _set_target_value(
				sculpt,
				cell,
				not _snapshot_value(snapshot, cell)
			):
				changed += 1
	return changed


func _take_snapshot(
	sculpt: CutsceneTerrainSculpt,
	area: Rect2i
) -> Dictionary:
	var snapshot: Dictionary = {}
	for local_y in range(area.position.y, area.end.y):
		for local_x in range(area.position.x, area.end.x):
			var cell := Vector2i(local_x, local_y)
			snapshot[cell] = _target_value(sculpt, cell)
	return snapshot


func _is_snapshot_boundary(snapshot: Dictionary, cell: Vector2i) -> bool:
	var current := _snapshot_value(snapshot, cell)
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			if offset_x == 0 and offset_y == 0:
				continue
			if _snapshot_value(
				snapshot,
				cell + Vector2i(offset_x, offset_y)
			) != current:
				return true
	return false


func _snapshot_value(snapshot: Dictionary, cell: Vector2i) -> bool:
	return bool(snapshot.get(cell, true))


func _target_value(sculpt: CutsceneTerrainSculpt, cell: Vector2i) -> bool:
	if target_layer < 0:
		return sculpt.is_solid_local(cell)
	return sculpt.is_layer_solid_local(target_layer, cell)


func _set_target_value(
	sculpt: CutsceneTerrainSculpt,
	cell: Vector2i,
	solid: bool
) -> bool:
	if target_layer >= 0:
		return sculpt.set_layer_solid_local(target_layer, cell, solid)

	var changed := sculpt.set_solid_local(cell, solid)
	if not sculpt.has_layer_masks():
		return changed
	for layer_index in range(sculpt.layer_solid_bits.size()):
		if sculpt.set_layer_solid_local(layer_index, cell, solid):
			changed = true
	return changed


func _passes_strength(cell: Vector2i, weight: float, salt: int) -> bool:
	var probability := clampf(strength, 0.0, 1.0) * weight
	if probability >= 1.0:
		return true
	if probability <= 0.0:
		return false
	return float(_cell_hash(cell, salt)) / 2_147_483_647.0 < probability


func _cell_hash(cell: Vector2i, salt: int) -> int:
	var value := seed_value
	value = _mix_hash(value ^ (cell.x * 0x45D9F3B))
	value = _mix_hash(value ^ (cell.y * 0x119DE1F3))
	return _mix_hash(value ^ salt) & 0x7FFFFFFF


func _mix_hash(value: int) -> int:
	var mixed := value ^ (value >> 16)
	mixed = (mixed * 0x45D9F3B) & 0xFFFFFFFF
	mixed = (mixed ^ (mixed >> 16)) & 0xFFFFFFFF
	return mixed


func _brush_bounds(center: Vector2, margin: int) -> Rect2i:
	var radius := maxf(radius_cells, 0.0)
	var minimum := Vector2i(
		floori(center.x - radius) - margin,
		floori(center.y - radius) - margin
	)
	var maximum := Vector2i(
		ceili(center.x + radius) + margin,
		ceili(center.y + radius) + margin
	)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)


func _brush_weight(center: Vector2, cell: Vector2i) -> float:
	var radius := maxf(radius_cells, 0.0)
	var distance := center.distance_to(Vector2(cell))
	if distance > radius:
		return 0.0
	if radius <= 0.0 or falloff <= 0.0:
		return 1.0
	var clamped_falloff := clampf(falloff, 0.0, 1.0)
	if clamped_falloff <= 0.0:
		return 1.0
	var normalized_distance := distance / radius
	var full_weight_radius := 1.0 - clamped_falloff
	if normalized_distance <= full_weight_radius:
		return 1.0
	return 1.0 - smoothstep(
		full_weight_radius,
		1.0,
		normalized_distance
	)
