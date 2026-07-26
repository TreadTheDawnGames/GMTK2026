@tool
class_name CutsceneEditorContext
extends RefCounted

## How it works:
## - Carries everything the cutscene editor's panels need about the scene
##   currently open: the stage, its terrain preview, the encounter it plays at,
##   the room being sculpted, and the timeline being authored.
## - The plugin rebuilds one of these whenever the edited scene changes and
##   hands the same instance to every panel, so no panel searches the tree or
##   caches its own idea of what is being edited.
## - It owns no UI and no undo history; it is a lookup, not a controller.
## The invariant is that a panel never reaches past this object for scene
## state, so a closed or swapped scene invalidates every panel at once.

## Emitted when a panel changes the sculpt or the sequence, so the other
## panels and the terrain preview can refresh from one place. Listening to this
## means rebuilding terrain, which is the expensive path.
signal authored_data_changed

## Emitted when a panel adds, removes or renames a cast member, prop or marker.
##
## Separate from authored_data_changed because nothing in that list is terrain:
## an actor is a node standing in the room, not a cell of it. Sharing one signal
## meant opening a stage rebuilt every chunk of a 384-cell-wide room three times
## over — once on load, then again for the cast and again for the miner — and
## the double-click that opens a cutscene wore all of it.
signal cast_changed

## Requests a timeline MOVE start from an actor's current stage-local position.
## The timeline owns the beat and decides whether to update or reject the
## request; the Cast panel only reports what the designer placed in the scene.
signal movement_start_position_requested(
	actor_id: StringName,
	stage_position: Vector2
)

## Requests a timeline MOVE destination from an actor's current stage-local
## position.
signal movement_destination_position_requested(
	actor_id: StringName,
	stage_position: Vector2
)

## Requests a new MOVE beat whose destination is the actor's current
## stage-local position.
signal movement_beat_creation_requested(
	actor_id: StringName,
	stage_position: Vector2
)

## Gives the timeline preview a chance to restore authored scene transforms
## before Cast records the "before" side of an undoable staging action.
signal stage_positions_will_change

var stage: Node2D
var preview: CinematicTerrainPreview
var encounter: DepthCharacterEncounter
var sculpt: CutsceneTerrainSculpt
var sequence: CutsceneSequence
var undo_redo: EditorUndoRedoManager
## The scene node new actors and props must be owned by, or nothing a panel
## adds will appear in the Scene dock or survive a save.
var scene_root: Node


## Reports whether there is a cutscene stage to edit at all.
func is_valid() -> bool:
	return is_instance_valid(stage) and is_instance_valid(preview)


## Reports whether terrain sculpting is available in the open scene.
func can_sculpt() -> bool:
	return is_valid() and sculpt != null and sculpt.get_sculpt_error().is_empty()


## Returns the actor ids a designer has placed in the open stage, in scene
## order, so the timeline draws one lane per visible cast member rather than
## only the ones that already have beats.
func get_stage_actor_ids() -> PackedStringArray:
	var actor_ids := PackedStringArray()
	if not is_valid():
		return actor_ids
	for node in _collect_actor_previews():
		if not node.actor_id.is_empty() and not actor_ids.has(node.actor_id):
			actor_ids.append(node.actor_id)
	return actor_ids


## Returns the placed stand-in for one actor id, so a panel can move or select
## the thing a designer can actually see.
func get_actor_preview(actor_id: StringName) -> CutsceneActorPreview:
	for node in _collect_actor_previews():
		if node.actor_id == actor_id:
			return node
	return null


## Returns direct Node2D children of PropMarkers. A composed prop such as a gem
## pile stays one selectable object; its sprites are presentation internals.
func get_stage_props() -> Array[Node2D]:
	var props: Array[Node2D] = []
	if not is_valid():
		return props
	var prop_root := stage.get_node_or_null(NodePath("PropMarkers"))
	if prop_root == null:
		return props
	for child: Node in prop_root.get_children():
		var prop := child as Node2D
		if prop != null and not prop is Marker2D:
			props.append(prop)
	return props


## Returns every object the Cast panel may transform, with actors first in
## scene order and composed props after them.
func get_stage_manipulable_nodes() -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	for preview_node in _collect_actor_previews():
		nodes.append(preview_node)
	nodes.append_array(get_stage_props())
	return nodes


## Keeps transform tools scoped to the stage's explicit cast and prop roots.
## Child sprites and terrain-preview furniture cannot be moved accidentally.
func is_stage_manipulable(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	for candidate in get_stage_manipulable_nodes():
		if candidate == node:
			return true
	return false


## Converts one selected object's origin into the coordinate space stored by a
## markerless cutscene beat.
func get_stage_local_position(node: Node2D) -> Vector2:
	if not is_stage_manipulable(node):
		return Vector2(NAN, NAN)
	return stage.to_local(node.global_position)


## Converts a stage-local transform target into the selected object's parent
## space, which lets actors and props share one align operation without losing
## either root's authored transform.
func stage_position_to_parent_position(
	node: Node2D,
	stage_position: Vector2
) -> Vector2:
	if not is_stage_manipulable(node):
		return Vector2(NAN, NAN)
	var parent_2d := node.get_parent() as Node2D
	if parent_2d == null:
		return stage_position
	return parent_2d.to_local(stage.to_global(stage_position))


## Resolves the first logical rock surface beneath an object's current origin
## and returns its top edge in stage space. X never moves: the sculpt column is
## sampled only to answer Y. A non-finite result means this object is outside a
## usable sculpt column or the room has no ground below it.
func get_floor_snap_stage_position(node: Node2D) -> Vector2:
	if (
		not is_stage_manipulable(node)
		or sculpt == null
		or not is_instance_valid(preview)
		or not can_sculpt()
	):
		return Vector2(NAN, NAN)
	var room_position := preview.global_position_to_sculpt_local(
		node.global_position
	)
	var local_x := floori(room_position.x)
	if local_x < 0 or local_x >= sculpt.grid_size.x:
		return Vector2(NAN, NAN)
	var first_row := clampi(floori(room_position.y), 0, sculpt.grid_size.y - 1)
	var surface_row := _find_surface_row_at_or_below(local_x, first_row)
	if surface_row < 0:
		return Vector2(NAN, NAN)
	var surface_global := preview.sculpt_local_to_global_position(
		Vector2(room_position.x, float(surface_row))
	)
	var current_stage_position := get_stage_local_position(node)
	var surface_stage_position := stage.to_local(surface_global)
	return Vector2(current_stage_position.x, surface_stage_position.y)


## Returns every named marker a beat can target, gathered from the stage's
## authored marker roots.
func get_marker_names() -> PackedStringArray:
	var marker_names := PackedStringArray()
	if not is_valid():
		return marker_names
	for root_name in ["ActorMarkers", "PropMarkers", "ActionMarkers"]:
		var root := stage.get_node_or_null(NodePath(root_name))
		if root == null:
			continue
		for child in root.get_children():
			if child is Marker2D:
				marker_names.append(child.name)
	return marker_names


## Resolves a marker name to its position in the stage's own space.
func get_marker_position(marker_name: StringName) -> Vector2:
	if not is_valid() or marker_name.is_empty():
		return Vector2.ZERO
	for root_name in ["ActorMarkers", "PropMarkers", "ActionMarkers"]:
		var root := stage.get_node_or_null(NodePath(root_name))
		if root == null:
			continue
		var marker := root.get_node_or_null(NodePath(marker_name)) as Marker2D
		if marker != null:
			return marker.global_position
	return Vector2.ZERO


## Announces an authored change once, after the caller has finished editing.
func notify_authored_data_changed() -> void:
	authored_data_changed.emit()


## Announces a cast, prop or marker edit. Panels that draw the room's occupants
## refresh; the terrain does not, because none of those touch a cell.
func notify_cast_changed() -> void:
	cast_changed.emit()


func notify_stage_positions_will_change() -> void:
	stage_positions_will_change.emit()


## Forwards a designer's explicit Cast action to whichever timeline panel owns
## the selected beat.
func request_movement_start_position(
	actor: CutsceneActorPreview
) -> bool:
	if not _can_request_actor_position(actor):
		return false
	movement_start_position_requested.emit(
		actor.actor_id,
		get_stage_local_position(actor)
	)
	return true


## Forwards a destination capture without coupling Cast to timeline selection.
func request_movement_destination_position(
	actor: CutsceneActorPreview
) -> bool:
	if not _can_request_actor_position(actor):
		return false
	movement_destination_position_requested.emit(
		actor.actor_id,
		get_stage_local_position(actor)
	)
	return true


## Forwards creation of a new MOVE beat from the staged actor position.
func request_movement_beat_creation(
	actor: CutsceneActorPreview
) -> bool:
	if not _can_request_actor_position(actor):
		return false
	movement_beat_creation_requested.emit(
		actor.actor_id,
		get_stage_local_position(actor)
	)
	return true


func _can_request_actor_position(actor: CutsceneActorPreview) -> bool:
	if (
		not is_instance_valid(actor)
		or actor.actor_id.is_empty()
		or not is_stage_manipulable(actor)
	):
		return false
	var stage_position := get_stage_local_position(actor)
	return (
		not is_nan(stage_position.x)
		and not is_inf(stage_position.x)
		and not is_nan(stage_position.y)
		and not is_inf(stage_position.y)
	)


func _find_surface_row_at_or_below(local_x: int, first_row: int) -> int:
	if sculpt.is_solid_local(Vector2i(local_x, first_row)):
		var containing_surface := first_row
		while (
			containing_surface > 0
			and sculpt.is_solid_local(
				Vector2i(local_x, containing_surface - 1)
			)
		):
			containing_surface -= 1
		return containing_surface
	for local_y in range(first_row, sculpt.grid_size.y):
		if not sculpt.is_solid_local(Vector2i(local_x, local_y)):
			continue
		if (
			local_y == 0
			or not sculpt.is_solid_local(Vector2i(local_x, local_y - 1))
		):
			return local_y
	return -1


func _collect_actor_previews() -> Array[CutsceneActorPreview]:
	var previews: Array[CutsceneActorPreview] = []
	if not is_valid():
		return previews
	for child in stage.get_children():
		if child is CutsceneActorPreview:
			previews.append(child)
		for grandchild in child.get_children():
			if grandchild is CutsceneActorPreview:
				previews.append(grandchild)
	return previews
