class_name TerrainArtPreview
extends Node2D

## Exercises terrain artwork and masks without starting a gameplay run.

@export_category("References")
@export var terrain_manager: TerrainManager
@export var combo_slider: HSlider
@export var brush_selector: OptionButton
@export var view_selector: OptionButton
@export var status_label: Label

var _preview_brush: MiningBrushDefinition
var _preview_mining_y: int


## Prepares editable preview controls from the shared mining configuration.
func _ready() -> void:
	_preview_brush = terrain_manager.config.mining_brush.duplicate(true)
	_preview_mining_y = terrain_manager.config.initial_surface_row
	brush_selector.select(_preview_brush.shape)
	view_selector.select(TerrainChunkVisual.ViewMode.FINAL)
	status_label.text = "Inspector: assign TerrainManager > Art Profile Override"


## Applies one legacy tunnel or preview-only brush stamp.
func _on_hit_button_pressed() -> void:
	var combo := roundi(combo_slider.value)
	var result: TerrainManager.DigResult
	var center_x := terrain_manager.config.terrain_width_cells / 2
	if _preview_brush.shape == MiningBrushDefinition.Shape.LEGACY_TUNNEL:
		var combo_steps := maxi(combo - 1, 0)
		result = terrain_manager.dig_tunnel(
			Vector2i(center_x, _preview_mining_y),
			terrain_manager.config.base_mine_depth_cells
				+ terrain_manager.config.combo_mine_depth_cells_per_step
				* combo_steps,
			terrain_manager.config.base_tunnel_half_width_cells
				+ terrain_manager.config.combo_tunnel_half_width_cells_per_step
				* combo_steps
		)
	else:
		var stamp_center := Vector2i(
			center_x,
			_preview_mining_y + _preview_brush.radius_y_cells
		)
		result = terrain_manager.stamp_preview_brush(
			stamp_center,
			_preview_brush,
			combo
		)
	_preview_mining_y = terrain_manager.find_surface_row(
		center_x,
		_preview_mining_y
	)
	terrain_manager.set_view_y(float(_preview_mining_y))
	status_label.text = "Removed %d cells at combo %d" % [
		result.cells_removed,
		combo,
	]


## Restores the authored preview terrain.
func _on_reset_button_pressed() -> void:
	_preview_mining_y = terrain_manager.config.initial_surface_row
	terrain_manager.set_view_y(float(_preview_mining_y))
	terrain_manager.reset_terrain()
	status_label.text = "Terrain reset"


## Selects the shape stamped by the next preview hit.
func _on_brush_selected(index: int) -> void:
	_preview_brush.shape = index as MiningBrushDefinition.Shape


## Selects the final artwork or an individual generated mask.
func _on_view_selected(index: int) -> void:
	terrain_manager.set_debug_view_mode(
		index as TerrainChunkVisual.ViewMode
	)
