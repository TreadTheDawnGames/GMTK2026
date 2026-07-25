@tool
class_name CutsceneBeatInspector
extends VBoxContainer

## How it works:
## - The inspector rebuilds a compact form from the selected beat's kind.
## - Shared timing fields appear for every beat; kind-specific fields stay focused.
## - Marker, actor, and dialogue line choices come from the current editor context.
## - Each committed field edit is one EditorUndoRedoManager action.
## - The invariant is that a visible control never edits a different beat than the one shown.

const FIELD_START_SECONDS: StringName = &"start_seconds"
const FIELD_DURATION_SECONDS: StringName = &"duration_seconds"
const FIELD_BLOCKS: StringName = &"blocks"
const FIELD_NOTES: StringName = &"notes"
const FIELD_ACTOR: StringName = &"actor"
const FIELD_TARGET_MARKER: StringName = &"target_marker"
const FIELD_TARGET_OFFSET: StringName = &"target_offset"
const FIELD_POSE: StringName = &"pose"
const FIELD_STEP_HEIGHT: StringName = &"step_height"
const FIELD_FACING: StringName = &"facing"
const FIELD_BOUNCE_COUNT: StringName = &"bounce_count"
const FIELD_CONVERSATION: StringName = &"conversation"
const FIELD_LINE_RANGE: StringName = &"line_range"
const FIELD_CUE: StringName = &"cue"

var _context: CutsceneEditorContext
var _selected_beat: CutsceneBeat
var _form: VBoxContainer


## Replaces the lookup used by every field and clears a stale selection.
func set_context(context: CutsceneEditorContext) -> void:
	_context = context
	_selected_beat = null
	_rebuild()


## Shows one beat and exposes only the fields that kind uses.
func show_beat(beat: CutsceneBeat) -> void:
	_selected_beat = beat
	_rebuild()


## Returns the playable pose names authored for one placed actor preview.
func get_pose_names_for_actor(actor_id: StringName) -> PackedStringArray:
	var pose_names := PackedStringArray()
	var pose_set := _get_actor_pose_set(actor_id)
	if pose_set == null:
		return pose_names
	for pose in pose_set.poses:
		if pose == null or not pose.is_playable():
			continue
		if not pose_names.has(str(pose.pose_name)):
			pose_names.append(str(pose.pose_name))
	return pose_names


## Returns the field names that should be visible for a beat kind.
func get_visible_fields_for_kind(kind: int) -> PackedStringArray:
	var fields := PackedStringArray([
		str(FIELD_START_SECONDS),
		str(FIELD_DURATION_SECONDS),
		str(FIELD_BLOCKS),
		str(FIELD_NOTES),
	])
	if _kind_uses_actor(kind):
		fields.append(str(FIELD_ACTOR))
	match kind:
		CutsceneBeat.Kind.MOVE:
			fields.append(str(FIELD_TARGET_MARKER))
			fields.append(str(FIELD_TARGET_OFFSET))
			fields.append(str(FIELD_POSE))
			fields.append(str(FIELD_STEP_HEIGHT))
		CutsceneBeat.Kind.POSE:
			fields.append(str(FIELD_POSE))
		CutsceneBeat.Kind.FACE:
			fields.append(str(FIELD_FACING))
		CutsceneBeat.Kind.BOUNCE:
			fields.append(str(FIELD_BOUNCE_COUNT))
		CutsceneBeat.Kind.DIALOGUE:
			fields.append(str(FIELD_CONVERSATION))
			fields.append(str(FIELD_LINE_RANGE))
		CutsceneBeat.Kind.STAGE_CUE, CutsceneBeat.Kind.STRIKE:
			fields.append(str(FIELD_CUE))
		CutsceneBeat.Kind.PROP:
			fields.append(str(FIELD_TARGET_MARKER))
			fields.append(str(FIELD_TARGET_OFFSET))
		_:
			pass
	return fields


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.free()
	_form = VBoxContainer.new()
	_form.name = "BeatFields"
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_form)
	if _selected_beat == null:
		var empty := Label.new()
		empty.text = "Select a beat to edit its details."
		empty.add_theme_color_override(&"font_color", Color("#a9b0bd"))
		_form.add_child(empty)
		return
	if _context == null or not _context.is_valid():
		var unavailable := Label.new()
		unavailable.text = "Open a cutscene stage to edit this beat."
		_form.add_child(unavailable)
		return
	var title := Label.new()
	title.text = "%s beat" % CutsceneBeat.Kind.keys()[_selected_beat.kind]
	title.add_theme_font_size_override(&"font_size", 15)
	_form.add_child(title)
	_add_number_field(
		"Start",
		FIELD_START_SECONDS,
		_selected_beat.start_seconds,
		0.0,
		3600.0,
		0.1
	)
	_add_number_field(
		"Duration",
		FIELD_DURATION_SECONDS,
		_selected_beat.duration_seconds,
		0.0,
		3600.0,
		0.1
	)
	_add_check_field("Blocks sequence", FIELD_BLOCKS, _selected_beat.blocks)
	if _kind_uses_actor(_selected_beat.kind):
		_add_actor_field()
	match _selected_beat.kind:
		CutsceneBeat.Kind.MOVE:
			_add_marker_field()
			_add_vector_field("Target offset", FIELD_TARGET_OFFSET, _selected_beat.target_offset)
			_add_pose_field()
			_add_number_field(
				"Step height",
				FIELD_STEP_HEIGHT,
				_selected_beat.step_height,
				0.0,
				256.0,
				0.5
			)
		CutsceneBeat.Kind.POSE:
			_add_pose_field()
		CutsceneBeat.Kind.FACE:
			_add_facing_field()
		CutsceneBeat.Kind.BOUNCE:
			_add_number_field(
				"Bounce count",
				FIELD_BOUNCE_COUNT,
				_selected_beat.bounce_count,
				0.0,
				99.0,
				1.0
			)
		CutsceneBeat.Kind.DIALOGUE:
			_add_conversation_field()
			_add_line_range_field()
		CutsceneBeat.Kind.STAGE_CUE, CutsceneBeat.Kind.STRIKE:
			_add_text_field("Cue", FIELD_CUE, _selected_beat.cue)
		CutsceneBeat.Kind.PROP:
			_add_marker_field()
			_add_vector_field("Target offset", FIELD_TARGET_OFFSET, _selected_beat.target_offset)
		_:
			pass
	_add_notes_field()


func _add_number_field(
	caption: String,
	property_name: StringName,
	current_value: float,
	minimum: float,
	maximum: float,
	step: float
) -> void:
	var row := _make_row(caption)
	var spin := SpinBox.new()
	spin.name = String(property_name)
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = current_value
	spin.allow_greater = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	if not spin.value_changed.is_connected(_on_number_changed):
		spin.value_changed.connect(_on_number_changed.bind(property_name))


func _add_check_field(
	caption: String,
	property_name: StringName,
	current_value: bool
) -> void:
	var row := _make_row(caption)
	var check := CheckButton.new()
	check.name = String(property_name)
	check.button_pressed = current_value
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(check)
	if not check.toggled.is_connected(_on_check_changed):
		check.toggled.connect(_on_check_changed.bind(property_name))


func _add_actor_field() -> void:
	var row := _make_row("Actor")
	var option := OptionButton.new()
	option.name = String(FIELD_ACTOR)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var actor_ids := _context.get_stage_actor_ids()
	var selected_index := -1
	for actor_id_text in actor_ids:
		var actor_id := StringName(actor_id_text)
		option.add_item(actor_id_text)
		option.set_item_metadata(option.item_count - 1, actor_id)
		if actor_id == _selected_beat.actor:
			selected_index = option.item_count - 1
	if selected_index < 0 and not _selected_beat.actor.is_empty():
		option.add_item(str(_selected_beat.actor) + " (unknown)")
		option.set_item_metadata(option.item_count - 1, _selected_beat.actor)
		selected_index = option.item_count - 1
	if selected_index >= 0:
		option.select(selected_index)
	row.add_child(option)
	if not option.item_selected.is_connected(_on_actor_changed):
		option.item_selected.connect(_on_actor_changed.bind(FIELD_ACTOR))


func _add_marker_field() -> void:
	var row := _make_row("Target marker")
	var option := OptionButton.new()
	option.name = String(FIELD_TARGET_MARKER)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_item("No marker")
	option.set_item_metadata(0, StringName())
	var selected_index := 0
	for marker_name_text in _context.get_marker_names():
		var marker_name := StringName(marker_name_text)
		option.add_item(marker_name_text)
		option.set_item_metadata(option.item_count - 1, marker_name)
		if marker_name == _selected_beat.target_marker:
			selected_index = option.item_count - 1
	if selected_index == 0 and not _selected_beat.target_marker.is_empty():
		option.add_item(str(_selected_beat.target_marker) + " (unknown)")
		option.set_item_metadata(option.item_count - 1, _selected_beat.target_marker)
		selected_index = option.item_count - 1
	option.select(selected_index)
	row.add_child(option)
	if not option.item_selected.is_connected(_on_marker_changed):
		option.item_selected.connect(_on_marker_changed)


func _add_pose_field() -> void:
	var row := _make_row("Pose")
	var option := OptionButton.new()
	option.name = String(FIELD_POSE)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pose_set := _get_actor_pose_set(_selected_beat.actor)
	var pose_names := get_pose_names_for_actor(_selected_beat.actor)
	if pose_names.is_empty():
		option.add_item(
			"No pose set"
			if pose_set == null
			else "No playable poses"
		)
		option.disabled = true
	else:
		var selected_index := -1
		for pose_name in pose_names:
			option.add_item(pose_name)
			option.set_item_metadata(option.item_count - 1, StringName(pose_name))
			if StringName(pose_name) == _selected_beat.pose:
				selected_index = option.item_count - 1
		if selected_index >= 0:
			option.select(selected_index)
		else:
			option.select(-1)
		if (
			not _selected_beat.pose.is_empty()
			and not pose_names.has(str(_selected_beat.pose))
		):
			var warning := Label.new()
			warning.text = "Current pose is not in this pose set."
			warning.add_theme_color_override(
				&"font_color",
				Color("#e5a15b")
			)
			_form.add_child(warning)
	row.add_child(option)
	if not option.item_selected.is_connected(_on_pose_changed):
		option.item_selected.connect(_on_pose_changed)


func _get_actor_pose_set(actor_id: StringName) -> ActorPoseSet:
	if _context == null or actor_id.is_empty():
		return null
	var preview := _context.get_actor_preview(actor_id)
	if not is_instance_valid(preview) or preview.appearance == null:
		return null
	return preview.appearance.pose_set


func _add_vector_field(
	caption: String,
	property_name: StringName,
	current_value: Vector2
) -> void:
	var row := _make_row(caption)
	var x_spin := SpinBox.new()
	x_spin.name = String(property_name) + "X"
	x_spin.min_value = -10000.0
	x_spin.max_value = 10000.0
	x_spin.step = 1.0
	x_spin.value = current_value.x
	x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(x_spin)
	var y_spin := SpinBox.new()
	y_spin.name = String(property_name) + "Y"
	y_spin.min_value = -10000.0
	y_spin.max_value = 10000.0
	y_spin.step = 1.0
	y_spin.value = current_value.y
	y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(y_spin)
	if not x_spin.value_changed.is_connected(_on_vector_x_changed):
		x_spin.value_changed.connect(_on_vector_x_changed.bind(y_spin, property_name))
	if not y_spin.value_changed.is_connected(_on_vector_y_changed):
		y_spin.value_changed.connect(_on_vector_y_changed.bind(x_spin, property_name))


func _add_facing_field() -> void:
	var row := _make_row("Facing")
	var option := OptionButton.new()
	option.name = String(FIELD_FACING)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_item("Auto / unchanged")
	option.set_item_metadata(0, 0)
	option.add_item("Left")
	option.set_item_metadata(1, -1)
	option.add_item("Right")
	option.set_item_metadata(2, 1)
	var selected_index := 0
	for index in range(option.item_count):
		if int(option.get_item_metadata(index)) == _selected_beat.facing:
			selected_index = index
	option.select(selected_index)
	row.add_child(option)
	if not option.item_selected.is_connected(_on_facing_changed):
		option.item_selected.connect(_on_facing_changed)


func _add_conversation_field() -> void:
	var row := _make_row("Conversation")
	var value := LineEdit.new()
	value.name = String(FIELD_CONVERSATION)
	value.editable = false
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _selected_beat.conversation == null:
		value.text = "(none assigned)"
	else:
		value.text = str(_selected_beat.conversation.conversation_id)
	row.add_child(value)


func _add_line_range_field() -> void:
	var row := _make_row("Line range")
	var start_option := _make_line_option(true)
	var end_option := _make_line_option(false)
	row.add_child(start_option)
	row.add_child(end_option)
	if not start_option.item_selected.is_connected(_on_line_start_changed):
		start_option.item_selected.connect(_on_line_start_changed.bind(end_option))
	if not end_option.item_selected.is_connected(_on_line_end_changed):
		end_option.item_selected.connect(_on_line_end_changed.bind(start_option))
	if _selected_beat.conversation == null:
		start_option.disabled = true
		end_option.disabled = true


func _make_line_option(is_start: bool) -> OptionButton:
	var option := OptionButton.new()
	option.name = "LineStart" if is_start else "LineEnd"
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_item("Whole conversation")
	option.set_item_metadata(0, -1)
	var selected_value := (
		_selected_beat.line_range.x
		if is_start
		else _selected_beat.line_range.y
	)
	for line_index in range(_selected_beat.conversation.lines.size() if _selected_beat.conversation != null else 0):
		var line := _selected_beat.conversation.lines[line_index]
		var line_text := "[%d]" % line_index
		if line != null:
			line_text += " " + str(line.speaker_slot) + ": " + line.text
		option.add_item(line_text)
		option.set_item_metadata(option.item_count - 1, line_index)
	var selected_index := 0
	if selected_value >= 0 and selected_value < option.item_count - 1:
		selected_index = selected_value + 1
	option.select(selected_index)
	return option


func _add_notes_field() -> void:
	var label := Label.new()
	label.text = "Notes"
	_form.add_child(label)
	var notes := TextEdit.new()
	notes.name = String(FIELD_NOTES)
	notes.text = _selected_beat.notes
	notes.custom_minimum_size = Vector2(0.0, 54.0)
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_child(notes)
	if not notes.focus_exited.is_connected(_on_notes_focus_exited):
		notes.focus_exited.connect(_on_notes_focus_exited.bind(notes))


func _add_text_field(
	caption: String,
	property_name: StringName,
	current_value: StringName
) -> void:
	var row := _make_row(caption)
	var line_edit := LineEdit.new()
	line_edit.name = String(property_name)
	line_edit.text = str(current_value)
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line_edit)
	if not line_edit.text_submitted.is_connected(_on_text_submitted):
		line_edit.text_submitted.connect(_on_text_submitted.bind(property_name))
	if not line_edit.focus_exited.is_connected(_on_text_focus_exited):
		line_edit.focus_exited.connect(_on_text_focus_exited.bind(line_edit, property_name))


func _make_row(caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(112.0, 0.0)
	row.add_child(label)
	_form.add_child(row)
	return row


func _on_number_changed(value: float, property_name: StringName) -> void:
	if _selected_beat == null:
		return
	_commit_property(property_name, maxf(value, 0.0), "Edit %s" % property_name)


func _on_check_changed(value: bool, property_name: StringName) -> void:
	_commit_property(property_name, value, "Edit %s" % property_name)


func _on_actor_changed(index: int, _property_name: StringName) -> void:
	if _selected_beat == null:
		return
	var option := _find_control(String(FIELD_ACTOR)) as OptionButton
	if option == null or index < 0:
		return
	_commit_property(
		FIELD_ACTOR,
		option.get_item_metadata(index),
		"Edit actor"
	)


func _on_marker_changed(index: int) -> void:
	if _selected_beat == null:
		return
	var option := _find_control(String(FIELD_TARGET_MARKER)) as OptionButton
	if option == null or index < 0:
		return
	_commit_property(
		FIELD_TARGET_MARKER,
		option.get_item_metadata(index),
		"Edit target marker"
	)


func _on_pose_changed(index: int) -> void:
	if _selected_beat == null:
		return
	var option := _find_control(String(FIELD_POSE)) as OptionButton
	if option == null or index < 0:
		return
	_commit_property(
		FIELD_POSE,
		option.get_item_metadata(index),
		"Edit pose"
	)


func _on_vector_x_changed(value: float, y_spin: SpinBox, property_name: StringName) -> void:
	if _selected_beat == null:
		return
	_commit_property(
		property_name,
		Vector2(value, y_spin.value),
		"Edit %s" % property_name
	)


func _on_vector_y_changed(value: float, x_spin: SpinBox, property_name: StringName) -> void:
	if _selected_beat == null:
		return
	_commit_property(
		property_name,
		Vector2(x_spin.value, value),
		"Edit %s" % property_name
	)


func _on_facing_changed(index: int) -> void:
	if _selected_beat == null:
		return
	var option := _find_control(String(FIELD_FACING)) as OptionButton
	if option != null:
		_commit_property(FIELD_FACING, int(option.get_item_metadata(index)), "Edit facing")


func _on_line_start_changed(index: int, end_option: OptionButton) -> void:
	if _selected_beat == null:
		return
	var start_value := int(end_option.get_item_metadata(0))
	var start_option := _find_control("LineStart") as OptionButton
	if start_option == null:
		return
	start_value = int(start_option.get_item_metadata(index))
	var end_value := int(end_option.get_item_metadata(end_option.selected))
	if start_value < 0:
		end_value = -1
	elif end_value < 0 or end_value < start_value:
		end_value = start_value
	_commit_line_range(Vector2i(start_value, end_value))


func _on_line_end_changed(index: int, start_option: OptionButton) -> void:
	if _selected_beat == null:
		return
	var end_option := _find_control("LineEnd") as OptionButton
	if end_option == null:
		return
	var end_value := int(end_option.get_item_metadata(index))
	var start_value := int(start_option.get_item_metadata(start_option.selected))
	if end_value < 0:
		start_value = -1
	elif start_value < 0 or end_value < start_value:
		start_value = end_value
	_commit_line_range(Vector2i(start_value, end_value))


func _on_text_submitted(value: String, property_name: StringName) -> void:
	_commit_property(property_name, StringName(value.strip_edges()), "Edit %s" % property_name)


func _on_text_focus_exited(line_edit: LineEdit, property_name: StringName) -> void:
	if line_edit != null:
		_on_text_submitted(line_edit.text, property_name)


func _on_notes_focus_exited(notes: TextEdit) -> void:
	if _selected_beat == null or notes == null:
		return
	_commit_property(FIELD_NOTES, notes.text, "Edit notes")


func _commit_line_range(next_range: Vector2i) -> void:
	_commit_property(FIELD_LINE_RANGE, next_range, "Edit dialogue line range")


func _commit_property(
	property_name: StringName,
	new_value: Variant,
	action_name: String
) -> void:
	if _selected_beat == null:
		return
	var old_value: Variant = _selected_beat.get(property_name)
	if old_value == new_value:
		return
	var changes := {
		String(property_name): {
			"before": old_value,
			"after": new_value,
		}
	}
	_commit_resource_changes(_selected_beat, changes, action_name)
	_rebuild()


func _commit_resource_changes(
	target: Object,
	changes: Dictionary,
	action_name: String
) -> void:
	if target == null or changes.is_empty():
		return
	var undo_redo: EditorUndoRedoManager = null
	if _context != null:
		undo_redo = _context.undo_redo
	if undo_redo == null:
		for property_name in changes.keys():
			var change: Dictionary = changes[property_name]
			target.set(property_name, change["after"])
	else:
		undo_redo.create_action(action_name)
		for property_name in changes.keys():
			var change: Dictionary = changes[property_name]
			undo_redo.add_do_property(target, property_name, change["after"])
			undo_redo.add_undo_property(target, property_name, change["before"])
		undo_redo.commit_action()
	if _context != null:
		_context.notify_authored_data_changed()


func _find_control(control_name: String) -> Control:
	if _form == null:
		return null
	return _find_control_recursive(_form, control_name)


func _find_control_recursive(node: Node, control_name: String) -> Control:
	for child in node.get_children():
		if child is Control and child.name == control_name:
			return child as Control
		var nested := _find_control_recursive(child, control_name)
		if nested != null:
			return nested
	return null


func _kind_uses_actor(kind: int) -> bool:
	return kind in [
		CutsceneBeat.Kind.MOVE,
		CutsceneBeat.Kind.POSE,
		CutsceneBeat.Kind.FACE,
		CutsceneBeat.Kind.BOUNCE,
		CutsceneBeat.Kind.PROP,
		CutsceneBeat.Kind.SHOW,
		CutsceneBeat.Kind.HIDE,
	]
