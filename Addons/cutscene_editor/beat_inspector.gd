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
const FIELD_STARTS_FROM_AUTHORED_POINT: StringName = (
	&"starts_from_authored_point"
)
const FIELD_START_MARKER: StringName = &"start_marker"
const FIELD_START_OFFSET: StringName = &"start_offset"
const FIELD_MOVEMENT_WAYPOINTS: StringName = &"movement_waypoints"
const FIELD_POSE: StringName = &"pose"
const FIELD_HOLDS_POSE: StringName = &"holds_pose"
const FIELD_STEP_HEIGHT: StringName = &"step_height"
const FIELD_FACING: StringName = &"facing"
const FIELD_BOUNCE_COUNT: StringName = &"bounce_count"
const FIELD_BOUNCE_OFFSET: StringName = &"bounce_offset"
const FIELD_BOUNCE_STYLE: StringName = &"bounce_style"
const FIELD_CONVERSATION: StringName = &"conversation"
const FIELD_LINE_RANGE: StringName = &"line_range"
const FIELD_CUE: StringName = &"cue"
const FIELD_CAMERA_ACTION: StringName = &"camera_action"
const FIELD_CAMERA_OFFSET: StringName = &"camera_offset"
const FIELD_CAMERA_ZOOM: StringName = &"camera_zoom"
const FIELD_CAMERA_SHAKE_STRENGTH: StringName = &"camera_shake_strength"
const FIELD_AUDIO_ACTION: StringName = &"audio_action"
const FIELD_AUDIO_STREAM: StringName = &"audio_stream"
const FIELD_AUDIO_BUS: StringName = &"audio_bus"
const FIELD_AUDIO_VOLUME_DB: StringName = &"audio_volume_db"
const FIELD_AUDIO_PITCH_SCALE: StringName = &"audio_pitch_scale"
const FIELD_AUDIO_FADE_SECONDS: StringName = &"audio_fade_seconds"
const FIELD_VFX_ACTION: StringName = &"vfx_action"
const FIELD_VFX_ID: StringName = &"vfx_id"
const FIELD_VFX_SCENE: StringName = &"vfx_scene"

## The DialogueDirector's own typewriter settings, mirrored so the editor can
## say how long a line runs without a director in the scene to ask. Keep these
## in step with dialogue_director.gd; they are only used to estimate timing,
## never to drive playback.
## Narrowest this panel may be squeezed to. Wide enough to hold a line of
## dialogue and its speed control side by side.
const _MINIMUM_WIDTH: float = 360.0

const _DEFAULT_CHARACTER_SPEED: float = 0.03
const _SLOWEST_CHARACTERS: Array[String] = ["."]
const _SLOWER_CHARACTERS: Array[String] = [","]

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
			fields.append(str(FIELD_STARTS_FROM_AUTHORED_POINT))
			fields.append(str(FIELD_START_MARKER))
			fields.append(str(FIELD_START_OFFSET))
			fields.append(str(FIELD_TARGET_MARKER))
			fields.append(str(FIELD_TARGET_OFFSET))
			fields.append(str(FIELD_MOVEMENT_WAYPOINTS))
			fields.append(str(FIELD_POSE))
			fields.append(str(FIELD_STEP_HEIGHT))
		CutsceneBeat.Kind.POSE:
			fields.append(str(FIELD_POSE))
			fields.append(str(FIELD_HOLDS_POSE))
		CutsceneBeat.Kind.FACE:
			fields.append(str(FIELD_FACING))
		CutsceneBeat.Kind.BOUNCE:
			fields.append(str(FIELD_BOUNCE_COUNT))
			fields.append(str(FIELD_BOUNCE_OFFSET))
			fields.append(str(FIELD_BOUNCE_STYLE))
		CutsceneBeat.Kind.DIALOGUE:
			fields.append(str(FIELD_CONVERSATION))
			fields.append(str(FIELD_LINE_RANGE))
		CutsceneBeat.Kind.STAGE_CUE, CutsceneBeat.Kind.STRIKE:
			fields.append(str(FIELD_CUE))
		CutsceneBeat.Kind.PROP:
			fields.append(str(FIELD_TARGET_MARKER))
			fields.append(str(FIELD_TARGET_OFFSET))
			fields.append(str(FIELD_MOVEMENT_WAYPOINTS))
		CutsceneBeat.Kind.CAMERA:
			fields.append_array(PackedStringArray([
				str(FIELD_CAMERA_ACTION),
				str(FIELD_CAMERA_OFFSET),
				str(FIELD_CAMERA_ZOOM),
				str(FIELD_CAMERA_SHAKE_STRENGTH),
			]))
		CutsceneBeat.Kind.AUDIO:
			fields.append_array(PackedStringArray([
				str(FIELD_AUDIO_ACTION),
				str(FIELD_AUDIO_STREAM),
				str(FIELD_AUDIO_BUS),
				str(FIELD_AUDIO_VOLUME_DB),
				str(FIELD_AUDIO_PITCH_SCALE),
				str(FIELD_AUDIO_FADE_SECONDS),
			]))
		CutsceneBeat.Kind.VFX:
			fields.append_array(PackedStringArray([
				str(FIELD_VFX_ACTION),
				str(FIELD_VFX_ID),
				str(FIELD_VFX_SCENE),
				str(FIELD_TARGET_MARKER),
				str(FIELD_TARGET_OFFSET),
			]))
		_:
			pass
	return fields


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.free()
	# The panel has to claim width and scroll its own contents. It shares a
	# split with a timeline that demands 900 pixels, so without a minimum it
	# gets squeezed to nothing and the fields are simply not on screen; and the
	# bottom dock is short, so a form taller than it needs somewhere to scroll
	# rather than being clipped with no way to reach the rest.
	custom_minimum_size.x = maxf(custom_minimum_size.x, _MINIMUM_WIDTH)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	var scroll := ScrollContainer.new()
	scroll.name = "BeatFieldsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_form = VBoxContainer.new()
	_form.name = "BeatFields"
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form)
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
	var guidance := Label.new()
	guidance.text = "Timing is changed here or by dragging the beat in the timeline."
	guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guidance.add_theme_color_override(&"font_color", Color("#9aa4b4"))
	guidance.tooltip_text = (
		"Drag a beat to change when it starts, drag its right edge to change "
		+ "duration, and drag between lanes to change its actor. Every field "
		+ "supports Godot undo and redo."
	)
	_form.add_child(guidance)
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
			# Start before target, because a walk reads as "from here to there"
			# and the panel should ask for it in that order.
			_add_check_field(
				"Start from a set point",
				FIELD_STARTS_FROM_AUTHORED_POINT,
				_selected_beat.starts_from_authored_point
			)
			if _selected_beat.starts_from_authored_point:
				_add_start_marker_field()
				_add_vector_field(
					"Start offset",
					FIELD_START_OFFSET,
					_selected_beat.start_offset
				)
			_add_marker_field()
			_add_vector_field("Target offset", FIELD_TARGET_OFFSET, _selected_beat.target_offset)
			_add_waypoint_fields()
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
			_add_check_field(
				"Hold through dialogue",
				FIELD_HOLDS_POSE,
				_selected_beat.holds_pose
			)
		CutsceneBeat.Kind.FACE:
			_add_facing_field()
		CutsceneBeat.Kind.BOUNCE:
			_add_number_field(
				"Bounce count",
				FIELD_BOUNCE_COUNT,
				_selected_beat.bounce_count,
				1.0,
				99.0,
				1.0,
				"How many complete out-and-back motions fit inside this beat."
			)
			_add_vector_field(
				"Peak offset",
				FIELD_BOUNCE_OFFSET,
				_selected_beat.bounce_offset,
				"Visual-only displacement at the peak. Negative Y bobs up; "
				+ "positive Y dips down; X adds a sideways hop."
			)
			_add_bounce_style_field()
		CutsceneBeat.Kind.DIALOGUE:
			_add_conversation_field()
			_add_line_range_field()
		CutsceneBeat.Kind.STAGE_CUE, CutsceneBeat.Kind.STRIKE:
			_add_text_field("Cue", FIELD_CUE, _selected_beat.cue)
		CutsceneBeat.Kind.PROP:
			_add_marker_field()
			_add_vector_field("Target offset", FIELD_TARGET_OFFSET, _selected_beat.target_offset)
			_add_waypoint_fields()
		CutsceneBeat.Kind.CAMERA:
			_add_enum_field(
				"Camera action",
				FIELD_CAMERA_ACTION,
				CutsceneBeat.CameraAction.keys(),
				_selected_beat.camera_action
			)
			_add_vector_field(
				"Frame offset",
				FIELD_CAMERA_OFFSET,
				_selected_beat.camera_offset
			)
			_add_vector_field(
				"Zoom",
				FIELD_CAMERA_ZOOM,
				_selected_beat.camera_zoom
			)
			_add_number_field(
				"Shake strength",
				FIELD_CAMERA_SHAKE_STRENGTH,
				_selected_beat.camera_shake_strength,
				0.0,
				128.0,
				0.1
			)
		CutsceneBeat.Kind.AUDIO:
			_add_enum_field(
				"Audio action",
				FIELD_AUDIO_ACTION,
				CutsceneBeat.AudioAction.keys(),
				_selected_beat.audio_action
			)
			_add_resource_field(
				"Stream",
				FIELD_AUDIO_STREAM,
				"AudioStream",
				_selected_beat.audio_stream
			)
			_add_text_field("Bus", FIELD_AUDIO_BUS, _selected_beat.audio_bus)
			_add_number_field(
				"Volume",
				FIELD_AUDIO_VOLUME_DB,
				_selected_beat.audio_volume_db,
				-80.0,
				24.0,
				0.1
			)
			_add_number_field(
				"Pitch",
				FIELD_AUDIO_PITCH_SCALE,
				_selected_beat.audio_pitch_scale,
				0.01,
				4.0,
				0.01
			)
			_add_number_field(
				"Fade",
				FIELD_AUDIO_FADE_SECONDS,
				_selected_beat.audio_fade_seconds,
				0.0,
				16.0,
				0.05
			)
		CutsceneBeat.Kind.VFX:
			_add_enum_field(
				"VFX action",
				FIELD_VFX_ACTION,
				CutsceneBeat.VfxAction.keys(),
				_selected_beat.vfx_action
			)
			_add_text_field("Effect id", FIELD_VFX_ID, _selected_beat.vfx_id)
			_add_resource_field(
				"Scene",
				FIELD_VFX_SCENE,
				"PackedScene",
				_selected_beat.vfx_scene
			)
			_add_marker_field()
			_add_vector_field(
				"Position offset",
				FIELD_TARGET_OFFSET,
				_selected_beat.target_offset,
				"Stage-local when no marker or actor is selected; otherwise "
				+ "an offset from that target."
			)
		_:
			pass
	_add_notes_field()


func _add_number_field(
	caption: String,
	property_name: StringName,
	current_value: float,
	minimum: float,
	maximum: float,
	step: float,
	help_text: String = ""
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
	spin.tooltip_text = help_text
	row.tooltip_text = help_text
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


## The start's own marker dropdown. Same list as the target's, because a walk
## can start from any point a walk can end at.
func _add_start_marker_field() -> void:
	var row := _make_row("Start marker")
	var option := OptionButton.new()
	option.name = String(FIELD_START_MARKER)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_item("No marker")
	option.set_item_metadata(0, StringName())
	var selected_index := 0
	for marker_name_text in _context.get_marker_names():
		var marker_name := StringName(marker_name_text)
		option.add_item(marker_name_text)
		option.set_item_metadata(option.item_count - 1, marker_name)
		if marker_name == _selected_beat.start_marker:
			selected_index = option.item_count - 1
	if selected_index == 0 and not _selected_beat.start_marker.is_empty():
		option.add_item(str(_selected_beat.start_marker) + " (unknown)")
		option.set_item_metadata(
			option.item_count - 1, _selected_beat.start_marker
		)
		selected_index = option.item_count - 1
	option.select(selected_index)
	row.add_child(option)
	if not option.item_selected.is_connected(_on_start_marker_changed):
		option.item_selected.connect(_on_start_marker_changed)


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
	current_value: Vector2,
	help_text: String = ""
) -> void:
	var row := _make_row(caption)
	var x_spin := SpinBox.new()
	x_spin.name = String(property_name) + "X"
	x_spin.min_value = -10000.0
	x_spin.max_value = 10000.0
	x_spin.step = 1.0
	x_spin.value = current_value.x
	x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	x_spin.tooltip_text = help_text
	row.add_child(x_spin)
	var y_spin := SpinBox.new()
	y_spin.name = String(property_name) + "Y"
	y_spin.min_value = -10000.0
	y_spin.max_value = 10000.0
	y_spin.step = 1.0
	y_spin.value = current_value.y
	y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	y_spin.tooltip_text = help_text
	row.tooltip_text = help_text
	row.add_child(y_spin)
	if not x_spin.value_changed.is_connected(_on_vector_x_changed):
		x_spin.value_changed.connect(_on_vector_x_changed.bind(y_spin, property_name))
	if not y_spin.value_changed.is_connected(_on_vector_y_changed):
		y_spin.value_changed.connect(_on_vector_y_changed.bind(x_spin, property_name))


func _add_waypoint_fields() -> void:
	var heading := Label.new()
	heading.text = "Path waypoints"
	heading.tooltip_text = (
		"Optional stage-local points visited in order. Empty makes a straight "
		+ "path. Drag waypoint handles in the 2D view for faster staging."
	)
	_form.add_child(heading)
	for index in range(_selected_beat.movement_waypoints.size()):
		var point := _selected_beat.movement_waypoints[index]
		var row := HBoxContainer.new()
		row.name = "%s%d" % [FIELD_MOVEMENT_WAYPOINTS, index]
		var index_label := Label.new()
		index_label.text = "%d" % (index + 1)
		index_label.custom_minimum_size.x = 24.0
		row.add_child(index_label)
		var x_spin := SpinBox.new()
		x_spin.min_value = -10000.0
		x_spin.max_value = 10000.0
		x_spin.step = 1.0
		x_spin.value = point.x
		x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		x_spin.value_changed.connect(
			_on_waypoint_component_changed.bind(index, true)
		)
		row.add_child(x_spin)
		var y_spin := SpinBox.new()
		y_spin.min_value = -10000.0
		y_spin.max_value = 10000.0
		y_spin.step = 1.0
		y_spin.value = point.y
		y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		y_spin.value_changed.connect(
			_on_waypoint_component_changed.bind(index, false)
		)
		row.add_child(y_spin)
		var remove_button := Button.new()
		remove_button.text = "×"
		remove_button.tooltip_text = "Remove this waypoint."
		remove_button.pressed.connect(_on_remove_waypoint.bind(index))
		row.add_child(remove_button)
		_form.add_child(row)
	var add_button := Button.new()
	add_button.text = "+ Waypoint"
	add_button.tooltip_text = (
		"Add a stage-local path point before the destination. You can then "
		+ "drag it in the 2D viewport."
	)
	add_button.pressed.connect(_on_add_waypoint)
	_form.add_child(add_button)


func _add_enum_field(
	caption: String,
	property_name: StringName,
	names: Array,
	current_value: int
) -> void:
	var row := _make_row(caption)
	var option := OptionButton.new()
	option.name = String(property_name)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in range(names.size()):
		option.add_item(str(names[index]).capitalize())
		option.set_item_metadata(index, index)
	option.select(clampi(current_value, 0, maxi(names.size() - 1, 0)))
	option.item_selected.connect(
		_on_enum_changed.bind(option, property_name)
	)
	row.add_child(option)


func _add_resource_field(
	caption: String,
	property_name: StringName,
	base_type: String,
	current_resource: Resource
) -> void:
	var row := _make_row(caption)
	var picker := EditorResourcePicker.new()
	picker.name = String(property_name)
	picker.base_type = base_type
	picker.edited_resource = current_resource
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.resource_changed.connect(
		_on_resource_changed.bind(property_name)
	)
	row.add_child(picker)


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


func _add_bounce_style_field() -> void:
	var row := _make_row("Motion")
	var option := OptionButton.new()
	option.name = String(FIELD_BOUNCE_STYLE)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_item("Gentle")
	option.set_item_metadata(0, CutsceneBeat.BounceStyle.GENTLE)
	option.add_item("Snappy")
	option.set_item_metadata(1, CutsceneBeat.BounceStyle.SNAPPY)
	option.add_item("Linear")
	option.set_item_metadata(2, CutsceneBeat.BounceStyle.LINEAR)
	for index in range(option.item_count):
		if int(option.get_item_metadata(index)) == _selected_beat.bounce_style:
			option.select(index)
			break
	option.tooltip_text = (
		"Gentle eases into the peak, Snappy reaches it quickly, and Linear "
		+ "moves at an even rate. Duration and bounce count stay unchanged."
	)
	row.tooltip_text = option.tooltip_text
	row.add_child(option)
	option.item_selected.connect(_on_bounce_style_changed.bind(option))


func _add_conversation_field() -> void:
	var row := _make_row("Conversation")
	var option := OptionButton.new()
	option.name = String(FIELD_CONVERSATION)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.tooltip_text = (
		"Choose which authored conversation this beat presents. The line range "
		+ "below decides which part runs at this point in the timeline."
	)
	option.add_item("(none assigned)")
	option.set_item_metadata(0, null)
	var conversations: Array[DialogueConversation] = []
	if (
		_context.encounter != null
		and _context.encounter.conversation != null
	):
		conversations.append(_context.encounter.conversation)
	if _context.sequence != null:
		for beat in _context.sequence.beats:
			if (
				beat != null
				and beat.conversation != null
				and not conversations.has(beat.conversation)
			):
				conversations.append(beat.conversation)
	var selected_index := 0
	for conversation in conversations:
		option.add_item(str(conversation.conversation_id))
		option.set_item_metadata(option.item_count - 1, conversation)
		if conversation == _selected_beat.conversation:
			selected_index = option.item_count - 1
	option.select(selected_index)
	row.add_child(option)
	option.item_selected.connect(_on_conversation_changed.bind(option))


func _add_line_range_field() -> void:
	var label := Label.new()
	label.text = "Line range"
	label.tooltip_text = (
		"Choose the inclusive first and last lines presented at this point in "
		+ "the timeline."
	)
	_form.add_child(label)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_child(row)
	var start_option := _make_line_option(true)
	var end_option := _make_line_option(false)
	var start_group := VBoxContainer.new()
	start_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var start_label := Label.new()
	start_label.text = "From"
	start_label.add_theme_color_override(&"font_color", Color("#9aa4b4"))
	start_group.add_child(start_label)
	start_group.add_child(start_option)
	row.add_child(start_group)
	var end_group := VBoxContainer.new()
	end_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var end_label := Label.new()
	end_label.text = "Through"
	end_label.add_theme_color_override(&"font_color", Color("#9aa4b4"))
	end_group.add_child(end_label)
	end_group.add_child(end_option)
	row.add_child(end_group)
	if not start_option.item_selected.is_connected(_on_line_start_changed):
		start_option.item_selected.connect(_on_line_start_changed.bind(end_option))
	if not end_option.item_selected.is_connected(_on_line_end_changed):
		end_option.item_selected.connect(_on_line_end_changed.bind(start_option))
	if _selected_beat.conversation == null:
		start_option.disabled = true
		end_option.disabled = true
	_add_dialogue_script()


## Writes the beat's dialogue out line by line, editable in place, with the pace
## each line is typed at and how long that takes.
##
## A DIALOGUE beat used to be a conversation id and two index dropdowns, so the
## only way to read the words was to open the conversation resource in a second
## Inspector and count. The lines are the content of the shot; writing them is
## the work, so they belong on the beat.
func _add_dialogue_script() -> void:
	if _selected_beat.conversation == null:
		return
	var lines := _selected_beat.conversation.lines
	var first := _selected_beat.line_range.x
	var last := _selected_beat.line_range.y
	if first < 0:
		first = 0
	if last < 0 or last >= lines.size():
		last = lines.size() - 1
	if first > last:
		return

	var total_seconds := 0.0
	for line_index in range(first, last + 1):
		var line: DialogueLine = lines[line_index]
		if line == null:
			continue
		total_seconds += _typing_seconds_for(line)
		total_seconds += maxf(line.auto_advance_delay_seconds, 0.0)

	var heading := Label.new()
	heading.text = "Dialogue  (%d line%s, about %.1fs typed)" % [
		last - first + 1,
		"" if last == first else "s",
		total_seconds,
	]
	heading.add_theme_font_size_override("font_size", 14)
	_form.add_child(heading)

	var fit_button := Button.new()
	fit_button.text = "Fit beat length to the dialogue"
	fit_button.tooltip_text = (
		"Sets this beat's duration to how long these lines take to type out, "
		+ "including their auto-advance waits. A beat shorter than its words "
		+ "runs the next beat over the top of them."
	)
	fit_button.pressed.connect(
		_on_fit_beat_to_dialogue_pressed.bind(total_seconds)
	)
	_form.add_child(fit_button)

	for line_index in range(first, last + 1):
		var line: DialogueLine = lines[line_index]
		if line == null:
			continue
		_add_dialogue_line_row(line_index, line)


## Returns how long one line takes to type, asking the line itself when it can
## answer and counting the characters here when it cannot.
##
## The fallback is not decoration. A resource whose script is not @tool loads in
## the editor with its values readable but its methods missing, and calling one
## aborts the panel mid-build - which is exactly how this section came to render
## nothing at all while every field around it looked fine. Degrading to a local
## count keeps the words editable even when the timing estimate is the thing
## that breaks.
func _typing_seconds_for(line: DialogueLine) -> float:
	if line == null:
		return 0.0
	if line.has_method(&"get_typing_seconds"):
		return line.get_typing_seconds(
			_DEFAULT_CHARACTER_SPEED,
			_SLOWEST_CHARACTERS,
			_SLOWER_CHARACTERS
		)
	var speed := _DEFAULT_CHARACTER_SPEED
	var override_value: Variant = line.get("character_display_speed_override")
	if override_value is float and float(override_value) > 0.0:
		speed = float(override_value)
	var total := 0.0
	for index in range(line.text.length()):
		var letter := line.text[index]
		if _SLOWEST_CHARACTERS.has(letter):
			total += speed * 5.0
		elif _SLOWER_CHARACTERS.has(letter):
			total += speed * 3.0
		else:
			total += speed
	return total


## One line: who says it, what they say, and how fast it types.
func _add_dialogue_line_row(line_index: int, line: DialogueLine) -> void:
	var speaker := str(line.speaker_slot)
	if speaker.is_empty():
		speaker = "(no speaker)"
	var seconds := _typing_seconds_for(line)
	var caption := Label.new()
	caption.text = "%d  %s  -  %.1fs" % [line_index, speaker, seconds]
	caption.add_theme_color_override(&"font_color", Color("#9aa4b4"))
	_form.add_child(caption)

	var delivery_row := GridContainer.new()
	delivery_row.columns = 4
	delivery_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var speaker_label := Label.new()
	speaker_label.text = "Speaker"
	delivery_row.add_child(speaker_label)
	var speaker_option := OptionButton.new()
	speaker_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for participant in _selected_beat.conversation.participants:
		if participant == null:
			continue
		speaker_option.add_item(participant.display_name)
		speaker_option.set_item_metadata(
			speaker_option.item_count - 1,
			participant.slot
		)
		if participant.slot == line.speaker_slot:
			speaker_option.select(speaker_option.item_count - 1)
	speaker_option.tooltip_text = (
		"Who delivers this line. The runtime uses the stable speaker slot to "
		+ "pick the actor and display name."
	)
	speaker_option.item_selected.connect(
		_on_dialogue_speaker_changed.bind(line, speaker_option)
	)
	delivery_row.add_child(speaker_option)

	var auto_label := Label.new()
	auto_label.text = "Auto"
	delivery_row.add_child(auto_label)
	var auto_spin := SpinBox.new()
	auto_spin.min_value = 0.0
	auto_spin.max_value = 30.0
	auto_spin.step = 0.1
	auto_spin.suffix = " s"
	auto_spin.value = line.auto_advance_delay_seconds
	auto_spin.tooltip_text = (
		"Zero waits for player input. A positive value advances this line "
		+ "automatically after that many seconds."
	)
	auto_spin.value_changed.connect(
		_on_dialogue_auto_advance_changed.bind(line)
	)
	delivery_row.add_child(auto_spin)
	_form.add_child(delivery_row)

	var text_edit := TextEdit.new()
	text_edit.text = line.text
	text_edit.custom_minimum_size = Vector2(0.0, 54.0)
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_child(text_edit)
	text_edit.focus_exited.connect(
		_on_dialogue_text_committed.bind(line, text_edit)
	)

	var speed_row := HBoxContainer.new()
	var speed_label := Label.new()
	speed_label.text = "Typing speed"
	speed_label.custom_minimum_size.x = 110.0
	speed_row.add_child(speed_label)
	var speed_spin := SpinBox.new()
	speed_spin.min_value = 0.0
	speed_spin.max_value = 0.2
	speed_spin.step = 0.001
	speed_spin.value = line.character_display_speed_override
	speed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_spin.tooltip_text = (
		"Seconds per character for this line. Zero uses the game's own speed, "
		+ "currently %.3f. Larger is slower." % _DEFAULT_CHARACTER_SPEED
	)
	speed_spin.value_changed.connect(
		_on_dialogue_speed_changed.bind(line)
	)
	speed_row.add_child(speed_spin)
	_form.add_child(speed_row)

	var cue_row := GridContainer.new()
	cue_row.columns = 4
	cue_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pose_label := Label.new()
	pose_label.text = "Pose"
	cue_row.add_child(pose_label)
	var pose_edit := LineEdit.new()
	pose_edit.text = str(line.speaker_pose)
	pose_edit.placeholder_text = "optional speaker pose"
	pose_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pose_edit.tooltip_text = (
		"Optional pose applied to this line's speaker while the line is shown."
	)
	pose_edit.focus_exited.connect(
		_on_dialogue_name_committed.bind(
			line,
			pose_edit,
			&"speaker_pose",
			"Edit dialogue speaker pose"
		)
	)
	cue_row.add_child(pose_edit)
	var cue_label := Label.new()
	cue_label.text = "Cue"
	cue_row.add_child(cue_label)
	var cue_edit := LineEdit.new()
	cue_edit.text = str(line.stage_cue)
	cue_edit.placeholder_text = "optional stage animation"
	cue_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cue_edit.tooltip_text = (
		"Optional AnimationPlayer clip started when this exact line appears."
	)
	cue_edit.focus_exited.connect(
		_on_dialogue_name_committed.bind(
			line,
			cue_edit,
			&"stage_cue",
			"Edit dialogue stage cue"
		)
	)
	cue_row.add_child(cue_edit)
	_form.add_child(cue_row)


func _on_fit_beat_to_dialogue_pressed(total_seconds: float) -> void:
	if _selected_beat == null:
		return
	_commit_property(
		FIELD_DURATION_SECONDS,
		snappedf(total_seconds, 0.1),
		"Fit beat to dialogue"
	)


## Commits an edited line on focus loss rather than per keystroke, so one undo
## entry covers one rewrite instead of one per letter.
func _on_dialogue_text_committed(line: DialogueLine, editor: TextEdit) -> void:
	if line == null or not is_instance_valid(editor):
		return
	if line.text == editor.text:
		return
	_commit_resource_changes(
		line,
		{"text": {"before": line.text, "after": editor.text}},
		"Edit dialogue line"
	)
	_rebuild()


func _on_dialogue_speed_changed(value: float, line: DialogueLine) -> void:
	if line == null or is_equal_approx(line.character_display_speed_override, value):
		return
	_commit_resource_changes(
		line,
		{
			"character_display_speed_override": {
				"before": line.character_display_speed_override,
				"after": value,
			}
		},
		"Edit dialogue typing speed"
	)
	_rebuild()


func _on_dialogue_speaker_changed(
	index: int,
	line: DialogueLine,
	option: OptionButton
) -> void:
	if line == null or option == null or index < 0:
		return
	var speaker_slot := StringName(option.get_item_metadata(index))
	if line.speaker_slot == speaker_slot:
		return
	_commit_resource_changes(
		line,
		{
			"speaker_slot": {
				"before": line.speaker_slot,
				"after": speaker_slot,
			}
		},
		"Edit dialogue speaker"
	)
	_rebuild()


func _on_dialogue_auto_advance_changed(
	value: float,
	line: DialogueLine
) -> void:
	if (
		line == null
		or is_equal_approx(line.auto_advance_delay_seconds, value)
	):
		return
	_commit_resource_changes(
		line,
		{
			"auto_advance_delay_seconds": {
				"before": line.auto_advance_delay_seconds,
				"after": maxf(value, 0.0),
			}
		},
		"Edit dialogue auto advance"
	)
	_rebuild()


func _on_dialogue_name_committed(
	line: DialogueLine,
	editor: LineEdit,
	property_name: StringName,
	action_name: String
) -> void:
	if line == null or editor == null:
		return
	var before := StringName(line.get(property_name))
	var after := StringName(editor.text.strip_edges())
	if before == after:
		return
	_commit_resource_changes(
		line,
		{
			String(property_name): {
				"before": before,
				"after": after,
			}
		},
		action_name
	)
	_rebuild()


func _make_line_option(is_start: bool) -> OptionButton:
	var option := OptionButton.new()
	option.name = "LineStart" if is_start else "LineEnd"
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The menu intentionally includes the full dialogue text, but that text must
	# not become the control's minimum width. Otherwise selecting a dialogue
	# beat makes two long dropdowns expand the inspector and crush the timeline.
	option.fit_to_longest_item = false
	option.tooltip_text = (
		"First dialogue line played by this beat."
		if is_start
		else "Last dialogue line played by this beat."
	)
	option.add_item("First line" if is_start else "Last line")
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


func _on_start_marker_changed(index: int) -> void:
	if _selected_beat == null:
		return
	var option := _find_control(String(FIELD_START_MARKER)) as OptionButton
	if option == null or index < 0:
		return
	_commit_property(
		FIELD_START_MARKER,
		option.get_item_metadata(index),
		"Edit start marker"
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


func _on_waypoint_component_changed(
	value: float,
	waypoint_index: int,
	is_x: bool
) -> void:
	if (
		_selected_beat == null
		or waypoint_index < 0
		or waypoint_index >= _selected_beat.movement_waypoints.size()
	):
		return
	var waypoints: Array[Vector2] = _selected_beat.movement_waypoints.duplicate()
	var point := waypoints[waypoint_index]
	if is_x:
		point.x = value
	else:
		point.y = value
	waypoints[waypoint_index] = point
	_commit_property(
		FIELD_MOVEMENT_WAYPOINTS,
		waypoints,
		"Move cutscene waypoint"
	)


func _on_add_waypoint() -> void:
	if _selected_beat == null:
		return
	var waypoints: Array[Vector2] = _selected_beat.movement_waypoints.duplicate()
	var start := _selected_beat.start_offset
	if not waypoints.is_empty():
		start = waypoints.back()
	waypoints.append(start.lerp(_selected_beat.target_offset, 0.5))
	_commit_property(
		FIELD_MOVEMENT_WAYPOINTS,
		waypoints,
		"Add cutscene waypoint"
	)


func _on_remove_waypoint(waypoint_index: int) -> void:
	if (
		_selected_beat == null
		or waypoint_index < 0
		or waypoint_index >= _selected_beat.movement_waypoints.size()
	):
		return
	var waypoints: Array[Vector2] = _selected_beat.movement_waypoints.duplicate()
	waypoints.remove_at(waypoint_index)
	_commit_property(
		FIELD_MOVEMENT_WAYPOINTS,
		waypoints,
		"Remove cutscene waypoint"
	)


func _on_enum_changed(
	index: int,
	option: OptionButton,
	property_name: StringName
) -> void:
	if _selected_beat == null or option == null or index < 0:
		return
	_commit_property(
		property_name,
		int(option.get_item_metadata(index)),
		"Edit %s" % property_name
	)


func _on_resource_changed(
	resource: Resource,
	property_name: StringName
) -> void:
	_commit_property(
		property_name,
		resource,
		"Edit %s" % property_name
	)


func _on_facing_changed(index: int) -> void:
	if _selected_beat == null:
		return
	var option := _find_control(String(FIELD_FACING)) as OptionButton
	if option != null:
		_commit_property(FIELD_FACING, int(option.get_item_metadata(index)), "Edit facing")


func _on_bounce_style_changed(index: int, option: OptionButton) -> void:
	if _selected_beat == null or option == null or index < 0:
		return
	_commit_property(
		FIELD_BOUNCE_STYLE,
		int(option.get_item_metadata(index)),
		"Edit bounce motion"
	)


func _on_conversation_changed(index: int, option: OptionButton) -> void:
	if _selected_beat == null or option == null or index < 0:
		return
	_commit_property(
		FIELD_CONVERSATION,
		option.get_item_metadata(index),
		"Edit dialogue conversation"
	)


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
		CutsceneBeat.Kind.VFX,
	]
