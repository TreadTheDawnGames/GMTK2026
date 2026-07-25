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
