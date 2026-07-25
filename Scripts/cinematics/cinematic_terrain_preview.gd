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

@export_category("Encounter")
## The run schedule this stage belongs to. Leave it empty and the preview loads
## the shipped schedule on its own.
##
## It must not be authored as a resource reference in a stage scene. Encounters
## point at their stage scene, so a stage scene pointing back at the schedule is
## a load cycle, and Godot resolves that by dropping the reference and reporting
## the scene as referencing a non-existent resource. Loading it here, at the
## moment the preview is built, breaks the cycle.
@export var encounter_config: DepthEncounterConfig:
	set(value):
		encounter_config = value
		_resolved_encounter_config = value
		_request_rebuild()
## Which encounter in that schedule this stage plays at. Leave it empty for a
## stage that is not tied to one, such as the surface arrival.
@export var encounter_id: StringName:
	set(value):
		encounter_id = value
		_request_rebuild()
## Takes the preview depth from the named encounter, so moving an encounter in
## the schedule cannot leave its stage previewing the wrong strata.
@export var follow_encounter_depth: bool = true:
	set(value):
		follow_encounter_depth = value
		_request_rebuild()

@export_category("Framing")
## Rows below the surface this cutscene plays at, so the strata on screen are
## the ones the sequence will really open against.
@export_range(0, 100_000, 10) var preview_depth_rows: int = 400:
	set(value):
		preview_depth_rows = value
		_request_rebuild()
## Combo the test hits resolve at through the normal four-layer reveal policy.
@export_range(1, 100, 1) var preview_combo: int = 8:
	set(value):
		preview_combo = value
		_request_rebuild()

# Marker drags arrive as a stream of tiny moves. Coalescing them into one
# rebuild keeps a full chunk restream off every mouse-move frame.
const _REBUILD_DELAY_SECONDS: float = 0.12

const DEFAULT_ENCOUNTER_CONFIG_PATH := (
	"res://resources/encounters/depth_encounter_config.tres"
)

var _tracked_impact_positions: PackedVector2Array = PackedVector2Array()
var _rebuild_countdown: float = -1.0
var _resolved_encounter_config: DepthEncounterConfig


## Returns the run schedule this preview draws against, loading the shipped one
## on first use. Only ever called in the editor; a running game frees this node
## in _enter_tree, so the load never happens during play.
func get_encounter_config() -> DepthEncounterConfig:
	if _resolved_encounter_config != null:
		return _resolved_encounter_config
	if encounter_config != null:
		_resolved_encounter_config = encounter_config
		return _resolved_encounter_config
	_resolved_encounter_config = (
		load(DEFAULT_ENCOUNTER_CONFIG_PATH) as DepthEncounterConfig
	)
	return _resolved_encounter_config


## Disappears before a running game can pay for it. This has to happen in
## _enter_tree, not _ready: Godot readies children first, so by the preview's
## own _ready its TerrainManager and TerrainLayerRenderer have already streamed
## a full chunk set the player will never see. Freeing them here is the only
## moment that second terrain stack can be stopped from existing at all.
func _enter_tree() -> void:
	if Engine.is_editor_hint() or not remove_in_running_game:
		return
	for child in get_children():
		remove_child(child)
		child.free()
	queue_free()


## Builds the preview in the editor.
func _ready() -> void:
	if not Engine.is_editor_hint() and remove_in_running_game:
		return
	set_process(true)
	_watch_authored_resources()
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


## Rebuilds whenever the authored look changes, so editing a stratum tint, a
## rock density, or the grass in the Inspector recolours the rock immediately
## instead of after a reload. Resource emits `changed` on every such edit.
func _watch_authored_resources() -> void:
	for resource: Resource in [
		terrain_renderer.profile if is_instance_valid(terrain_renderer) else null,
		terrain_manager.config if is_instance_valid(terrain_manager) else null,
		# The sculpt batches a whole brush stroke into one `changed`, so
		# listening here redraws the room once per stroke rather than per cell.
		get_sculpt(),
	]:
		if resource != null and not resource.changed.is_connected(_request_rebuild):
			resource.changed.connect(_request_rebuild)


## Digs one real hit at a world position and keeps it, so a click in the editor
## viewport leaves an opening that survives the next rebuild. The marker is
## added under test_impacts_root and owned by the edited scene, which is what
## makes the dug state save with the cutscene instead of vanishing on reload.
func dig_at_world_position(world_position: Vector2) -> bool:
	if not get_preview_error().is_empty():
		return false
	if not is_instance_valid(test_impacts_root):
		return false
	var marker := Marker2D.new()
	marker.name = "Impact"
	test_impacts_root.add_child(marker)
	marker.global_position = world_position
	# Without an owner the editor neither shows the marker nor saves it.
	var scene_root := get_tree().edited_scene_root
	marker.owner = scene_root if scene_root != null else owner
	build_preview()
	return true


## Removes the authored impact nearest a world position, so a click can heal
## rock as well as break it. Returns false when nothing is close enough.
func heal_nearest_impact(
	world_position: Vector2,
	radius: float
) -> bool:
	if not is_instance_valid(test_impacts_root):
		return false
	var closest: Marker2D
	var closest_distance := radius
	for child in test_impacts_root.get_children():
		var marker := child as Marker2D
		if marker == null:
			continue
		var distance := marker.global_position.distance_to(world_position)
		if distance <= closest_distance:
			closest_distance = distance
			closest = marker
	if closest == null:
		return false
	test_impacts_root.remove_child(closest)
	closest.queue_free()
	build_preview()
	return true


## Restreams intact terrain at the authored depth, then breaks it again at
## every authored marker. Public so a headless test can build the same preview
## the editor builds, without an editor.
func build_preview() -> void:
	if not get_preview_error().is_empty():
		return
	# The schedule has to be attached before anything streams, or the chunk
	# under the cast is built as unbroken rock and the room appears only after
	# some later edit happens to rebuild it.
	var schedule := get_encounter_config()
	# Borrowed for the rebuild and handed straight back, never left on the node.
	#
	# TerrainManager.encounter_config is an exported property, so a value left
	# sitting on it is written into whatever scene is open the next time it is
	# saved. That made every stage scene reference the schedule, the schedule
	# reference its encounters, and each encounter reference its stage scene -
	# a load cycle that took the whole cutscene set down with it. The preview is
	# editor-only furniture and must leave no trace in the saved scene.
	var borrowed_from := terrain_manager.encounter_config
	if borrowed_from != schedule:
		terrain_manager.encounter_config = schedule
		terrain_manager.invalidate_sculpt_placements()
	_align_to_runtime_stage_anchor()
	_watch_authored_resources()
	terrain_manager.clear_damage()
	terrain_manager.set_view_position(_get_preview_view_position())
	terrain_renderer.rebuild_all_chunks()
	_apply_test_impacts()
	if borrowed_from != schedule:
		terrain_manager.encounter_config = borrowed_from


## Offsets this preview so the stage's origin lands exactly where the running
## game puts the stage, rather than on the mining face.
##
## DepthEncounterController places an encounter's cast and its stage at the
## terrain centre plus encounter_horizontal_offset_cells. The preview used to
## ignore that entirely and align the stage origin to the mining face, so every
## marker, actor and prop a designer placed was that many cells left of where
## it played. Deriving the offset here means the two cannot drift again.
func _align_to_runtime_stage_anchor() -> void:
	var config := terrain_manager.config
	if config == null:
		return
	var offset_cells := 0
	var schedule := get_encounter_config()
	if schedule != null:
		offset_cells = schedule.encounter_horizontal_offset_cells
	position = Vector2(
		-(
			config.terrain_screen_center_x
			+ float(offset_cells) * float(config.terrain_cell_world_size)
		),
		-config.mining_face_screen_y
	)


## Returns where the running game places this stage, in the terrain's own
## screen space, so a test can assert the editor agrees with the game.
func get_runtime_stage_screen_position() -> Vector2:
	var config := terrain_manager.config
	var offset_cells := 0
	var schedule := get_encounter_config()
	if schedule != null:
		offset_cells = schedule.encounter_horizontal_offset_cells
	return Vector2(
		config.terrain_screen_center_x
			+ float(offset_cells) * float(config.terrain_cell_world_size),
		config.mining_face_screen_y
	)


## Returns the encounter this stage plays at, or null when it is not tied to
## one or the named encounter is not in the schedule.
func get_encounter() -> DepthCharacterEncounter:
	var schedule := get_encounter_config()
	if schedule == null or encounter_id.is_empty():
		return null
	for encounter in schedule.encounters:
		if encounter != null and encounter.encounter_id == encounter_id:
			return encounter
	return null


## Returns the authored room this stage's encounter uses, or null.
func get_sculpt() -> CutsceneTerrainSculpt:
	var encounter := get_encounter()
	return null if encounter == null else encounter.terrain_sculpt


## Returns the world cell the authored room is measured from, so a tool can
## convert a click into a room coordinate.
func get_sculpt_anchor_cell() -> Vector2i:
	var encounter := get_encounter()
	if encounter == null:
		return Vector2i.ZERO
	return terrain_manager.get_encounter_anchor_cell(encounter)


## Converts a position in the edited scene into a fractional room coordinate.
## Fractional because a brush is dragged between cells; rounding here would
## make a slow drag stutter from cell centre to cell centre.
func global_position_to_sculpt_local(global_point: Vector2) -> Vector2:
	var sculpt := get_sculpt()
	if sculpt == null:
		return Vector2.ZERO
	var cell_size := float(terrain_manager.config.terrain_cell_world_size)
	var terrain_position := terrain_manager.screen_to_terrain_position(
		terrain_renderer.to_local(global_point)
	)
	var room_origin := get_sculpt_anchor_cell() + sculpt.anchor_offset_cells
	return terrain_position / cell_size - Vector2(room_origin)


## Converts a room coordinate back into the edited scene, so an overlay can
## outline the cells a brush is about to change.
func sculpt_local_to_global_position(local_cell: Vector2) -> Vector2:
	var sculpt := get_sculpt()
	if sculpt == null:
		return Vector2.ZERO
	var cell_size := float(terrain_manager.config.terrain_cell_world_size)
	var room_origin := get_sculpt_anchor_cell() + sculpt.anchor_offset_cells
	return terrain_renderer.to_global(
		terrain_manager.terrain_to_screen_position(
			(local_cell + Vector2(room_origin)) * cell_size
		)
	)


## Returns the world size of one terrain cell on screen, so an overlay can
## size a brush ring in the same units the brush works in.
func get_cell_screen_size() -> float:
	return float(terrain_manager.config.terrain_cell_world_size)


## Places the view at the authored depth, centred the way the run centres it.
func _get_preview_view_position() -> Vector2:
	var config := terrain_manager.config
	return Vector2(
		float(config.terrain_width_cells) * 0.5,
		float(config.initial_surface_row + get_effective_depth_rows())
	)


## Returns the depth this preview actually sits at: the encounter's own depth
## when one is named, so a stage cannot drift from the schedule that places it.
func get_effective_depth_rows() -> int:
	var encounter := get_encounter()
	if encounter == null or not follow_encounter_depth:
		return preview_depth_rows
	return encounter.resolve_depth(terrain_manager.config.total_run_depth)


## Digs one real tunnel per authored marker through the production terrain
## authority, so what appears is a mined opening rather than a drawn one.
func _apply_test_impacts() -> void:
	_tracked_impact_positions = _get_test_impact_positions()
	if _tracked_impact_positions.is_empty():
		return
	var config := terrain_manager.config
	# The renderer picks a hole size from the combo the hit resolved at, and
	# that arrives by signal during play. In the editor there is no controller
	# to send it, so the preview supplies the same value directly.
	terrain_renderer._on_dig_presentation_started(preview_combo)
	for marker_position in _tracked_impact_positions:
		terrain_manager.dig_tunnel(
			global_position_to_terrain_cell(marker_position),
			config.base_mine_depth_rows,
			config.base_tunnel_half_width_cells
		)


## Converts a position in the edited scene into the terrain cell drawn there.
##
## This has to go through the renderer's own transform. The renderer lays its
## chunks out in its local space using screen coordinates, and this preview is
## deliberately offset so the mining face lands on the stage origin. Reading a
## global position as if it were already screen space therefore digs one screen
## up and to the left of the click — the rock the designer aimed at stays
## solid while an opening appears off-frame.
func global_position_to_terrain_cell(global_point: Vector2) -> Vector2i:
	var cell_size := float(terrain_manager.config.terrain_cell_world_size)
	var terrain_position := terrain_manager.screen_to_terrain_position(
		terrain_renderer.to_local(global_point)
	)
	return Vector2i(
		floori(terrain_position.x / cell_size),
		floori(terrain_position.y / cell_size)
	)


## Returns where one terrain cell's top-left corner is drawn in the edited
## scene, so a tool can outline the cells it is about to change.
func terrain_cell_to_global_position(cell: Vector2i) -> Vector2:
	var cell_size := float(terrain_manager.config.terrain_cell_world_size)
	return terrain_renderer.to_global(
		terrain_manager.terrain_to_screen_position(
			Vector2(cell) * cell_size
		)
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
