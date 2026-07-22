@tool
class_name ShipSection
extends Node2D
## Manually placed, grid-snapped ship section with explicit connection points.

signal placement_changed(section: ShipSection)

enum Connection {
	UP = 1,
	RIGHT = 2,
	DOWN = 4,
	LEFT = 8,
}

@export var section_id: StringName
@export_flags("Up", "Right", "Down", "Left") var connections := 0:
	set(value):
		connections = value
		if is_node_ready():
			_update_connection_markers()
@export_range(1, 64, 1) var editor_snap_size := 8
@export var snap_in_editor := true
@export var show_connections_in_game := false

@onready var connection_up: Marker2D = %ConnectionUp
@onready var connection_right: Marker2D = %ConnectionRight
@onready var connection_down: Marker2D = %ConnectionDown
@onready var connection_left: Marker2D = %ConnectionLeft

var _is_applying_snap := false


func _enter_tree() -> void:
	set_notify_transform(true)


func _ready() -> void:
	_update_connection_markers()


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSFORM_CHANGED:
		return
	if Engine.is_editor_hint() and snap_in_editor and not _is_applying_snap:
		var snap_vector := Vector2(editor_snap_size, editor_snap_size)
		var snapped_position := position.snapped(snap_vector)
		if not position.is_equal_approx(snapped_position):
			_is_applying_snap = true
			position = snapped_position
			_is_applying_snap = false
			return
	_refresh_navigation_transform.call_deferred()


func _refresh_navigation_transform() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		var navigation_region := child as NavigationRegion2D
		if navigation_region == null:
			continue
		var navigation_map := NavigationServer2D.region_get_map(navigation_region.get_rid())
		if navigation_map.is_valid():
			NavigationServer2D.map_set_use_async_iterations(navigation_map, false)
		navigation_region.force_update_transform()
		NavigationServer2D.region_set_transform(
			navigation_region.get_rid(),
			navigation_region.global_transform
		)
		if navigation_map.is_valid():
			NavigationServer2D.map_force_update(navigation_map)
	placement_changed.emit(self)


func has_connection(direction: Connection) -> bool:
	return (connections & direction) != 0


func get_connection_point(direction: Connection) -> Marker2D:
	match direction:
		Connection.UP:
			return connection_up
		Connection.RIGHT:
			return connection_right
		Connection.DOWN:
			return connection_down
		Connection.LEFT:
			return connection_left
		_:
			return null


func get_world_connection_position(direction: Connection) -> Vector2:
	var marker := get_connection_point(direction)
	return marker.global_position if marker != null else global_position


func get_visual_bounds() -> Rect2:
	var bounds := Rect2()
	var has_bounds := false
	for child in get_children():
		var artwork := child as Sprite2D
		if artwork == null:
			continue
		var artwork_rect := artwork.get_rect()
		for corner: Vector2 in [
			artwork_rect.position,
			Vector2(artwork_rect.end.x, artwork_rect.position.y),
			artwork_rect.end,
			Vector2(artwork_rect.position.x, artwork_rect.end.y),
		]:
			var point: Vector2 = artwork.transform * corner
			if not has_bounds:
				bounds = Rect2(point, Vector2.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(point)
	return bounds


func can_connect_to(other: ShipSection, direction: Connection) -> bool:
	return other != null and has_connection(direction) and other.has_connection(opposite(direction))


static func opposite(direction: Connection) -> Connection:
	match direction:
		Connection.UP:
			return Connection.DOWN
		Connection.RIGHT:
			return Connection.LEFT
		Connection.DOWN:
			return Connection.UP
		Connection.LEFT:
			return Connection.RIGHT
		_:
			return Connection.UP


func _update_connection_markers() -> void:
	var show_markers := Engine.is_editor_hint() or show_connections_in_game
	connection_up.visible = show_markers and has_connection(Connection.UP)
	connection_right.visible = show_markers and has_connection(Connection.RIGHT)
	connection_down.visible = show_markers and has_connection(Connection.DOWN)
	connection_left.visible = show_markers and has_connection(Connection.LEFT)
