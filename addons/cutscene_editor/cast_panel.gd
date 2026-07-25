@tool
class_name CutsceneCastPanel
extends VBoxContainer

## How it works:
## - Reads the shared context and builds cast, prop, and marker controls in code.
## - Structural edits are staged through the context's undo manager.
## - Actor rows select the real preview node so the Inspector owns positioning.
## - The context signal rebuilds this panel after edits and undo/redo.
## The invariant is that every authored node has the edited scene as owner and
## every structural change has a matching undo operation and one notification.

const _MARKER_ROOT_NAMES: Array[StringName] = [
	&"ActorMarkers",
	&"PropMarkers",
	&"ActionMarkers",
]

var _context: CutsceneEditorContext
var _status_label: Label
var _actor_picker: EditorResourcePicker
var _actor_id_edit: LineEdit
var _prop_picker: EditorResourcePicker
var _prop_name_edit: LineEdit
var _marker_root_selector: OptionButton
var _marker_name_edit: LineEdit
var _selected_preview: CutsceneActorPreview


func _init() -> void:
	name = &"Cast"
	_rebuild()


## Rebinds the panel to one open stage, or shows a safe empty state.
func set_context(context: CutsceneEditorContext) -> void:
	if (
		_context != null
		and is_instance_valid(_context)
		and _context != context
		and _context.authored_data_changed.is_connected(
			_on_authored_data_changed
		)
	):
		_context.authored_data_changed.disconnect(_on_authored_data_changed)
	_context = context
	if (
		_context != null
		and not _context.authored_data_changed.is_connected(
			_on_authored_data_changed
		)
	):
		_context.authored_data_changed.connect(_on_authored_data_changed)
	_rebuild()


func _rebuild() -> void:
	_clear_contents()
	_selected_preview = null
	if not _has_valid_context():
		var message := Label.new()
		message.text = "Open a cutscene stage to edit its cast and props."
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(message)
		return
	_build_controls()


func _clear_contents() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_status_label = null
	_actor_picker = null
	_actor_id_edit = null
	_prop_picker = null
	_prop_name_edit = null
	_marker_root_selector = null
	_marker_name_edit = null


func _has_valid_context() -> bool:
	return (
		_context != null
		and is_instance_valid(_context)
		and _context.is_valid()
		and is_instance_valid(_context.scene_root)
		and _context.undo_redo != null
	)


func _build_controls() -> void:
	var title := Label.new()
	title.text = "Cast and Stage Dressing"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	add_child(_make_section_label("Cast"))
	var cast_scroll := ScrollContainer.new()
	cast_scroll.custom_minimum_size.y = 120.0
	cast_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cast_list := VBoxContainer.new()
	cast_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cast_scroll.add_child(cast_list)
	add_child(cast_scroll)
	_build_cast_rows(cast_list)

	var remove_button := Button.new()
	remove_button.text = "Remove Selected Actor"
	remove_button.pressed.connect(_on_remove_actor_pressed)
	add_child(remove_button)

	add_child(HSeparator.new())
	add_child(_make_section_label("Add Actor"))
	_actor_id_edit = LineEdit.new()
	_actor_id_edit.placeholder_text = "Stable actor id, for example miner"
	_actor_id_edit.tooltip_text = (
		"The timeline keys actor lanes by this stable id."
	)
	_add_labeled_control("Actor id", _actor_id_edit)
	_actor_picker = EditorResourcePicker.new()
	_actor_picker.base_type = "CharacterAppearance"
	_actor_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_labeled_control("Appearance", _actor_picker)
	var add_actor_button := Button.new()
	add_actor_button.text = "Add Actor"
	add_actor_button.pressed.connect(_on_add_actor_pressed)
	add_child(add_actor_button)

	add_child(HSeparator.new())
	add_child(_make_section_label("Add Prop"))
	_prop_name_edit = LineEdit.new()
	_prop_name_edit.placeholder_text = "Name in the PropMarkers root"
	_add_labeled_control("Prop name", _prop_name_edit)
	_prop_picker = EditorResourcePicker.new()
	_prop_picker.base_type = "PackedScene"
	_prop_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_labeled_control("Prop scene", _prop_picker)
	var add_prop_button := Button.new()
	add_prop_button.text = "Add Prop"
	add_prop_button.pressed.connect(_on_add_prop_pressed)
	add_child(add_prop_button)

	add_child(HSeparator.new())
	add_child(_make_section_label("Add Marker"))
	_marker_root_selector = OptionButton.new()
	for root_name: StringName in _MARKER_ROOT_NAMES:
		_marker_root_selector.add_item(String(root_name))
	_marker_root_selector.select(0)
	_add_labeled_control("Marker root", _marker_root_selector)
	_marker_name_edit = LineEdit.new()
	_marker_name_edit.placeholder_text = "Name targeted by a beat"
	_add_labeled_control("Marker name", _marker_name_edit)
	var add_marker_button := Button.new()
	add_marker_button.text = "Add Marker"
	add_marker_button.pressed.connect(_on_add_marker_pressed)
	add_child(add_marker_button)


func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	return label


func _add_labeled_control(label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 100.0
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	add_child(row)


func _build_cast_rows(cast_list: VBoxContainer) -> void:
	var row_count := 0
	for actor_id: StringName in _context.get_stage_actor_ids():
		var preview := _context.get_actor_preview(actor_id)
		if preview == null:
			continue
		var row := HBoxContainer.new()
		var select_button := Button.new()
		select_button.text = (
			String(preview.actor_id) if not preview.actor_id.is_empty()
			else "<unnamed actor>"
		)
		select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select_button.tooltip_text = "Select this stand-in in the 2D editor."
		select_button.pressed.connect(
			_on_actor_row_pressed.bind(preview)
		)
		row.add_child(select_button)

		var appearance_label := Label.new()
		appearance_label.text = _get_appearance_name(preview.appearance)
		appearance_label.custom_minimum_size.x = 150.0
		row.add_child(appearance_label)

		var preview_error := preview.get_preview_error()
		if not preview_error.is_empty():
			var warning_label := Label.new()
			warning_label.text = "Warning: %s" % preview_error
			warning_label.tooltip_text = preview_error
			warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(warning_label)
		cast_list.add_child(row)
		row_count += 1
	if row_count == 0:
		var empty_label := Label.new()
		empty_label.text = "No actors placed in this stage."
		cast_list.add_child(empty_label)


func _get_appearance_name(appearance: CharacterAppearance) -> String:
	if appearance == null:
		return "No appearance"
	if not appearance.resource_name.is_empty():
		return appearance.resource_name
	if not appearance.resource_path.is_empty():
		return appearance.resource_path.get_file().get_basename()
	return "Unnamed appearance"


func _on_authored_data_changed() -> void:
	_rebuild()


func _on_actor_row_pressed(preview: CutsceneActorPreview) -> void:
	if not is_instance_valid(preview):
		return
	_selected_preview = preview
	var selection = EditorInterface.get_selection()
	if selection == null:
		return
	selection.clear()
	selection.add_node(preview)


func _on_add_actor_pressed() -> void:
	if not _has_valid_context():
		return
	var actor_id := StringName(_actor_id_edit.text.strip_edges())
	if actor_id.is_empty():
		_set_status("Actor id is required.")
		return
	if _context.get_stage_actor_ids().has(actor_id):
		_set_status("Actor id '%s' is already in the cast." % actor_id)
		return
	var appearance := _actor_picker.edited_resource as CharacterAppearance
	if appearance == null:
		_set_status("Choose a CharacterAppearance before adding the actor.")
		return

	var actor := CutsceneActorPreview.new()
	actor.name = _make_unique_child_name(_context.stage, String(actor_id))
	actor.actor_id = actor_id
	actor.appearance = appearance
	var conversation_marker := _get_conversation_marker()
	if conversation_marker != null:
		actor.position = _context.stage.to_local(
			conversation_marker.global_position
		)
	var undo_redo := _context.undo_redo
	undo_redo.create_action("Add cutscene actor")
	undo_redo.add_do_method(
		_context.stage,
		&"add_child",
		actor
	)
	undo_redo.add_do_property(actor, &"owner", _context.scene_root)
	undo_redo.add_undo_method(
		_context,
		&"notify_authored_data_changed"
	)
	undo_redo.add_undo_method(_context.stage, &"remove_child", actor)
	undo_redo.add_do_reference(actor)
	undo_redo.add_do_method(
		_context,
		&"notify_authored_data_changed"
	)
	undo_redo.commit_action()
	_selected_preview = actor
	_on_actor_row_pressed(actor)


func _on_remove_actor_pressed() -> void:
	if not _has_valid_context():
		return
	var preview := _get_selected_actor_preview()
	if preview == null or preview.get_parent() == null:
		_set_status("Select an actor stand-in to remove it.")
		return
	var parent := preview.get_parent()
	var undo_redo := _context.undo_redo
	undo_redo.create_action("Remove cutscene actor")
	undo_redo.add_do_method(parent, &"remove_child", preview)
	undo_redo.add_do_method(
		_context,
		&"notify_authored_data_changed"
	)
	undo_redo.add_undo_method(
		_context,
		&"notify_authored_data_changed"
	)
	undo_redo.add_undo_method(parent, &"add_child", preview)
	undo_redo.commit_action()
	_selected_preview = null


func _get_selected_actor_preview() -> CutsceneActorPreview:
	if is_instance_valid(_selected_preview):
		return _selected_preview
	var selection = EditorInterface.get_selection()
	if selection == null:
		return null
	for selected: Node in selection.get_selected_nodes():
		if selected is CutsceneActorPreview:
			return selected
	return null


func _on_add_prop_pressed() -> void:
	if not _has_valid_context():
		return
	var prop_name := _prop_name_edit.text.strip_edges()
	if prop_name.is_empty():
		_set_status("Prop name is required.")
		return
	var prop_scene := _prop_picker.edited_resource as PackedScene
	if prop_scene == null:
		_set_status("Choose a PackedScene before adding the prop.")
		return
	var prop_root := _get_stage_root(&"PropMarkers")
	if prop_root == null:
		_set_status("This stage has no PropMarkers root.")
		return
	var prop := prop_scene.instantiate()
	if prop == null:
		_set_status("The selected prop scene could not be instantiated.")
		return
	prop.name = _make_unique_child_name(prop_root, prop_name)
	var undo_redo := _context.undo_redo
	undo_redo.create_action("Add cutscene prop")
	undo_redo.add_do_method(prop_root, &"add_child", prop)
	undo_redo.add_do_property(prop, &"owner", _context.scene_root)
	undo_redo.add_undo_method(
		_context,
		&"notify_authored_data_changed"
	)
	undo_redo.add_undo_method(prop_root, &"remove_child", prop)
	undo_redo.add_do_reference(prop)
	undo_redo.add_do_method(
		_context,
		&"notify_authored_data_changed"
	)
	undo_redo.commit_action()


func _on_add_marker_pressed() -> void:
	if not _has_valid_context():
		return
	var marker_name := _marker_name_edit.text.strip_edges()
	if marker_name.is_empty():
		_set_status("Marker name is required.")
		return
	var root_index := _marker_root_selector.selected
	var marker_root := _get_stage_root(_MARKER_ROOT_NAMES[root_index])
	if marker_root == null:
		_set_status("This stage has no selected marker root.")
		return
	var marker := Marker2D.new()
	marker.name = _make_unique_child_name(marker_root, marker_name)
	var undo_redo := _context.undo_redo
	undo_redo.create_action("Add cutscene marker")
	undo_redo.add_do_method(marker_root, &"add_child", marker)
	undo_redo.add_do_property(marker, &"owner", _context.scene_root)
	undo_redo.add_undo_method(
		_context,
		&"notify_authored_data_changed"
	)
	undo_redo.add_undo_method(marker_root, &"remove_child", marker)
	undo_redo.add_do_reference(marker)
	undo_redo.add_do_method(
		_context,
		&"notify_authored_data_changed"
	)
	undo_redo.commit_action()


func _get_stage_root(root_name: StringName) -> Node:
	if not _has_valid_context():
		return null
	return _context.stage.get_node_or_null(NodePath(root_name))


func _get_conversation_marker() -> Marker2D:
	var actor_root := _get_stage_root(&"ActorMarkers")
	if actor_root == null:
		return null
	return actor_root.get_node_or_null(NodePath("Conversation")) as Marker2D


func _make_unique_child_name(parent: Node, requested_name: String) -> StringName:
	var base_name := requested_name.replace("/", "_").replace("\\", "_")
	if base_name.is_empty():
		base_name = "Item"
	var candidate := base_name
	var suffix := 2
	while _has_child_named(parent, StringName(candidate)):
		candidate = "%s_%d" % [base_name, suffix]
		suffix += 1
	return StringName(candidate)


func _has_child_named(parent: Node, child_name: StringName) -> bool:
	for child: Node in parent.get_children():
		if child.name == child_name:
			return true
	return false


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
