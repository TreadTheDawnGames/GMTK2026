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
## The invariant is that every edit is deterministic for its seed and cell, and
## no brush operation writes outside the sculpt grid.

const OP_CARVE: StringName = &"carve"
const OP_FILL: StringName = &"fill"
const OP_SMOOTH: StringName = &"smooth"
const OP_ROUGHEN: StringName = &"roughen"

const _SELECTION_SALT: int = 17
const _ROUGHEN_SALT: int = 43

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
