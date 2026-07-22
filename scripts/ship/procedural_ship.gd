class_name ProceduralShip
extends Node2D
## Generates connected rooms and corridors on a navigation-enabled TileMapLayer.

signal generated(generation_seed: int, walkable_cell_count: int)
signal navigation_ready(generation_seed: int)

const TILE_SOURCE_ID := 0
const TILE_HORIZONTAL := Vector2i(0, 0)
const TILE_VERTICAL := Vector2i(1, 0)
const TILE_T_UP_LEFT_RIGHT := Vector2i(2, 0)
const TILE_T_DOWN_LEFT_RIGHT := Vector2i(3, 0)
const TILE_T_UP_DOWN_LEFT := Vector2i(4, 0)
const TILE_T_UP_DOWN_RIGHT := Vector2i(5, 0)
const TILE_CORNER_UP_LEFT := Vector2i(6, 0)
const TILE_CORNER_UP_RIGHT := Vector2i(7, 0)
const TILE_CORNER_DOWN_LEFT := Vector2i(8, 0)
const TILE_CORNER_DOWN_RIGHT := Vector2i(9, 0)
const TILE_OPEN_FLOOR := Vector2i(10, 0)
const TILE_CROSS := Vector2i(11, 0)
const TILE_END_UP := Vector2i(12, 0)
const TILE_END_RIGHT := Vector2i(13, 0)
const TILE_END_DOWN := Vector2i(14, 0)
const TILE_END_LEFT := Vector2i(15, 0)

const DIRECTION_UP := 1
const DIRECTION_RIGHT := 2
const DIRECTION_DOWN := 4
const DIRECTION_LEFT := 8
const CARDINAL_DIRECTIONS := {
	DIRECTION_UP: Vector2i.UP,
	DIRECTION_RIGHT: Vector2i.RIGHT,
	DIRECTION_DOWN: Vector2i.DOWN,
	DIRECTION_LEFT: Vector2i.LEFT,
}
const CONNECTION_TILES := {
	DIRECTION_UP: TILE_END_UP,
	DIRECTION_RIGHT: TILE_END_RIGHT,
	DIRECTION_DOWN: TILE_END_DOWN,
	DIRECTION_LEFT: TILE_END_LEFT,
	DIRECTION_UP | DIRECTION_DOWN: TILE_VERTICAL,
	DIRECTION_LEFT | DIRECTION_RIGHT: TILE_HORIZONTAL,
	DIRECTION_UP | DIRECTION_LEFT: TILE_CORNER_UP_LEFT,
	DIRECTION_UP | DIRECTION_RIGHT: TILE_CORNER_UP_RIGHT,
	DIRECTION_DOWN | DIRECTION_LEFT: TILE_CORNER_DOWN_LEFT,
	DIRECTION_DOWN | DIRECTION_RIGHT: TILE_CORNER_DOWN_RIGHT,
	DIRECTION_UP | DIRECTION_LEFT | DIRECTION_RIGHT: TILE_T_UP_LEFT_RIGHT,
	DIRECTION_DOWN | DIRECTION_LEFT | DIRECTION_RIGHT: TILE_T_DOWN_LEFT_RIGHT,
	DIRECTION_UP | DIRECTION_DOWN | DIRECTION_LEFT: TILE_T_UP_DOWN_LEFT,
	DIRECTION_UP | DIRECTION_DOWN | DIRECTION_RIGHT: TILE_T_UP_DOWN_RIGHT,
	DIRECTION_UP | DIRECTION_RIGHT | DIRECTION_DOWN | DIRECTION_LEFT: TILE_CROSS,
}

@export_category("Ship Bounds")
@export_range(12, 80, 1) var map_width := 35
@export_range(10, 50, 1) var map_height := 19

@export_category("Rooms")
@export_range(2, 24, 1) var target_room_count := 9
@export var minimum_room_size := Vector2i(3, 3)
@export var maximum_room_size := Vector2i(7, 6)
@export_range(0, 4, 1) var room_spacing := 1
@export_range(0.0, 1.0, 0.05) var extra_connection_chance := 0.25

@export_category("Generation")
@export var generation_seed := 2026
@export var randomize_seed_on_ready := false
@export var generate_on_ready := true

@onready var floor_layer: TileMapLayer = %FloorLayer

var _random := RandomNumberGenerator.new()
var _rooms: Array[Rect2i] = []
var _walkable_cells := {}
var _room_cells := {}
var _active_seed := 0
var _generation_revision := 0


func _ready() -> void:
	if generate_on_ready:
		generate_ship()


func generate_ship() -> void:
	_generation_revision += 1
	_active_seed = _resolve_seed()
	_random.seed = _active_seed
	_rooms.clear()
	_walkable_cells.clear()
	_room_cells.clear()
	floor_layer.clear()

	_place_rooms()
	_connect_rooms()
	_render_floor()
	floor_layer.update_internals()
	generated.emit(_active_seed, _walkable_cells.size())
	_publish_navigation_when_ready(_generation_revision)


func regenerate_with_random_seed() -> void:
	generation_seed = int(Time.get_ticks_usec() & 0x7fffffff)
	randomize_seed_on_ready = false
	generate_ship()


func get_active_seed() -> int:
	return _active_seed


func get_rooms() -> Array[Rect2i]:
	return _rooms.duplicate()


func get_walkable_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _walkable_cells:
		cells.append(cell)
	return cells


func is_cell_walkable(cell: Vector2i) -> bool:
	return _walkable_cells.has(cell)


func is_world_position_walkable(world_position: Vector2) -> bool:
	return is_cell_walkable(floor_layer.local_to_map(floor_layer.to_local(world_position)))


func get_world_position_for_cell(cell: Vector2i) -> Vector2:
	return floor_layer.to_global(floor_layer.map_to_local(cell))


func get_random_walkable_world_position() -> Vector2:
	var cells := get_walkable_cells()
	if cells.is_empty():
		return global_position
	return get_world_position_for_cell(cells[_random.randi_range(0, cells.size() - 1)])


func _resolve_seed() -> int:
	if randomize_seed_on_ready or generation_seed == 0:
		return int(Time.get_ticks_usec() & 0x7fffffff)
	return generation_seed


func _publish_navigation_when_ready(revision: int) -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	if revision != _generation_revision:
		return
	NavigationServer2D.map_force_update(get_world_2d().navigation_map)
	navigation_ready.emit(_active_seed)


func _place_rooms() -> void:
	var safe_minimum := Vector2i(
		clampi(minimum_room_size.x, 2, map_width - 2),
		clampi(minimum_room_size.y, 2, map_height - 2)
	)
	var safe_maximum := Vector2i(
		clampi(maximum_room_size.x, safe_minimum.x, map_width - 2),
		clampi(maximum_room_size.y, safe_minimum.y, map_height - 2)
	)
	var attempts_remaining := target_room_count * 12

	while _rooms.size() < target_room_count and attempts_remaining > 0:
		attempts_remaining -= 1
		var room_size := Vector2i(
			_random.randi_range(safe_minimum.x, safe_maximum.x),
			_random.randi_range(safe_minimum.y, safe_maximum.y)
		)
		var room := Rect2i(
			Vector2i(
				_random.randi_range(1, map_width - room_size.x - 1),
				_random.randi_range(1, map_height - room_size.y - 1)
			),
			room_size
		)
		if _room_overlaps_existing(room):
			continue
		_rooms.append(room)
		_carve_room(room)

	if _rooms.is_empty():
		var fallback_size := safe_minimum
		var fallback_position := Vector2i(
			(map_width - fallback_size.x) / 2,
			(map_height - fallback_size.y) / 2
		)
		var fallback_room := Rect2i(fallback_position, fallback_size)
		_rooms.append(fallback_room)
		_carve_room(fallback_room)


func _room_overlaps_existing(candidate: Rect2i) -> bool:
	var padded_candidate := candidate.grow(room_spacing)
	for room: Rect2i in _rooms:
		if padded_candidate.intersects(room):
			return true
	return false


func _carve_room(room: Rect2i) -> void:
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			var cell := Vector2i(x, y)
			_walkable_cells[cell] = true
			_room_cells[cell] = true


func _connect_rooms() -> void:
	if _rooms.size() < 2:
		return
	var ordered_rooms := _rooms.duplicate()
	ordered_rooms.sort_custom(
		func(first: Rect2i, second: Rect2i) -> bool:
			return _room_center(first).x < _room_center(second).x
	)

	for index in range(1, ordered_rooms.size()):
		_carve_corridor(
			_room_center(ordered_rooms[index - 1]),
			_room_center(ordered_rooms[index]),
			_random.randf() < 0.5
		)

	for index in range(ordered_rooms.size() - 2):
		if _random.randf() <= extra_connection_chance:
			_carve_corridor(
				_room_center(ordered_rooms[index]),
				_room_center(ordered_rooms[index + 2]),
				_random.randf() < 0.5
			)


func _room_center(room: Rect2i) -> Vector2i:
	return room.position + Vector2i(room.size.x / 2, room.size.y / 2)


func _carve_corridor(start: Vector2i, destination: Vector2i, horizontal_first: bool) -> void:
	var cursor := start
	_walkable_cells[cursor] = true
	if horizontal_first:
		cursor = _carve_axis(cursor, destination, true)
		_carve_axis(cursor, destination, false)
	else:
		cursor = _carve_axis(cursor, destination, false)
		_carve_axis(cursor, destination, true)


func _carve_axis(start: Vector2i, destination: Vector2i, horizontal: bool) -> Vector2i:
	var cursor := start
	var destination_value := destination.x if horizontal else destination.y
	while (cursor.x if horizontal else cursor.y) != destination_value:
		var current_value := cursor.x if horizontal else cursor.y
		var step := 1 if destination_value > current_value else -1
		if horizontal:
			cursor.x += step
		else:
			cursor.y += step
		_walkable_cells[cursor] = true
	return cursor


func _render_floor() -> void:
	for cell: Vector2i in _walkable_cells:
		var atlas_coordinates := TILE_OPEN_FLOOR
		if not _room_cells.has(cell):
			atlas_coordinates = CONNECTION_TILES.get(_connection_mask(cell), TILE_OPEN_FLOOR)
		floor_layer.set_cell(cell, TILE_SOURCE_ID, atlas_coordinates)


func _connection_mask(cell: Vector2i) -> int:
	var mask := 0
	for direction: int in CARDINAL_DIRECTIONS:
		if _walkable_cells.has(cell + CARDINAL_DIRECTIONS[direction]):
			mask |= direction
	return mask
