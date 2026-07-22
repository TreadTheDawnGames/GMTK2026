@tool
class_name CrewMember
extends CharacterBody2D
## Selectable crew pawn that follows the ship's authored navigation map.

signal selection_changed(crew_member: CrewMember, selected: bool)
signal move_order_received(crew_member: CrewMember, destination: Vector2)

@export var display_name := "Crew Member"
@export var crew_texture: Texture2D:
	set(value):
		crew_texture = value
		if is_node_ready():
			crew_sprite.texture = crew_texture
@export_range(10.0, 300.0, 1.0) var move_speed := 72.0
@export_range(4.0, 40.0, 1.0) var selection_radius := 16.0

@onready var crew_sprite: Sprite2D = %CrewSprite
@onready var selection_indicator: Line2D = %SelectionIndicator
@onready var navigation_agent: NavigationAgent2D = %NavigationAgent2D

var is_selected := false


func _ready() -> void:
	crew_sprite.texture = crew_texture
	selection_indicator.visible = is_selected


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if navigation_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		return
	var next_position := navigation_agent.get_next_path_position()
	velocity = global_position.direction_to(next_position) * move_speed
	if not is_zero_approx(velocity.x):
		crew_sprite.flip_h = velocity.x < 0.0
	move_and_slide()


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	selection_indicator.visible = is_selected
	selection_changed.emit(self, is_selected)


func move_to(world_destination: Vector2) -> void:
	# Orders may land on transparent pixels or outside a section. Projecting the
	# click onto the shared map keeps the agent's target reachable.
	var navigation_map := get_world_2d().navigation_map
	var reachable_destination := NavigationServer2D.map_get_closest_point(
		navigation_map,
		world_destination
	)
	navigation_agent.target_position = reachable_destination
	move_order_received.emit(self, reachable_destination)


func is_world_point_selectable(world_point: Vector2) -> bool:
	return global_position.distance_squared_to(world_point) <= selection_radius * selection_radius
