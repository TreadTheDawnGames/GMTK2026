class_name DigNumberPresenter
extends CanvasLayer

## How it works:
## - Each successful impact may create one short-lived DigNumber child.
## - Native and web builds use separate active-label budgets.
## - At capacity, the oldest label is retired before a new one is added.
## The invariant is that _active_numbers never exceeds the platform budget.

const PRESENTER_GROUP: StringName = &"dig_number_presenter"

@export_category("Content")
@export var dig_number_scene: PackedScene
@export var timing_window: TimingWindowTask
## Includes the timing bar texture that expands above its Control rectangle.
@export_range(0.0, 160.0, 1.0) var timing_bar_visual_overhang_px: float = 80.0

@export_category("Performance")
## RichText effects and tweens make each active label relatively expensive.
@export_range(1, 32, 1) var maximum_active_numbers: int = 8
## Keeps animated RichText work within the itch.io web-export budget.
@export_range(1, 16, 1) var web_maximum_active_numbers: int = 4

var _random := RandomNumberGenerator.new()
# Oldest-first references are pruned or retired on every spawn. This array's
# growth is strictly bounded by the active platform cap above.
var _active_numbers: Array[DigNumber] = []


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

	# Remove labels that completed between impacts without introducing a
	# signal connection for this presenter-owned, bounded child collection.
	for number_index in range(_active_numbers.size() - 1, -1, -1):
		var active_number := _active_numbers[number_index]
		if (
			not is_instance_valid(active_number)
			or active_number.is_queued_for_deletion()
		):
			_active_numbers.remove_at(number_index)

	var active_budget := maximum_active_numbers
	if OS.has_feature("web"):
		active_budget = mini(
			active_budget,
			web_maximum_active_numbers
		)
	active_budget = maxi(active_budget, 1)
	while _active_numbers.size() >= active_budget:
		var oldest_number: DigNumber = _active_numbers.pop_front()
		if is_instance_valid(oldest_number):
			oldest_number.queue_free()

	var dig_number := dig_number_scene.instantiate() as DigNumber
	if dig_number == null:
		push_error("The configured dig number scene is not a DigNumber.")
		return null
	add_child(dig_number)
	_active_numbers.append(dig_number)
	var horizontal_direction := (
		-1.0
		if impact_screen_position.x
			>= get_viewport().get_visible_rect().size.x * 0.5
		else 1.0
	)
	var bottom_screen_limit_y := (
		get_viewport().get_visible_rect().end.y
	)
	if (
		timing_window != null
		and timing_window.visible
		and timing_window.mining_window != null
	):
		bottom_screen_limit_y = (
			timing_window.mining_window.get_global_rect().position.y
			- timing_bar_visual_overhang_px
		)
	dig_number.present(
		impact_screen_position,
		depth_gained,
		combo,
		combo_strength,
		horizontal_direction,
		_random.randf_range(0.8, 1.2),
		bottom_screen_limit_y
	)
	return dig_number
