@tool
class_name CinematicTerrainPreview
extends Node2D

## How it works:
## - Shows, inside the editor, the real terrain a cutscene plays against, by
##   running the production TerrainManager and TerrainLayerRenderer authored as
##   its own children. Nothing here draws terrain; it only decides where the
##   view sits and where the rock is already broken.
## - Each Marker2D under test_impacts_root is dug with a real dig_tunnel call,
##   so a designer breaking rock in the editor breaks actual cells.
## - Dragging a marker rebuilds from intact terrain, so openings never
##   accumulate behind you.
## - It deletes itself the moment the game runs; the mining scene owns the only
##   terrain a player ever sees.
## The invariant is that this adds no terrain artwork of its own — take this
## node away and the cutscene is unchanged.

## Cutscene markers are authored in viewport pixels, the same space the
## renderer converts into. Digs are placed through TerrainManager's own
## conversion so the preview cannot invent a second coordinate system.
@export var terrain_manager: TerrainManager
@export var terrain_renderer: TerrainLayerRenderer
## Marker2D children are dug in child order. Add, move, or delete them freely.
@export var test_impacts_root: Node2D
## Leave this on. It is the guarantee that no second terrain stack reaches a
## player. Only the preview test turns it off, so it can build the shipped
## scene's own terrain outside an editor and assert what a designer will see.
@export var remove_in_running_game: bool = true

@export_category("Framing")
## Rows below the surface this cutscene plays at, so the strata on screen are
## the ones the sequence will really open against.
@export_range(0, 100_000, 10) var preview_depth_rows: int = 400:
	set(value):
		preview_depth_rows = value
		_request_rebuild()
## Combo the test hits resolve at. Above the renderer's threshold this exposes
## the deep backdrop, which is what a breakthrough-qualifying hit does.
@export_range(1, 100, 1) var preview_combo: int = 8:
	set(value):
		preview_combo = value
		_request_rebuild()

# Marker drags arrive as a stream of tiny moves. Coalescing them into one
# rebuild keeps a full chunk restream off every mouse-move frame.
const _REBUILD_DELAY_SECONDS: float = 0.12

var _tracked_impact_positions: PackedVector2Array = PackedVector2Array()
var _rebuild_countdown: float = -1.0


## Builds the preview in the editor and disappears entirely in a running game.
func _ready() -> void:
	if not Engine.is_editor_hint() and remove_in_running_game:
		# A second terrain stack must never reach the player. Freeing beats
		# hiding: it also drops the chunk images this would otherwise retain.
		queue_free()
		return
	set_process(true)
	build_preview.call_deferred()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if _have_test_impacts_moved():
		_request_rebuild()
	if _rebuild_countdown < 0.0:
		return
	_rebuild_countdown -= delta
	if _rebuild_countdown <= 0.0:
		_rebuild_countdown = -1.0
		build_preview()


## Returns the one actionable reason the preview cannot draw, or an empty
## string. Exposed so a test can assert the authored scene is still wired.
func get_preview_error() -> String:
	if not is_instance_valid(terrain_manager):
		return "Terrain preview needs a TerrainManager."
	if not is_instance_valid(terrain_renderer):
		return "Terrain preview needs a TerrainLayerRenderer."
	if terrain_manager.config == null:
		return "Terrain preview needs a mining config on its TerrainManager."
	if terrain_renderer.profile == null:
		return "Terrain preview needs a layer profile on its renderer."
	if not terrain_renderer.preview_in_editor:
		return "Terrain preview requires Preview In Editor on its renderer."
	return ""


## Reports how many strata the preview currently draws, so a test can tell a
## built preview apart from an empty canvas without inspecting node paths.
func get_drawn_layer_count() -> int:
	if not is_instance_valid(terrain_renderer):
		return 0
	for child in terrain_renderer.get_children():
		if child.name.begins_with("LayeredTerrainChunk_"):
			return child.get_child_count()
	return 0


func _request_rebuild() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	_rebuild_countdown = _REBUILD_DELAY_SECONDS


## Restreams intact terrain at the authored depth, then breaks it again at
## every authored marker. Public so a headless test can build the same preview
## the editor builds, without an editor.
func build_preview() -> void:
	if not get_preview_error().is_empty():
		return
	terrain_manager.clear_damage()
	terrain_manager.set_view_position(_get_preview_view_position())
	terrain_renderer.rebuild_all_chunks()
	_apply_test_impacts()


## Places the view at the authored depth, centred the way the run centres it.
func _get_preview_view_position() -> Vector2:
	var config := terrain_manager.config
	return Vector2(
		float(config.terrain_width_cells) * 0.5,
		float(config.initial_surface_row + preview_depth_rows)
	)


## Digs one real tunnel per authored marker through the production terrain
## authority, so what appears is a mined opening rather than a drawn one.
func _apply_test_impacts() -> void:
	_tracked_impact_positions = _get_test_impact_positions()
	if _tracked_impact_positions.is_empty():
		return
	var config := terrain_manager.config
	var cell_size := float(config.terrain_cell_world_size)
	# The renderer picks a hole size from the combo the hit resolved at, and
	# that arrives by signal during play. In the editor there is no controller
	# to send it, so the preview supplies the same value directly.
	terrain_renderer._on_dig_presentation_started(preview_combo)
	for screen_position in _tracked_impact_positions:
		var terrain_position := terrain_manager.screen_to_terrain_position(
			screen_position
		)
		var cell := Vector2i(
			floori(terrain_position.x / cell_size),
			floori(terrain_position.y / cell_size)
		)
		terrain_manager.dig_tunnel(
			cell,
			config.base_mine_depth_rows,
			config.base_tunnel_half_width_cells
		)


func _get_test_impact_positions() -> PackedVector2Array:
	var positions := PackedVector2Array()
	if not is_instance_valid(test_impacts_root):
		return positions
	for child in test_impacts_root.get_children():
		var marker := child as Marker2D
		if marker != null:
			positions.append(marker.global_position)
	return positions


func _have_test_impacts_moved() -> bool:
	return _get_test_impact_positions() != _tracked_impact_positions
