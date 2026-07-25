@tool
class_name CutsceneTerrainSculpt
extends Resource

## How it works:
## - Stores one authored room as a grid of terrain cells anchored to an
##   encounter, where a set bit is solid rock and a clear bit is open air.
## - The grid is placed by anchor_offset_cells relative to that encounter's
##   anchor cell: the chamber's center column and its solid floor row.
## - solid_bits is the single logical truth used for collision and landing.
##   layer_solid_bits optionally lets each stratum's visible rock differ from
##   it, which is what makes strata read as receding rock rather than one
##   silhouette stamped four times.
## - It owns no terrain code. Take the resource away and the encounter falls
##   back to the procedural chamber exactly as before.
## The invariant is that solid_bits is the only thing collision ever reads;
## a per-stratum mask can change what a room looks like but never where the
## miner can stand.
## @tool because the sculpt editor calls these methods from editor context,
## where a non-tool resource loads as a placeholder and throws on every call.

## Rooms smaller than this cannot hold a cast; larger than this and one
## authored room would cover more rows than the chamber it replaces.
const MINIMUM_GRID_SIZE := Vector2i(8, 8)
const MAXIMUM_GRID_SIZE := Vector2i(512, 512)

@export var enabled: bool = true:
	set(value):
		enabled = value
		emit_changed()

## Grid footprint in terrain cells. Resizing preserves overlapping content so
## growing a room to reach further left does not discard what is already cut.
@export var grid_size: Vector2i = Vector2i(140, 120):
	set(value):
		var clamped := value.clamp(MINIMUM_GRID_SIZE, MAXIMUM_GRID_SIZE)
		if clamped == grid_size:
			return
		# The old shape has to be taken before the new size is stored, and the
		# store has to happen here rather than in a helper: assigning the
		# property from another function re-enters this setter and recurses.
		var previous_size := grid_size
		var previous_bits := solid_bits.duplicate()
		var previous_layers: Array[PackedByteArray] = []
		for layer_bits in layer_solid_bits:
			previous_layers.append(layer_bits.duplicate())
		grid_size = clamped
		_adopt_resized_bits(previous_size, previous_bits, previous_layers)

## Rows at and below the encounter floor that stay solid whatever is painted
## over them. The miner reaches a cutscene by falling through the ceiling, so
## the floor he lands on is not decoration — carving it away drops him past the
## stage the cast is standing on. Three rows survive a brush that overshoots.
## Set it to zero only for a room deliberately authored with no floor.
@export_range(0, 16, 1) var protected_floor_rows: int = 3:
	set(value):
		protected_floor_rows = clampi(value, 0, 16)
		emit_changed()

## How much the drawn rock rounds off the cell grid it is authored on. Zero
## draws hard cell edges, which is what makes a roughened wall read as jagged
## rock; one interpolates every rim, which is what makes a smoothed wall read
## as a worn chamber. This changes the picture only — collision always uses
## whole cells.
## Defaults to full smoothing. The mask is written at four pixels per cell, so
## interpolating the rim puts the visible edge on the true sub-cell contour;
## blending back toward the raw cells only drags that contour onto the grid and
## the wall reads as stair-steps. Jaggedness should come from the roughen
## brush, which moves actual cells, not from refusing to interpolate.
@export_range(0.0, 1.0, 0.05) var edge_smoothing: float = 1.0:
	set(value):
		edge_smoothing = clampf(value, 0.0, 1.0)
		emit_changed()

## Top-left of the grid relative to the encounter anchor cell, which is the
## chamber's center column on its solid floor row. The default reaches 110
## rows above the floor and keeps 10 rows below it so the floor itself can be
## shaped.
@export var anchor_offset_cells: Vector2i = Vector2i(-70, -110):
	set(value):
		anchor_offset_cells = value
		emit_changed()

## One bit per cell, row-major, set means solid. Hidden from the Inspector
## because a room is authored with the brush, not by typing bytes.
@export_storage var solid_bits: PackedByteArray = PackedByteArray()
## Optional per-stratum visible rock, same layout as solid_bits. An empty
## array means every stratum follows the logical mask.
@export_storage var layer_solid_bits: Array[PackedByteArray] = []

# A brush stroke touches thousands of cells. Emitting `changed` per cell would
# rebuild the previewed terrain thousands of times inside one drag, so edits
# are batched between begin_edit() and end_edit().
var _edit_depth: int = 0
var _changed_while_editing: bool = false


func _init() -> void:
	_ensure_logical_capacity()


## Opens a batched edit. Nested calls are counted, so a brush that calls a
## helper which also batches still emits exactly one change.
func begin_edit() -> void:
	_edit_depth += 1


## Closes a batched edit and notifies listeners once if anything moved.
func end_edit() -> void:
	_edit_depth = maxi(_edit_depth - 1, 0)
	if _edit_depth > 0 or not _changed_while_editing:
		return
	_changed_while_editing = false
	emit_changed()


## Returns whether a grid coordinate is inside this room's footprint.
func contains_local(local_cell: Vector2i) -> bool:
	return (
		local_cell.x >= 0
		and local_cell.y >= 0
		and local_cell.x < grid_size.x
		and local_cell.y < grid_size.y
	)


## Returns whether a cell is solid rock. Cells outside the grid are solid,
## because the world beyond an authored room is ordinary untouched terrain.
func is_solid_local(local_cell: Vector2i) -> bool:
	if not contains_local(local_cell):
		return true
	if is_protected_floor_row(local_cell.y):
		return true
	return _read_bit(solid_bits, _bit_index(local_cell))


## Returns the grid row holding the encounter's own floor. The anchor sits on
## that row, so the offset that places the grid also locates it.
func get_floor_local_row() -> int:
	return -anchor_offset_cells.y


## Reports whether a grid row is part of the guarded landing floor.
func is_protected_floor_row(local_row: int) -> bool:
	if protected_floor_rows <= 0:
		return false
	var floor_local_row := get_floor_local_row()
	return (
		local_row >= floor_local_row
		and local_row < floor_local_row + protected_floor_rows
	)


## Returns, for each column the run's snaking path can arrive down, the grid
## row the miner would first touch. The editor draws this so a designer sees
## the real landing line rather than guessing where a ledge catches him.
##
## The scan skips the intact rock above the room before looking for ground.
## The miner does not land on the ceiling, he breaks through it: the row that
## matters is the first solid cell *below the first opening*, which is what
## TerrainManager.find_tunnel_surface_cell finds once he is falling.
##
## One entry per column from the leftmost reachable column rightward. -1 means
## that column has no opening to fall into at all.
func get_landing_local_rows(half_span_cells: int) -> PackedInt32Array:
	var landing_rows := PackedInt32Array()
	var floor_local_row := get_floor_local_row()
	if floor_local_row < 0 or floor_local_row >= grid_size.y:
		return landing_rows
	var center_local_x := -anchor_offset_cells.x
	var first_local_x := maxi(center_local_x - half_span_cells, 0)
	var last_local_x := mini(center_local_x + half_span_cells, grid_size.x - 1)
	for local_x in range(first_local_x, last_local_x + 1):
		var landing_row := -1
		var has_reached_opening := false
		for local_y in range(0, grid_size.y):
			if not is_solid_local(Vector2i(local_x, local_y)):
				has_reached_opening = true
				continue
			if has_reached_opening:
				landing_row = local_y
				break
		landing_rows.append(landing_row)
	return landing_rows


## Returns the leftmost grid column that get_landing_local_rows reports on, so
## a caller can turn an index in that array back into a column.
func get_landing_first_local_x(half_span_cells: int) -> int:
	return maxi(-anchor_offset_cells.x - half_span_cells, 0)


## Sets one logical cell and reports whether it actually changed, so a brush
## can skip work and undo records stay minimal.
func set_solid_local(local_cell: Vector2i, solid: bool) -> bool:
	if not contains_local(local_cell):
		return false
	_ensure_logical_capacity()
	if not _write_bit(solid_bits, _bit_index(local_cell), solid):
		return false
	_mark_changed()
	return true


## Returns what one stratum draws at a cell. Without per-stratum masks every
## stratum draws the logical mask, which is the shape collision agrees with.
func is_layer_solid_local(layer_index: int, local_cell: Vector2i) -> bool:
	if (
		layer_index < 0
		or layer_index >= layer_solid_bits.size()
		or not contains_local(local_cell)
	):
		return is_solid_local(local_cell)
	var layer_bits := layer_solid_bits[layer_index]
	if layer_bits.size() < _required_byte_count():
		return is_solid_local(local_cell)
	# The guarded floor is drawn as well as walked on. Letting a stratum paint
	# it away would leave the miner standing on rock nobody can see.
	if is_protected_floor_row(local_cell.y):
		return true
	return _read_bit(layer_bits, _bit_index(local_cell))


## Sets one stratum's visible rock without touching collision.
func set_layer_solid_local(
	layer_index: int,
	local_cell: Vector2i,
	solid: bool
) -> bool:
	if layer_index < 0 or not contains_local(local_cell):
		return false
	ensure_layer_masks(layer_index + 1)
	var layer_bits := layer_solid_bits[layer_index]
	if not _write_bit(layer_bits, _bit_index(local_cell), solid):
		return false
	layer_solid_bits[layer_index] = layer_bits
	_mark_changed()
	return true


## Reports whether any stratum draws something other than the logical mask.
func has_layer_masks() -> bool:
	return not layer_solid_bits.is_empty()


## Grows the per-stratum masks to a stratum count, seeding new ones from the
## logical mask so enabling per-layer editing never changes the look first.
func ensure_layer_masks(layer_count: int) -> void:
	if layer_count <= layer_solid_bits.size():
		for layer_index in range(layer_solid_bits.size()):
			if layer_solid_bits[layer_index].size() < _required_byte_count():
				layer_solid_bits[layer_index] = solid_bits.duplicate()
		return
	_ensure_logical_capacity()
	while layer_solid_bits.size() < layer_count:
		layer_solid_bits.append(solid_bits.duplicate())
	_mark_changed()


## Drops every per-stratum mask so all strata follow collision again.
func clear_layer_masks() -> void:
	if layer_solid_bits.is_empty():
		return
	layer_solid_bits.clear()
	_mark_changed()


## Fills the whole room solid or open, including any per-stratum masks.
func fill_all(solid: bool) -> void:
	_ensure_logical_capacity()
	var fill_byte := 0xFF if solid else 0x00
	solid_bits.fill(fill_byte)
	_clear_trailing_bits(solid_bits)
	for layer_index in range(layer_solid_bits.size()):
		var layer_bits := layer_solid_bits[layer_index]
		layer_bits.resize(_required_byte_count())
		layer_bits.fill(fill_byte)
		_clear_trailing_bits(layer_bits)
		layer_solid_bits[layer_index] = layer_bits
	_mark_changed()


## Counts open cells, so a test can tell a carved room from an untouched one
## without reading bytes.
func get_open_cell_count() -> int:
	_ensure_logical_capacity()
	var open_count := 0
	for local_y in range(grid_size.y):
		for local_x in range(grid_size.x):
			if not _read_bit(
				solid_bits,
				local_y * grid_size.x + local_x
			):
				open_count += 1
	return open_count


## Converts a world terrain cell into this room's grid coordinate.
func world_to_local(world_cell: Vector2i, anchor_cell: Vector2i) -> Vector2i:
	return world_cell - anchor_cell - anchor_offset_cells


## Converts a grid coordinate back into a world terrain cell.
func local_to_world(local_cell: Vector2i, anchor_cell: Vector2i) -> Vector2i:
	return local_cell + anchor_cell + anchor_offset_cells


## Returns the world cell rectangle this room covers, so callers can reject a
## row cheaply before converting every cell in it.
func get_world_rect(anchor_cell: Vector2i) -> Rect2i:
	return Rect2i(anchor_cell + anchor_offset_cells, grid_size)


## Returns the one actionable reason this room cannot be used, or an empty
## string.
func get_sculpt_error() -> String:
	if grid_size.x < MINIMUM_GRID_SIZE.x or grid_size.y < MINIMUM_GRID_SIZE.y:
		return "Cutscene sculpt grid is smaller than the minimum room size."
	if solid_bits.size() < _required_byte_count():
		return "Cutscene sculpt data does not cover its grid."
	var floor_local_row := get_floor_local_row()
	if floor_local_row < 0 or floor_local_row >= grid_size.y:
		return (
			"Cutscene sculpt grid does not contain its encounter floor row; "
			+ "the miner would fall past the room he is meant to land in."
		)
	return ""


## Copies another room's shape into this one without changing identity, used
## by the editor's undo so a restored stroke keeps the same resource.
func copy_shape_from(other: CutsceneTerrainSculpt) -> void:
	if other == null:
		return
	grid_size = other.grid_size
	anchor_offset_cells = other.anchor_offset_cells
	solid_bits = other.solid_bits.duplicate()
	layer_solid_bits = []
	for layer_bits in other.layer_solid_bits:
		layer_solid_bits.append(layer_bits.duplicate())
	_mark_changed()


func _bit_index(local_cell: Vector2i) -> int:
	return local_cell.y * grid_size.x + local_cell.x


func _required_byte_count() -> int:
	return ceili(float(grid_size.x * grid_size.y) / 8.0)


func _ensure_logical_capacity() -> void:
	var required := _required_byte_count()
	if solid_bits.size() >= required:
		return
	var previous_size := solid_bits.size()
	solid_bits.resize(required)
	# New rooms start as untouched rock so the first brush stroke is a cut,
	# which is how a designer expects to open a room out of solid ground.
	for byte_index in range(previous_size, required):
		solid_bits[byte_index] = 0xFF
	_clear_trailing_bits(solid_bits)


func _read_bit(bits: PackedByteArray, bit_index: int) -> bool:
	var byte_offset := bit_index >> 3
	if byte_offset < 0 or byte_offset >= bits.size():
		return true
	return bits[byte_offset] & (1 << (bit_index & 7)) != 0


## Writes one bit and reports whether the stored value actually moved.
func _write_bit(
	bits: PackedByteArray,
	bit_index: int,
	value: bool
) -> bool:
	var byte_offset := bit_index >> 3
	if byte_offset < 0 or byte_offset >= bits.size():
		return false
	var bit_mask := 1 << (bit_index & 7)
	var was_set := bits[byte_offset] & bit_mask != 0
	if was_set == value:
		return false
	if value:
		bits[byte_offset] = bits[byte_offset] | bit_mask
	else:
		bits[byte_offset] = bits[byte_offset] & ~bit_mask
	return true


## Keeps the unused bits of the final byte clear. Without this, a grid whose
## cell count is not a multiple of eight would report phantom solid cells past
## its own last row when counted or copied.
func _clear_trailing_bits(bits: PackedByteArray) -> void:
	var cell_count := grid_size.x * grid_size.y
	var used_bits := cell_count & 7
	if used_bits == 0 or bits.is_empty():
		return
	var last_byte := bits.size() - 1
	bits[last_byte] = bits[last_byte] & ((1 << used_bits) - 1)


## Rebuilds the bit storage for an already-stored new grid size, keeping every
## cell both grids share so widening a room does not erase what is carved.
## This must never assign grid_size; its setter owns that.
func _adopt_resized_bits(
	previous_size: Vector2i,
	previous_bits: PackedByteArray,
	previous_layers: Array[PackedByteArray]
) -> void:
	var new_size := grid_size
	solid_bits = PackedByteArray()
	_ensure_logical_capacity()
	layer_solid_bits = []
	for _layer_index in range(previous_layers.size()):
		layer_solid_bits.append(solid_bits.duplicate())

	var shared_width := mini(previous_size.x, new_size.x)
	var shared_height := mini(previous_size.y, new_size.y)
	for local_y in range(shared_height):
		for local_x in range(shared_width):
			var source_index := local_y * previous_size.x + local_x
			var target_index := local_y * new_size.x + local_x
			_write_bit(
				solid_bits,
				target_index,
				_read_bit(previous_bits, source_index)
			)
			for layer_index in range(previous_layers.size()):
				var layer_bits := layer_solid_bits[layer_index]
				_write_bit(
					layer_bits,
					target_index,
					_read_bit(previous_layers[layer_index], source_index)
				)
				layer_solid_bits[layer_index] = layer_bits
	_clear_trailing_bits(solid_bits)
	for layer_index in range(layer_solid_bits.size()):
		var layer_bits := layer_solid_bits[layer_index]
		_clear_trailing_bits(layer_bits)
		layer_solid_bits[layer_index] = layer_bits
	_mark_changed()


func _mark_changed() -> void:
	if _edit_depth > 0:
		_changed_while_editing = true
		return
	emit_changed()
