class_name ViewController
extends Node

## Keeps view position separate from the authoritative mining position. The
## continuous follow avoids overlapping per-hit tweens.

@export var config: MiningConfig
@export var terrain_manager: TerrainManager

var current_view_y: float
var target_view_y: float


func _ready() -> void:
	current_view_y = float(config.initial_surface_row)
	target_view_y = current_view_y
	terrain_manager.set_view_y(current_view_y)


func _process(delta: float) -> void:
	var follow_weight := 1.0 - exp(-config.view_follow_speed * delta)
	current_view_y = lerpf(current_view_y, target_view_y, follow_weight)
	if is_equal_approx(current_view_y, target_view_y):
		current_view_y = target_view_y
	terrain_manager.set_view_y(current_view_y)


func follow_mining_y(mining_y: int) -> void:
	target_view_y = float(mining_y)
