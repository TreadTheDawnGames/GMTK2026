class_name MiningBrushDefinition
extends Resource

## Stores editable shapes for terrain previews and future mining behaviors.

enum Shape {
	LEGACY_TUNNEL,
	CIRCLE,
	ELLIPSE,
	CAPSULE,
}

@export var shape: Shape = Shape.LEGACY_TUNNEL
@export_range(1, 64, 1) var radius_x_cells: int = 6
@export_range(1, 64, 1) var radius_y_cells: int = 5
@export_range(0.0, 1.0, 0.05) var edge_roughness: float = 0.15
@export_range(0, 8, 1) var combo_radius_step: int = 1


## Returns cells for previewing a future circular, ellipse, or capsule hit.
func get_stamp_cells(
	center: Vector2i,
	combo: int
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var combo_steps := maxi(combo - 1, 0) * combo_radius_step
	var radius_x := maxi(radius_x_cells + combo_steps, 1)
	var radius_y := maxi(radius_y_cells + combo_steps, 1)
	for offset_y in range(-radius_y, radius_y + 1):
		for offset_x in range(-radius_x, radius_x + 1):
			if _contains_offset(
				Vector2i(offset_x, offset_y),
				radius_x,
				radius_y
			):
				cells.append(center + Vector2i(offset_x, offset_y))
	return cells


## Returns whether one local cell belongs to the selected brush shape.
func _contains_offset(
	offset: Vector2i,
	radius_x: int,
	radius_y: int
) -> bool:
	var normalized_distance_squared: float
	match shape:
		Shape.CIRCLE:
			var radius := mini(radius_x, radius_y)
			normalized_distance_squared = (
				float(offset.length_squared())
				/ float(radius * radius)
			)
		Shape.CAPSULE:
			var cap_radius := mini(radius_x, radius_y)
			var segment_half_height := maxi(radius_y - cap_radius, 0)
			var nearest_y := clampi(
				offset.y,
				-segment_half_height,
				segment_half_height
			)
			normalized_distance_squared = float(Vector2i(
				offset.x,
				offset.y - nearest_y
			).length_squared()) / float(cap_radius * cap_radius)
		_:
			var normalized_x := float(offset.x) / float(radius_x)
			var normalized_y := float(offset.y) / float(radius_y)
			normalized_distance_squared = (
				normalized_x * normalized_x
				+ normalized_y * normalized_y
			)
	var cell_hash := offset.x * 73_856_093 ^ offset.y * 19_349_663
	var edge_noise := (
		float(posmod(cell_hash, 2_001)) / 1_000.0 - 1.0
	)
	var roughened_radius := 1.0 + edge_noise * edge_roughness * 0.2
	return normalized_distance_squared <= roughened_radius * roughened_radius
