@tool
extends EditorPlugin

## How it works:
## - Adds a "Dig Terrain" toggle to the 2D viewport toolbar, shown only while a
##   scene containing a CinematicTerrainPreview is open.
## - While it is on, left-click digs a real hit into the previewed terrain and
##   Alt-click heals the nearest one. Both go through the preview, which digs
##   through the production TerrainManager, so a click breaks actual cells.
## - Every click adds or removes an authored Marker2D owned by the edited
##   scene, so the dug state is visible in the Scene dock and saves with the
##   cutscene rather than vanishing on reload.
## - It owns no terrain state and draws nothing; switch it off and the preview
##   behaves exactly as it did before.
## The invariant is that this only ever edits authored markers, never terrain
## directly, so nothing it does can desynchronise the preview from the game.

## Clicks land on the rock the designer aimed at, not a marker several hundred
## pixels away, so healing only claims impacts within roughly one opening.
const _HEAL_RADIUS_PIXELS: float = 96.0

var _dig_button: Button


func _enter_tree() -> void:
	_dig_button = Button.new()
	_dig_button.text = "Dig Terrain"
	_dig_button.toggle_mode = true
	_dig_button.tooltip_text = (
		"Click the previewed terrain to dig a real hit. "
		+ "Alt-click an opening to heal it."
	)
	_dig_button.hide()
	add_control_to_container(
		EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU,
		_dig_button
	)
	scene_changed.connect(_on_scene_changed)
	_on_scene_changed(EditorInterface.get_edited_scene_root())


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	if _dig_button != null:
		remove_control_from_container(
			EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU,
			_dig_button
		)
		_dig_button.queue_free()
		_dig_button = null


## Claims viewport input only while the toggle is on, so ordinary selection and
## marker dragging keep working the rest of the time.
func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _dig_button == null or not _dig_button.button_pressed:
		return false
	var preview := _find_preview()
	if preview == null:
		return false
	var mouse_event := event as InputEventMouseButton
	if (
		mouse_event == null
		or not mouse_event.pressed
		or mouse_event.button_index != MOUSE_BUTTON_LEFT
	):
		return false
	var world_position := _to_world_position(mouse_event.position)
	if mouse_event.alt_pressed:
		if preview.heal_nearest_impact(world_position, _HEAL_RADIUS_PIXELS):
			_commit("Heal cutscene terrain")
		return true
	if preview.dig_at_world_position(world_position):
		_commit("Dig cutscene terrain")
	return true


## The 2D editor reports clicks in its own control space. The viewport's canvas
## transform is the only thing that knows the current pan and zoom, so the
## inverse of it is what turns a click back into a scene coordinate.
func _to_world_position(event_position: Vector2) -> Vector2:
	var editor_viewport := EditorInterface.get_editor_viewport_2d()
	if editor_viewport == null:
		return event_position
	return (
		editor_viewport.global_canvas_transform.affine_inverse()
		* event_position
	)


## Shows the toggle only where it can act, and never leaves it armed in a scene
## that has no terrain to dig.
func _on_scene_changed(_scene_root: Node) -> void:
	if _dig_button == null:
		return
	var has_preview := _find_preview() != null
	_dig_button.visible = has_preview
	if not has_preview:
		_dig_button.button_pressed = false


func _find_preview() -> CinematicTerrainPreview:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return null
	if scene_root is CinematicTerrainPreview:
		return scene_root
	for child in scene_root.get_children():
		if child is CinematicTerrainPreview:
			return child
	return null


## Marks the scene dirty so the new marker is part of the next save. The
## preview rebuilds itself, so there is nothing else to undo.
func _commit(action_name: String) -> void:
	var undo_redo := get_undo_redo()
	undo_redo.create_action(action_name)
	undo_redo.commit_action(false)
