class_name DigNumberPresenter
extends CanvasLayer

## Creates floating depth numbers at successful hammer impacts.

const PRESENTER_GROUP: StringName = &"dig_number_presenter"

@export var dig_number_scene: PackedScene

var _random := RandomNumberGenerator.new()


## Seeds launch direction and distance variation for this run.
func _ready() -> void:
	_random.randomize()


## Shows the gameplay depth gained by the current impact.
func show_dig_number_at_impact(
	impact_screen_position: Vector2,
	depth_gained: int,
	combo: int,
	combo_strength: float
) -> void:
	create(
		impact_screen_position,
		depth_gained,
		combo,
		combo_strength,
		get_tree()
	)


## Creates a number in the active presentation layer for this scene tree.
static func create(
	impact_screen_position: Vector2,
	depth_gained: int,
	combo: int,
	combo_strength: float,
	scene_tree: SceneTree
) -> DigNumber:
	if scene_tree == null:
		push_error("A SceneTree is required to create a dig number.")
		return null
	var presenter := scene_tree.get_first_node_in_group(
		PRESENTER_GROUP
	) as DigNumberPresenter
	if presenter == null:
		push_error("The SceneTree has no active DigNumberPresenter.")
		return null
	return presenter._spawn_dig_number(
		impact_screen_position,
		depth_gained,
		combo,
		combo_strength
	)


## Instantiates one number with this layer's scene and random launch.
func _spawn_dig_number(
	impact_screen_position: Vector2,
	depth_gained: int,
	combo: int,
	combo_strength: float
) -> DigNumber:
	if depth_gained <= 0 or dig_number_scene == null:
		return null
	var dig_number := dig_number_scene.instantiate() as DigNumber
	if dig_number == null:
		push_error("The configured dig number scene is not a DigNumber.")
		return null
	add_child(dig_number)
	var horizontal_direction := (
		-1.0
		if _random.randi_range(0, 1) == 0
		else 1.0
	)
	dig_number.present(
		impact_screen_position,
		depth_gained,
		combo,
		combo_strength,
		horizontal_direction,
		_random.randf_range(0.8, 1.2)
	)
	return dig_number
