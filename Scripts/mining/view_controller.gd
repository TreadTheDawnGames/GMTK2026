class_name ViewController
extends Node

## Smoothly follows the player's depth and updates visible terrain.

signal landing_reached(mining_y: int)

@export var config: MiningConfig
@export var terrain_manager: TerrainManager

var current_view_y: float
var target_view_y: float
var _last_landing_y: int


## Starts the view at the ground surface.
func _ready() -> void:
	current_view_y = float(config.initial_surface_row)
	target_view_y = current_view_y
	_last_landing_y = config.initial_surface_row
	terrain_manager.set_view_y(current_view_y)


## Smoothly follows the player's latest landing row.
func _process(delta: float) -> void:
	var follow_weight := 1.0 - exp(-config.view_follow_speed * delta)
	current_view_y = lerpf(current_view_y, target_view_y, follow_weight)
	var reached_landing := is_equal_approx(current_view_y, target_view_y)
	if reached_landing:
		current_view_y = target_view_y
	terrain_manager.set_view_y(current_view_y)
	var landing_y := roundi(target_view_y)
	if reached_landing and landing_y != _last_landing_y:
		_last_landing_y = landing_y
		landing_reached.emit(landing_y)


## Sets the terrain row the view should follow.
func follow_mining_y(mining_y: int) -> void:
	target_view_y = float(mining_y)
