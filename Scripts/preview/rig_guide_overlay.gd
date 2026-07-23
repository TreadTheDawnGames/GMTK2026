class_name RigGuideOverlay
extends Node2D

## Draws preview-only pivot and gameplay-anchor markers.

@export var visual_root: Node2D
@export var body_pivot: Node2D
@export var head_pivot: Node2D
@export var arm_pivot: Node2D
@export var pickaxe_pivot: Node2D
@export var chip_origin: Node2D


## Keeps markers aligned while preview animations move their pivots.
func _process(_delta: float) -> void:
	queue_redraw()


## Draws pivot circles and a distinct fixed mining-origin cross.
func _draw() -> void:
	for pivot in [
		visual_root,
		body_pivot,
		head_pivot,
		arm_pivot,
		pickaxe_pivot,
	]:
		var local_position := to_local(pivot.global_position)
		draw_circle(local_position, 5.0, Color(0.35, 0.85, 1.0, 0.9))
	var chip_position := to_local(chip_origin.global_position)
	draw_line(
		chip_position + Vector2.LEFT * 10.0,
		chip_position + Vector2.RIGHT * 10.0,
		Color(1.0, 0.35, 0.35, 1.0),
		2.0
	)
	draw_line(
		chip_position + Vector2.UP * 10.0,
		chip_position + Vector2.DOWN * 10.0,
		Color(1.0, 0.35, 0.35, 1.0),
		2.0
	)
