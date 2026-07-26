@tool
class_name CutsceneTimelinePanel
extends VBoxContainer

## How it works:
## - The panel builds the toolbar, scrollable ruler, actor lanes, and validation list.
## - A small inner canvas draws beats and forwards mouse gestures to the panel.
## - Drag values stay as preview state until release, then one UndoRedo action commits them.
## - Scrubbing evaluates the sequence and applies the resulting presentation to actor previews.
## - The invariant is that authored beat resources change only through one committed gesture.

signal scrub_time_changed(seconds: float)
signal beat_selected(beat: CutsceneBeat)
signal beat_selection_changed(beats: Array[CutsceneBeat])

const RULER_HEIGHT: float = 34.0
const LANE_LABEL_WIDTH: float = 140.0
const LANE_HEIGHT: float = 58.0
const MIN_BEAT_WIDTH: float = 20.0
const EDGE_HOT_ZONE: float = 7.0
const MIN_PIXELS_PER_SECOND: float = 20.0
const MAX_PIXELS_PER_SECOND: float = 240.0
const DEFAULT_PIXELS_PER_SECOND: float = 80.0
const DEFAULT_GRID_SECONDS: float = 0.1
## How near, in screen pixels, a dragged edge has to come to another beat's edge
## before it snaps onto it.
const _NEIGHBOUR_SNAP_PIXELS: float = 8.0

enum TemplateKind {
	ENTRANCE,
	CONVERSATION,
	REACTION,
	MINING_STRIKE,
	EXIT,
	FULL_EXCHANGE,
}

const KIND_COLORS: Dictionary = {
	CutsceneBeat.Kind.MOVE: Color("#4b91d1"),
	CutsceneBeat.Kind.POSE: Color("#9d70cf"),
	CutsceneBeat.Kind.FACE: Color("#ca8c43"),
	CutsceneBeat.Kind.BOUNCE: Color("#d56b90"),
	CutsceneBeat.Kind.WAIT: Color("#68758a"),
	CutsceneBeat.Kind.DIALOGUE: Color("#47a88e"),
	CutsceneBeat.Kind.STAGE_CUE: Color("#b36aab"),
	CutsceneBeat.Kind.PROP: Color("#5f9fba"),
	CutsceneBeat.Kind.STRIKE: Color("#d45d57"),
	CutsceneBeat.Kind.SHOW: Color("#73aa61"),
	CutsceneBeat.Kind.HIDE: Color("#755f70"),
	CutsceneBeat.Kind.CAMERA: Color("#d0a64f"),
	CutsceneBeat.Kind.AUDIO: Color("#52a9ca"),
	CutsceneBeat.Kind.VFX: Color("#c466df"),
}

class _TimelineCanvas extends Control:
	var _draw_handler: Callable
	var _input_handler: Callable
	var _cursor_handler: Callable
	var _capturing: bool = false

	func configure(
		draw_handler: Callable,
		input_handler: Callable,
		cursor_handler: Callable
	) -> void:
		_draw_handler = draw_handler
		_input_handler = input_handler
		_cursor_handler = cursor_handler
		mouse_filter = Control.MOUSE_FILTER_STOP
		# Click to focus, so the timeline's keys are live while you are working
		# in it and dormant everywhere else. A panel that answered Delete
		# whatever had focus would eat the Scene dock's own Delete.
		focus_mode = Control.FOCUS_CLICK
		set_process_input(true)

	func _draw() -> void:
		if _draw_handler.is_valid():
			_draw_handler.call(self)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var motion := event as InputEventMouseMotion
			_update_cursor(motion.position)
			return
		var key := event as InputEventKey
		if key != null:
			if not key.pressed or key.echo:
				return
			if _input_handler.is_valid() and bool(
				_input_handler.call(&"key", Vector2.ZERO, key)
			):
				accept_event()
			return
		if not event is InputEventMouseButton:
			return
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
			return
		if _input_handler.is_valid():
			var accepted: Variant = _input_handler.call(
				&"press",
				button.position,
				button
			)
			_capturing = bool(accepted)
			if _capturing:
				get_viewport().set_input_as_handled()

	func _input(event: InputEvent) -> void:
		if not _capturing or not _input_handler.is_valid():
			return
		if event is InputEventMouseMotion:
			var motion := event as InputEventMouseMotion
			_input_handler.call(&"motion", get_local_mouse_position(), motion)
			get_viewport().set_input_as_handled()
			return
		if not event is InputEventMouseButton:
			return
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT or button.pressed:
			return
		_input_handler.call(
			&"release",
			get_local_mouse_position(),
			button
		)
		_capturing = false
		get_viewport().set_input_as_handled()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			mouse_default_cursor_shape = Control.CURSOR_ARROW

	func _update_cursor(position: Vector2) -> void:
		if _cursor_handler.is_valid():
			mouse_default_cursor_shape = int(_cursor_handler.call(position))


var _context: CutsceneEditorContext
var _canvas: _TimelineCanvas
var _toolbar: HFlowContainer
var _status_bar: HBoxContainer
var _playhead_readout: Label
var _legend: HBoxContainer
var _kind_option: OptionButton
var _actor_option: OptionButton
var _zoom_spin: SpinBox
var _grid_spin: SpinBox
var _play_button: Button
var _loop_button: CheckButton
var _lane_lock_button: CheckButton
var _lane_mute_button: CheckButton
var _lane_solo_button: CheckButton
var _time_label: Label
var _duration_label: Label
var _validation_list: ItemList
var _empty_message: Label

var _lane_actor_ids: PackedStringArray = PackedStringArray()
var _invalid_beat_indices: Dictionary = {}
var _selected_beat: CutsceneBeat
var _selected_beats: Array[CutsceneBeat] = []
var _selected_kind: int = CutsceneBeat.Kind.MOVE
var _pixels_per_second: float = DEFAULT_PIXELS_PER_SECOND
var _grid_seconds: float = DEFAULT_GRID_SECONDS
var _scrub_time: float = 0.0
var _is_playing: bool = false
var _loop_enabled: bool = false
var _loop_start_seconds: float = 0.0
var _loop_end_seconds: float = 0.0
var _locked_lanes: Dictionary = {}
var _muted_lanes: Dictionary = {}
var _solo_lanes: Dictionary = {}

var _drag_mode: StringName = &""
var _drag_beat: CutsceneBeat
var _drag_original_start: float = 0.0
var _drag_original_duration: float = 0.0
var _drag_original_actor: StringName
var _drag_pointer_offset_seconds: float = 0.0
var _drag_preview_start: float = 0.0
var _drag_preview_duration: float = 0.0
var _drag_preview_actor: StringName
var _drag_group_original_starts: Dictionary = {}
var _drag_group_preview_starts: Dictionary = {}

var _preview_player: CutsceneSequencePlayer
var _preview_base_states: Dictionary = {}
## The position this panel last wrote for each actor, so a later restore can
## distinguish its own work from a node the designer moved by hand.
var _preview_applied_states: Dictionary = {}

## Editor-session clipboard deliberately stores duplicated beat resources rather
## than serializing text. It survives switching scenes while Godot is open but
## never dirties a game resource until Paste is explicitly requested.
static var _beat_clipboard: Array[CutsceneBeat] = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if _context == null:
		_show_empty_state()


func _process(delta: float) -> void:
	if not _is_playing:
		return
	if not _has_valid_context():
		_set_playing(false)
		return
	var duration := _sequence_duration()
	if duration <= 0.0:
		_set_scrub_time(0.0, true)
		_set_playing(false)
		return
	var playback_end := duration
	if _has_loop_range():
		playback_end = _loop_end_seconds
	var next_time := minf(_scrub_time + maxf(delta, 0.0), playback_end)
	_set_scrub_time(next_time, true)
	if is_equal_approx(next_time, playback_end) and _has_loop_range():
		_set_scrub_time(_loop_start_seconds, true)
	elif is_equal_approx(next_time, duration):
		_set_playing(false)


## Rebuilds the panel for the supplied scene context.
func set_context(context: CutsceneEditorContext) -> void:
	_restore_preview_states()
	_stop_drag_without_commit()
	if _context != null and _context.authored_data_changed.is_connected(
		_on_context_data_changed
	):
		_context.authored_data_changed.disconnect(_on_context_data_changed)
	# The timeline draws one lane per cast member, so a cast edit has to reach
	# it too - just without the terrain rebuild authored_data_changed carries.
	if _context != null and _context.cast_changed.is_connected(
		_on_context_data_changed
	):
		_context.cast_changed.disconnect(_on_context_data_changed)
	if _context != null:
		if _context.movement_start_position_requested.is_connected(
			_on_movement_start_position_requested
		):
			_context.movement_start_position_requested.disconnect(
				_on_movement_start_position_requested
			)
		if _context.movement_destination_position_requested.is_connected(
			_on_movement_destination_position_requested
		):
			_context.movement_destination_position_requested.disconnect(
				_on_movement_destination_position_requested
			)
		if _context.movement_beat_creation_requested.is_connected(
			_on_movement_beat_creation_requested
		):
			_context.movement_beat_creation_requested.disconnect(
				_on_movement_beat_creation_requested
			)
		if _context.stage_positions_will_change.is_connected(
			_prepare_for_stage_position_change
		):
			_context.stage_positions_will_change.disconnect(
				_prepare_for_stage_position_change
			)
	_context = context
	_selected_beat = null
	_selected_beats.clear()
	_scrub_time = 0.0
	_loop_start_seconds = 0.0
	_loop_end_seconds = 0.0
	_set_playing(false)
	_preview_base_states.clear()
	_preview_applied_states.clear()
	if not _has_valid_context():
		_show_empty_state()
		return
	if not _context.authored_data_changed.is_connected(_on_context_data_changed):
		_context.authored_data_changed.connect(_on_context_data_changed)
	if not _context.cast_changed.is_connected(_on_context_data_changed):
		_context.cast_changed.connect(_on_context_data_changed)
	_context.movement_start_position_requested.connect(
		_on_movement_start_position_requested
	)
	_context.movement_destination_position_requested.connect(
		_on_movement_destination_position_requested
	)
	_context.movement_beat_creation_requested.connect(
		_on_movement_beat_creation_requested
	)
	_context.stage_positions_will_change.connect(
		_prepare_for_stage_position_change
	)
	_build_valid_panel()


func _on_movement_start_position_requested(
	actor_id: StringName,
	stage_position: Vector2
) -> void:
	var beat := _selected_move_for_actor(actor_id)
	if beat == null:
		return
	_commit_resource_changes(
		beat,
		{
			&"starts_from_authored_point": {
				"before": beat.starts_from_authored_point,
				"after": true,
			},
			&"start_marker": {
				"before": beat.start_marker,
				"after": StringName(),
			},
			&"start_offset": {
				"before": beat.start_offset,
				"after": stage_position,
			},
		},
		"Record cutscene movement start"
	)


func _on_movement_destination_position_requested(
	actor_id: StringName,
	stage_position: Vector2
) -> void:
	var beat := _selected_move_for_actor(actor_id)
	if beat == null:
		return
	_commit_resource_changes(
		beat,
		{
			&"target_marker": {
				"before": beat.target_marker,
				"after": StringName(),
			},
			&"target_offset": {
				"before": beat.target_offset,
				"after": stage_position,
			},
		},
		"Record cutscene movement destination"
	)


func _on_movement_beat_creation_requested(
	actor_id: StringName,
	stage_position: Vector2
) -> void:
	if not _has_valid_context():
		return
	var beat := CutsceneBeat.new()
	beat.kind = CutsceneBeat.Kind.MOVE
	beat.actor = actor_id
	beat.start_seconds = snap_time(_scrub_time)
	beat.duration_seconds = 1.0
	beat.target_offset = stage_position
	_append_new_beats([beat], "Create staged movement beat")


func _selected_move_for_actor(actor_id: StringName) -> CutsceneBeat:
	if (
		_selected_beat != null
		and _selected_beat.kind == CutsceneBeat.Kind.MOVE
		and _selected_beat.actor == actor_id
	):
		return _selected_beat
	for selected in _selected_beats:
		if (
			selected != null
			and selected.kind == CutsceneBeat.Kind.MOVE
			and selected.actor == actor_id
		):
			return selected
	return null


## Converts authored seconds to the horizontal timeline coordinate.
func time_to_pixels(seconds: float, zoom: float = -1.0) -> float:
	var pixels_per_second := _resolved_zoom(zoom)
	return maxf(seconds, 0.0) * pixels_per_second


## Converts a horizontal timeline coordinate back to non-negative seconds.
func pixels_to_time(pixels: float, zoom: float = -1.0) -> float:
	var pixels_per_second := _resolved_zoom(zoom)
	return maxf(pixels, 0.0) / pixels_per_second


## Snaps a time to the configured grid unless a modifier bypasses snapping.
func snap_time(seconds: float, grid: float = -1.0, bypass_grid: bool = false) -> float:
	var non_negative := maxf(seconds, 0.0)
	var resolved_grid := _grid_seconds if grid < 0.0 else grid
	if bypass_grid or resolved_grid <= 0.0:
		return non_negative
	return maxf(roundf(non_negative / resolved_grid) * resolved_grid, 0.0)


## Clamps a right-edge drag so resizing can never invert a beat.
func clamp_duration_after_resize(
	start_seconds: float,
	right_edge_seconds: float
) -> float:
	return maxf(right_edge_seconds - maxf(start_seconds, 0.0), 0.0)


## Applies only the actor change used by a lane move; other beat fields stay intact.
func move_beat_to_lane(beat: CutsceneBeat, actor_id: StringName) -> void:
	if beat != null:
		beat.actor = actor_id


func _has_valid_context() -> bool:
	return (
		_context != null
		and _context.is_valid()
		and _context.sequence != null
	)


func _show_empty_state() -> void:
	_clear_children()
	_empty_message = Label.new()
	_empty_message.text = "Open a cutscene stage to edit its timeline."
	_empty_message.add_theme_color_override(
		&"font_color",
		Color("#a9b0bd")
	)
	_empty_message.custom_minimum_size = Vector2(0.0, 42.0)
	_empty_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_empty_message)
	set_process(false)


func _build_valid_panel() -> void:
	_clear_children()
	_build_toolbar()
	_build_status_bar()
	_canvas = _TimelineCanvas.new()
	_canvas.configure(
		Callable(self, "_draw_timeline"),
		Callable(self, "_handle_canvas_input"),
		Callable(self, "_cursor_for_position")
	)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size = Vector2(900.0, 180.0)
	# Hovering the thing you are about to use is where a person looks for its
	# keys, so the timeline's bindings are written on the timeline itself
	# rather than only in a manual nobody opens.
	_canvas.tooltip_text = (
		"Drag a beat to move it, drag its edge to change how long it lasts, "
		+ "and drag it onto another lane to hand it to a different character. "
		+ "Drag the ruler to scrub.\n"
		+ "\n"
		+ "Click the timeline first, then:\n"
		+ "  Space  play or pause\n"
		+ "  Left and Right  step the playhead by one grid division\n"
		+ "  Shift+arrows  step ten divisions\n"
		+ "  Ctrl+arrows  move the selected beat instead of the playhead\n"
		+ "  Home and End  jump to the start or the end\n"
		+ "  Shift-click  select several beats\n"
		+ "  Ctrl+A/C/V/D  select all, copy, paste, or duplicate\n"
		+ "  I and O  set loop in/out; L toggles looping\n"
		+ "  Delete  remove the selected beat"
	)
	var scroll := ScrollContainer.new()
	scroll.name = "TimelineScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, 190.0)
	scroll.add_child(_canvas)
	add_child(scroll)
	_validation_list = ItemList.new()
	_validation_list.name = "ValidationMessages"
	_validation_list.select_mode = ItemList.SELECT_SINGLE
	_validation_list.mouse_filter = Control.MOUSE_FILTER_STOP
	_validation_list.tooltip_text = (
		"Select an error to focus the beat that needs attention."
	)
	_validation_list.custom_minimum_size = Vector2(0.0, 64.0)
	_validation_list.item_selected.connect(_on_validation_selected)
	add_child(_validation_list)
	_rebuild_lane_data()
	_capture_preview_states()
	_refresh_validation()
	_update_timeline_size()
	_update_toolbar_readout()
	_update_playhead_readout()
	set_process(true)


func _build_toolbar() -> void:
	_toolbar = HFlowContainer.new()
	_toolbar.name = "TimelineToolbar"
	_toolbar.custom_minimum_size = Vector2(0.0, 34.0)
	_toolbar.add_theme_constant_override(&"h_separation", 6)
	_toolbar.add_theme_constant_override(&"v_separation", 4)
	add_child(_toolbar)

	var add_label := Label.new()
	add_label.text = "Add"
	_toolbar.add_child(add_label)
	_kind_option = OptionButton.new()
	_kind_option.name = "BeatKind"
	_kind_option.custom_minimum_size = Vector2(112.0, 0.0)
	_kind_option.tooltip_text = "Choose the action the next + Beat button will add."
	for kind in range(CutsceneBeat.Kind.size()):
		_kind_option.add_item(_kind_name(kind))
	_toolbar.add_child(_kind_option)
	if not _kind_option.item_selected.is_connected(_on_kind_selected):
		_kind_option.item_selected.connect(_on_kind_selected)

	_actor_option = OptionButton.new()
	_actor_option.name = "BeatActor"
	_actor_option.custom_minimum_size = Vector2(130.0, 0.0)
	_actor_option.tooltip_text = (
		"Choose the cast lane for the next actor-owned beat. Shared beats do "
		+ "not target a character."
	)
	_populate_actor_option()
	_toolbar.add_child(_actor_option)
	if not _actor_option.item_selected.is_connected(_on_actor_selected):
		_actor_option.item_selected.connect(_on_actor_selected)

	var add_button := Button.new()
	add_button.text = "+ Beat"
	add_button.tooltip_text = (
		"Add a beat at the current playhead time.\n"
		+ "Ctrl+D duplicates the selected beat instead."
	)
	_toolbar.add_child(add_button)
	if not add_button.pressed.is_connected(_add_beat):
		add_button.pressed.connect(_add_beat)

	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.tooltip_text = "Delete the selected beat.  (Delete)"
	_toolbar.add_child(delete_button)
	if not delete_button.pressed.is_connected(_delete_selected):
		delete_button.pressed.connect(_delete_selected)

	var copy_button := Button.new()
	copy_button.text = "Copy"
	copy_button.tooltip_text = "Copy selected beats for this or another cutscene.  (Ctrl+C)"
	copy_button.pressed.connect(_copy_selected)
	_toolbar.add_child(copy_button)

	var paste_button := Button.new()
	paste_button.text = "Paste"
	paste_button.tooltip_text = "Paste copied beats at the playhead.  (Ctrl+V)"
	paste_button.pressed.connect(_paste_clipboard)
	_toolbar.add_child(paste_button)

	var template_menu := MenuButton.new()
	template_menu.text = "Template"
	template_menu.tooltip_text = (
		"Add a reusable choreography block at the playhead."
	)
	var template_popup := template_menu.get_popup()
	template_popup.add_item("Entrance", TemplateKind.ENTRANCE)
	template_popup.add_item("Conversation", TemplateKind.CONVERSATION)
	template_popup.add_item("Reaction", TemplateKind.REACTION)
	template_popup.add_item("Mining strike", TemplateKind.MINING_STRIKE)
	template_popup.add_item("Exit", TemplateKind.EXIT)
	template_popup.add_separator()
	template_popup.add_item("Enter, speak, react, leave", TemplateKind.FULL_EXCHANGE)
	template_popup.id_pressed.connect(_on_template_selected)
	_toolbar.add_child(template_menu)

	var insert_time_button := Button.new()
	insert_time_button.text = "+ Time"
	insert_time_button.tooltip_text = (
		"Insert one grid division at the playhead and ripple later beats right."
	)
	insert_time_button.pressed.connect(_ripple_time.bind(1))
	_toolbar.add_child(insert_time_button)

	var remove_time_button := Button.new()
	remove_time_button.text = "- Time"
	remove_time_button.tooltip_text = (
		"Remove one grid division at the playhead and ripple later beats left."
	)
	remove_time_button.pressed.connect(_ripple_time.bind(-1))
	_toolbar.add_child(remove_time_button)

	var spacer := Control.new()
	spacer.custom_minimum_size.x = 12.0
	_toolbar.add_child(spacer)

	var zoom_label := Label.new()
	zoom_label.text = "Zoom"
	_toolbar.add_child(zoom_label)
	_zoom_spin = SpinBox.new()
	_zoom_spin.name = "PixelsPerSecond"
	_zoom_spin.min_value = MIN_PIXELS_PER_SECOND
	_zoom_spin.max_value = MAX_PIXELS_PER_SECOND
	_zoom_spin.step = 5.0
	_zoom_spin.value = _pixels_per_second
	_zoom_spin.suffix = " px/s"
	_zoom_spin.custom_minimum_size = Vector2(112.0, 0.0)
	_zoom_spin.tooltip_text = "Horizontal timeline scale; authored seconds do not change."
	_toolbar.add_child(_zoom_spin)
	if not _zoom_spin.value_changed.is_connected(_on_zoom_changed):
		_zoom_spin.value_changed.connect(_on_zoom_changed)

	var fit_button := Button.new()
	fit_button.text = "Fit"
	fit_button.tooltip_text = "Fit the whole sequence into the visible timeline."
	fit_button.pressed.connect(_zoom_to_fit)
	_toolbar.add_child(fit_button)

	var grid_label := Label.new()
	grid_label.text = "Grid"
	_toolbar.add_child(grid_label)
	_grid_spin = SpinBox.new()
	_grid_spin.name = "SnapGrid"
	_grid_spin.min_value = 0.0
	_grid_spin.max_value = 2.0
	_grid_spin.step = 0.05
	_grid_spin.value = _grid_seconds
	_grid_spin.suffix = " s"
	_grid_spin.custom_minimum_size = Vector2(88.0, 0.0)
	_grid_spin.tooltip_text = (
		"Time snapping interval. Hold Shift or Ctrl while dragging to bypass snapping."
	)
	_toolbar.add_child(_grid_spin)
	if not _grid_spin.value_changed.is_connected(_on_grid_changed):
		_grid_spin.value_changed.connect(_on_grid_changed)

	_play_button = Button.new()
	_play_button.name = "PlayPause"
	_play_button.text = "Play"
	_play_button.toggle_mode = true
	_play_button.custom_minimum_size = Vector2(72.0, 0.0)
	_play_button.tooltip_text = "Preview from the current playhead.  (Space)"
	_toolbar.add_child(_play_button)
	if not _play_button.toggled.is_connected(_on_play_toggled):
		_play_button.toggled.connect(_on_play_toggled)

	var set_in_button := Button.new()
	set_in_button.text = "In"
	set_in_button.tooltip_text = "Set loop start at the playhead.  (I)"
	set_in_button.pressed.connect(_set_loop_in)
	_toolbar.add_child(set_in_button)
	var set_out_button := Button.new()
	set_out_button.text = "Out"
	set_out_button.tooltip_text = "Set loop end at the playhead.  (O)"
	set_out_button.pressed.connect(_set_loop_out)
	_toolbar.add_child(set_out_button)
	_loop_button = CheckButton.new()
	_loop_button.text = "Loop"
	_loop_button.tooltip_text = "Repeat the marked in/out range.  (L)"
	_loop_button.toggled.connect(_on_loop_toggled)
	_toolbar.add_child(_loop_button)

	_lane_lock_button = CheckButton.new()
	_lane_lock_button.text = "Lock lane"
	_lane_lock_button.tooltip_text = "Prevent edits on the actor lane selected above."
	_lane_lock_button.toggled.connect(_on_lane_lock_toggled)
	_toolbar.add_child(_lane_lock_button)
	_lane_mute_button = CheckButton.new()
	_lane_mute_button.text = "Mute lane"
	_lane_mute_button.tooltip_text = "Ignore this actor lane while previewing."
	_lane_mute_button.toggled.connect(_on_lane_mute_toggled)
	_toolbar.add_child(_lane_mute_button)
	_lane_solo_button = CheckButton.new()
	_lane_solo_button.text = "Solo lane"
	_lane_solo_button.tooltip_text = "Preview only this actor lane."
	_lane_solo_button.toggled.connect(_on_lane_solo_toggled)
	_toolbar.add_child(_lane_solo_button)

	_time_label = Label.new()
	_time_label.name = "CurrentTime"
	_time_label.custom_minimum_size = Vector2(72.0, 0.0)
	_toolbar.add_child(_time_label)
	_duration_label = Label.new()
	_duration_label.name = "TotalDuration"
	_duration_label.custom_minimum_size = Vector2(82.0, 0.0)
	_toolbar.add_child(_duration_label)
	_update_actor_option_state()
	_update_lane_control_state()


func _build_status_bar() -> void:
	_status_bar = HBoxContainer.new()
	_status_bar.name = "TimelineStatusBar"
	_status_bar.custom_minimum_size = Vector2(0.0, 26.0)
	_status_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_status_bar)

	_playhead_readout = Label.new()
	_playhead_readout.name = "PlayheadReadout"
	_playhead_readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_playhead_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_playhead_readout.clip_text = true
	_status_bar.add_child(_playhead_readout)

	_legend = HBoxContainer.new()
	_legend.name = "KindLegend"
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_bar.add_child(_legend)
	_add_legend_item("MOVE", CutsceneBeat.Kind.MOVE)
	_add_legend_item("POSE", CutsceneBeat.Kind.POSE)
	_add_legend_item("DIALOGUE", CutsceneBeat.Kind.DIALOGUE)
	_add_legend_item("STAGE CUE", CutsceneBeat.Kind.STAGE_CUE)


func _add_legend_item(caption: String, kind: int) -> void:
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(8.0, 8.0)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.color = KIND_COLORS.get(kind, Color("#7e8794"))
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.add_child(swatch)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override(&"font_size", 10)
	label.add_theme_color_override(&"font_color", Color("#b8c1ce"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.add_child(label)


func _clear_children() -> void:
	for child in get_children():
		child.free()
	_toolbar = null
	_status_bar = null
	_playhead_readout = null
	_legend = null
	_canvas = null
	_validation_list = null
	_empty_message = null
	_loop_button = null
	_lane_lock_button = null
	_lane_mute_button = null
	_lane_solo_button = null


func _populate_actor_option() -> void:
	if _actor_option == null or not _has_valid_context():
		return
	_actor_option.add_item("Shared / none")
	_actor_option.set_item_metadata(0, StringName())
	var actor_ids := _context.get_stage_actor_ids()
	for actor_id_text in actor_ids:
		var actor_id := StringName(actor_id_text)
		_actor_option.add_item(actor_id_text)
		_actor_option.set_item_metadata(_actor_option.item_count - 1, actor_id)


func _update_actor_option_state() -> void:
	if _actor_option == null:
		return
	_actor_option.disabled = not _kind_uses_actor(_selected_kind)
	if _kind_uses_actor(_selected_kind):
		if _actor_option.item_count > 1:
			_actor_option.select(1)
		else:
			_actor_option.select(0)
	else:
		_actor_option.select(0)


func _on_kind_selected(index: int) -> void:
	_selected_kind = clampi(index, 0, CutsceneBeat.Kind.size() - 1)
	_update_actor_option_state()


func _on_actor_selected(_index: int) -> void:
	# The same choice authors the next beat and scopes the session-only lane
	# controls, so a designer does not need a second actor picker.
	_update_lane_control_state()


func _current_toolbar_actor() -> StringName:
	if _actor_option == null or _actor_option.item_count <= 0:
		return StringName()
	var selected_index := maxi(_actor_option.selected, 0)
	return StringName(_actor_option.get_item_metadata(selected_index))


func _update_lane_control_state() -> void:
	var actor_id := _current_toolbar_actor()
	if _lane_lock_button != null:
		_lane_lock_button.set_pressed_no_signal(
			bool(_locked_lanes.get(actor_id, false))
		)
	if _lane_mute_button != null:
		_lane_mute_button.set_pressed_no_signal(
			bool(_muted_lanes.get(actor_id, false))
		)
	if _lane_solo_button != null:
		_lane_solo_button.set_pressed_no_signal(
			bool(_solo_lanes.get(actor_id, false))
		)


func _set_lane_state(store: Dictionary, enabled: bool) -> void:
	var actor_id := _current_toolbar_actor()
	if enabled:
		store[actor_id] = true
	else:
		store.erase(actor_id)
	refresh_preview()


func _on_lane_lock_toggled(enabled: bool) -> void:
	_set_lane_state(_locked_lanes, enabled)


func _on_lane_mute_toggled(enabled: bool) -> void:
	_set_lane_state(_muted_lanes, enabled)


func _on_lane_solo_toggled(enabled: bool) -> void:
	_set_lane_state(_solo_lanes, enabled)


func _on_zoom_changed(value: float) -> void:
	_pixels_per_second = clampf(
		value,
		MIN_PIXELS_PER_SECOND,
		MAX_PIXELS_PER_SECOND
	)
	_update_timeline_size()
	if _canvas != null:
		_canvas.queue_redraw()


func _on_grid_changed(value: float) -> void:
	_grid_seconds = maxf(value, 0.0)


func _on_play_toggled(pressed: bool) -> void:
	_set_playing(pressed)


func _set_playing(playing: bool) -> void:
	_is_playing = playing and _has_valid_context()
	if _play_button != null:
		_play_button.set_pressed_no_signal(_is_playing)
		_play_button.text = "Pause" if _is_playing else "Play"
	set_process(_is_playing or _has_valid_context())


func _has_loop_range() -> bool:
	return (
		_loop_enabled
		and _loop_end_seconds > _loop_start_seconds + 0.00001
	)


func _set_loop_in() -> void:
	_loop_start_seconds = _scrub_time
	if _loop_end_seconds <= _loop_start_seconds:
		_loop_end_seconds = minf(
			_sequence_duration(),
			_loop_start_seconds + maxf(_grid_seconds, DEFAULT_GRID_SECONDS)
		)
	_update_playhead_readout()
	if _canvas != null:
		_canvas.queue_redraw()


func _set_loop_out() -> void:
	_loop_end_seconds = _scrub_time
	if _loop_end_seconds <= _loop_start_seconds:
		_loop_start_seconds = maxf(
			0.0,
			_loop_end_seconds - maxf(_grid_seconds, DEFAULT_GRID_SECONDS)
		)
	_update_playhead_readout()
	if _canvas != null:
		_canvas.queue_redraw()


func _on_loop_toggled(enabled: bool) -> void:
	_loop_enabled = enabled
	if enabled and _loop_end_seconds <= _loop_start_seconds:
		_loop_start_seconds = _scrub_time
		_loop_end_seconds = _sequence_duration()
	if _canvas != null:
		_canvas.queue_redraw()


func _zoom_to_fit() -> void:
	var duration := maxf(_sequence_duration(), 0.1)
	var available_width := maxf(size.x - LANE_LABEL_WIDTH - 32.0, 200.0)
	_pixels_per_second = clampf(
		available_width / (duration + 0.25),
		MIN_PIXELS_PER_SECOND,
		MAX_PIXELS_PER_SECOND
	)
	if _zoom_spin != null:
		_zoom_spin.set_value_no_signal(_pixels_per_second)
	_update_timeline_size()


## Inserts or removes one grid unit without changing beat durations. This is a
## concrete ripple edit rather than a general time-warp system: every beat at
## or after the playhead moves together, and no beat can cross time zero.
func _ripple_time(direction: int) -> void:
	if not _has_valid_context() or direction == 0:
		return
	var amount := maxf(_grid_seconds, DEFAULT_GRID_SECONDS) * float(signi(direction))
	var changes: Dictionary = {}
	for beat in _context.sequence.beats:
		if beat == null or beat.start_seconds < _scrub_time - 0.00001:
			continue
		if bool(_locked_lanes.get(beat.actor, false)):
			continue
		var moved := maxf(beat.start_seconds + amount, _scrub_time if amount < 0.0 else 0.0)
		if not is_equal_approx(moved, beat.start_seconds):
			changes[beat] = moved
	_commit_beat_start_changes(
		changes,
		"Insert cutscene time" if direction > 0 else "Remove cutscene time"
	)


func _on_template_selected(template_id: int) -> void:
	if not _has_valid_context():
		return
	var actor_id := _current_toolbar_actor()
	if actor_id.is_empty() and not _lane_actor_ids.is_empty():
		actor_id = StringName(_lane_actor_ids[0])
	var cursor := snap_time(_scrub_time)
	var additions: Array[CutsceneBeat] = []
	match template_id:
		TemplateKind.ENTRANCE:
			additions.append(_make_move_template(actor_id, cursor, &"Entrance", &"Conversation"))
		TemplateKind.CONVERSATION:
			additions.append(_make_dialogue_template(cursor))
		TemplateKind.REACTION:
			additions.append(_make_reaction_template(actor_id, cursor))
		TemplateKind.MINING_STRIKE:
			var strike := CutsceneBeat.new()
			strike.kind = CutsceneBeat.Kind.STRIKE
			strike.start_seconds = cursor
			strike.duration_seconds = 0.25
			strike.cue = _first_marker_name(&"ActionMarkers")
			additions.append(strike)
		TemplateKind.EXIT:
			additions.append(_make_move_template(actor_id, cursor, &"Rest", &"Exit"))
		TemplateKind.FULL_EXCHANGE:
			additions.append(_make_move_template(actor_id, cursor, &"Entrance", &"Conversation"))
			cursor += 1.0
			var dialogue := _make_dialogue_template(cursor)
			additions.append(dialogue)
			cursor += maxf(dialogue.duration_seconds, 1.0)
			additions.append(_make_reaction_template(actor_id, cursor))
			cursor += 0.4
			additions.append(_make_move_template(actor_id, cursor, &"Conversation", &"Exit"))
	if additions.is_empty():
		return
	_append_new_beats(additions, "Add choreography template")


func _make_move_template(
	actor_id: StringName,
	start_seconds: float,
	start_marker: StringName,
	target_marker: StringName
) -> CutsceneBeat:
	var beat := CutsceneBeat.new()
	beat.kind = CutsceneBeat.Kind.MOVE
	beat.actor = actor_id
	beat.start_seconds = start_seconds
	beat.duration_seconds = 1.0
	beat.starts_from_authored_point = true
	beat.start_marker = start_marker if _context.get_marker_names().has(start_marker) else StringName()
	beat.target_marker = target_marker if _context.get_marker_names().has(target_marker) else StringName()
	if beat.start_marker.is_empty():
		beat.start_offset = _actor_position(actor_id)
	if beat.target_marker.is_empty():
		beat.target_offset = _actor_position(actor_id)
	return beat


func _make_dialogue_template(start_seconds: float) -> CutsceneBeat:
	var beat := CutsceneBeat.new()
	beat.kind = CutsceneBeat.Kind.DIALOGUE
	beat.start_seconds = start_seconds
	beat.duration_seconds = 2.0
	beat.blocks = true
	if _context.encounter != null:
		beat.conversation = _context.encounter.conversation
	return beat


func _make_reaction_template(
	actor_id: StringName,
	start_seconds: float
) -> CutsceneBeat:
	var beat := CutsceneBeat.new()
	beat.kind = CutsceneBeat.Kind.BOUNCE
	beat.actor = actor_id
	beat.start_seconds = start_seconds
	beat.duration_seconds = 0.35
	beat.bounce_count = 1
	return beat


func _actor_position(actor_id: StringName) -> Vector2:
	var actor := _context.get_actor_preview(actor_id)
	if not is_instance_valid(actor):
		return Vector2.ZERO
	return _context.stage.to_local(actor.global_position)


func _first_marker_name(root_name: StringName) -> StringName:
	if _context == null or not is_instance_valid(_context.stage):
		return StringName()
	var marker_root := _context.stage.get_node_or_null(NodePath(root_name))
	if marker_root == null:
		return StringName()
	for child in marker_root.get_children():
		if child is Marker2D:
			return child.name
	return StringName()


func _append_new_beats(
	additions: Array[CutsceneBeat],
	action_name: String
) -> void:
	var beats: Array[CutsceneBeat] = _context.sequence.beats.duplicate()
	beats.append_array(additions)
	_commit_resource_changes(
		_context.sequence,
		{&"beats": beats},
		action_name
	)
	_set_selection(additions, additions.back())
	_rebuild_lane_data()
	_refresh_validation()
	_update_timeline_size()


func _add_beat() -> void:
	if not _has_valid_context():
		return
	var beat := CutsceneBeat.new()
	beat.kind = _selected_kind
	beat.start_seconds = snap_time(_scrub_time)
	beat.duration_seconds = _default_duration_for_kind(_selected_kind)
	if (
		_selected_kind == CutsceneBeat.Kind.DIALOGUE
		and _context.encounter != null
	):
		beat.conversation = _context.encounter.conversation
	if _kind_uses_actor(_selected_kind) and _actor_option.item_count > 0:
		var selected_index := _actor_option.selected
		if selected_index < 0:
			selected_index = 0
		beat.actor = _actor_option.get_item_metadata(selected_index)
		if bool(_locked_lanes.get(beat.actor, false)):
			_validation_list.tooltip_text = (
				"Unlock '%s' before adding a beat to it." % beat.actor
			)
			return
	var next_beats: Array[CutsceneBeat] = []
	for existing in _context.sequence.beats:
		if existing != null:
			next_beats.append(existing)
	next_beats.append(beat)
	_commit_resource_changes(
		_context.sequence,
		{
			"beats": {
				"before": _context.sequence.beats,
				"after": next_beats,
			}
		},
		"Add cutscene beat"
	)
	_set_selection([beat], beat)
	_rebuild_lane_data()
	_refresh_validation()
	_update_timeline_size()
	if _canvas != null:
		_canvas.queue_redraw()


func _delete_selected() -> void:
	if not _has_valid_context() or _selected_beats.is_empty():
		return
	var next_beats: Array[CutsceneBeat] = []
	var found := false
	for existing in _context.sequence.beats:
		if _selected_beats.has(existing):
			if bool(_locked_lanes.get(existing.actor, false)):
				next_beats.append(existing)
				continue
			found = true
			continue
		if existing != null:
			next_beats.append(existing)
	if not found:
		return
	_commit_resource_changes(
		_context.sequence,
		{
			"beats": {
				"before": _context.sequence.beats,
				"after": next_beats,
			}
		},
		"Delete cutscene beat"
	)
	_set_selection([], null)
	_rebuild_lane_data()
	_refresh_validation()
	_update_timeline_size()
	if _canvas != null:
		_canvas.queue_redraw()


func _handle_canvas_input(
	event_type: StringName,
	position: Vector2,
	event: InputEvent
) -> bool:
	if not _has_valid_context():
		return false
	match event_type:
		&"key":
			return _handle_canvas_key(event as InputEventKey)
		&"press":
			if position.y < RULER_HEIGHT and position.x >= LANE_LABEL_WIDTH:
				_begin_scrub(pixels_to_time(position.x - LANE_LABEL_WIDTH))
				return true
			var hit := _hit_test_beat(position)
			if hit.is_empty():
				if not (event as InputEventMouseButton).shift_pressed:
					_set_selection([], null)
				return false
			var beat := hit["beat"] as CutsceneBeat
			var button := event as InputEventMouseButton
			_select_beat(beat, button.shift_pressed or button.ctrl_pressed)
			if bool(_locked_lanes.get(beat.actor, false)):
				return true
			_begin_drag(
				beat,
				bool(hit["resize"]),
				position
			)
			return true
		&"motion":
			if _drag_mode.is_empty():
				return false
			_update_drag(position, event)
			return true
		&"release":
			if _drag_mode.is_empty():
				return false
			_finish_drag()
			return true
	return false


func _cursor_for_position(position: Vector2) -> Control.CursorShape:
	if _drag_mode == &"resize":
		return Control.CURSOR_HSIZE
	if _drag_mode == &"move" or _drag_mode == &"scrub":
		return Control.CURSOR_MOVE
	var hit := _hit_test_beat(position)
	if not hit.is_empty():
		if bool(hit["resize"]):
			return Control.CURSOR_HSIZE
		return Control.CURSOR_POINTING_HAND
	return Control.CURSOR_ARROW


## The bindings an animation timeline is expected to answer: space transports,
## Delete removes, Ctrl+D duplicates, the arrows step, and Home/End jump to the
## ends. Shift multiplies a step by ten, and Ctrl moves the selected beat rather
## than the playhead, which are the two modifiers this kind of editor always
## carries.
##
## Returns whether the key was claimed, so anything unbound still reaches the
## editor underneath instead of being swallowed by a focused timeline.
func _handle_canvas_key(key: InputEventKey) -> bool:
	if key == null:
		return false
	var step := _grid_seconds if _grid_seconds > 0.0 else DEFAULT_GRID_SECONDS
	if key.shift_pressed:
		step *= 10.0
	match key.keycode:
		KEY_SPACE:
			_set_playing(not _is_playing)
			return true
		KEY_DELETE:
			if _selected_beats.is_empty():
				return false
			_delete_selected()
			return true
		KEY_A:
			if not key.ctrl_pressed:
				return false
			var all_beats: Array[CutsceneBeat] = []
			for beat in _context.sequence.beats:
				if beat != null:
					all_beats.append(beat)
			_set_selection(all_beats, all_beats.back() if not all_beats.is_empty() else null)
			return true
		KEY_C:
			if not key.ctrl_pressed or _selected_beats.is_empty():
				return false
			_copy_selected()
			return true
		KEY_V:
			if not key.ctrl_pressed or _beat_clipboard.is_empty():
				return false
			_paste_clipboard()
			return true
		KEY_D:
			if not key.ctrl_pressed or _selected_beats.is_empty():
				return false
			_duplicate_selected()
			return true
		KEY_I:
			_set_loop_in()
			return true
		KEY_O:
			_set_loop_out()
			return true
		KEY_L:
			_loop_enabled = not _loop_enabled
			if _loop_button != null:
				_loop_button.set_pressed_no_signal(_loop_enabled)
			_on_loop_toggled(_loop_enabled)
			return true
		KEY_LEFT:
			if key.ctrl_pressed:
				return _nudge_selected_beat(-step)
			_set_scrub_time(_scrub_time - step, true)
			return true
		KEY_RIGHT:
			if key.ctrl_pressed:
				return _nudge_selected_beat(step)
			_set_scrub_time(_scrub_time + step, true)
			return true
		KEY_HOME:
			_set_scrub_time(0.0, true)
			return true
		KEY_END:
			_set_scrub_time(_context.sequence.get_duration_seconds(), true)
			return true
	return false


## Copies the selected beat one grid step later and selects the copy, so a
## repeated action is authored by duplicating rather than by rebuilding it.
func _duplicate_selected() -> void:
	if not _has_valid_context() or _selected_beats.is_empty():
		return
	var step := _grid_seconds if _grid_seconds > 0.0 else DEFAULT_GRID_SECONDS
	var beats: Array[CutsceneBeat] = _context.sequence.beats.duplicate()
	var copies: Array[CutsceneBeat] = []
	var selection_end := 0.0
	for selected in _selected_beats:
		selection_end = maxf(selection_end, selected.get_end_seconds())
	var selection_start := _selection_start_seconds()
	var offset := maxf(selection_end - selection_start, step)
	for selected in _selected_beats:
		if bool(_locked_lanes.get(selected.actor, false)):
			continue
		var copy: CutsceneBeat = selected.duplicate(true)
		copy.start_seconds = snap_time(selected.start_seconds + offset)
		beats.append(copy)
		copies.append(copy)
	if copies.is_empty():
		return
	_commit_resource_changes(
		_context.sequence,
		{&"beats": beats},
		"Duplicate cutscene beats"
	)
	_set_selection(copies, copies.back())


func _selection_start_seconds() -> float:
	if _selected_beats.is_empty():
		return _scrub_time
	var earliest := INF
	for beat in _selected_beats:
		earliest = minf(earliest, maxf(beat.start_seconds, 0.0))
	return earliest


func _copy_selected() -> void:
	if not _has_valid_context() or _selected_beats.is_empty():
		return
	_beat_clipboard.clear()
	var ordered := _selected_beats.duplicate()
	ordered.sort_custom(
		func(left: CutsceneBeat, right: CutsceneBeat) -> bool:
			return left.start_seconds < right.start_seconds
	)
	for beat in ordered:
		_beat_clipboard.append(beat.duplicate(true))


func _paste_clipboard() -> void:
	if not _has_valid_context() or _beat_clipboard.is_empty():
		return
	var earliest := INF
	for copied in _beat_clipboard:
		earliest = minf(earliest, copied.start_seconds)
	var beats: Array[CutsceneBeat] = _context.sequence.beats.duplicate()
	var pasted: Array[CutsceneBeat] = []
	for copied in _beat_clipboard:
		if bool(_locked_lanes.get(copied.actor, false)):
			continue
		var beat: CutsceneBeat = copied.duplicate(true)
		beat.start_seconds = snap_time(
			_scrub_time + maxf(copied.start_seconds - earliest, 0.0)
		)
		beats.append(beat)
		pasted.append(beat)
	if pasted.is_empty():
		return
	_commit_resource_changes(
		_context.sequence,
		{&"beats": beats},
		"Paste cutscene beats"
	)
	_set_selection(pasted, pasted.back())
	_rebuild_lane_data()
	_refresh_validation()
	_update_timeline_size()


## Slides the selected beat along its lane by one step, clamped at zero so a
## beat cannot be nudged to a negative start time.
func _nudge_selected_beat(delta_seconds: float) -> bool:
	if not _has_valid_context() or _selected_beat == null:
		return false
	if bool(_locked_lanes.get(_selected_beat.actor, false)):
		return false
	var moved := maxf(
		snap_time(maxf(_selected_beat.start_seconds, 0.0) + delta_seconds),
		0.0
	)
	if is_equal_approx(moved, _selected_beat.start_seconds):
		return true
	_commit_resource_changes(
		_selected_beat,
		{&"start_seconds": moved},
		"Nudge cutscene beat"
	)
	return true


func _begin_scrub(seconds: float) -> void:
	_drag_mode = &"scrub"
	_set_scrub_time(seconds, true)


func _begin_drag(beat: CutsceneBeat, resize: bool, position: Vector2) -> void:
	_drag_beat = beat
	_drag_original_start = maxf(beat.start_seconds, 0.0)
	_drag_original_duration = maxf(beat.duration_seconds, 0.0)
	_drag_original_actor = beat.actor
	_drag_preview_start = _drag_original_start
	_drag_preview_duration = _drag_original_duration
	_drag_preview_actor = _drag_original_actor
	_drag_mode = &"resize" if resize else &"move"
	_drag_group_original_starts.clear()
	_drag_group_preview_starts.clear()
	if not resize:
		if not _selected_beats.has(beat):
			_set_selection([beat], beat)
		for selected in _selected_beats:
			if not bool(_locked_lanes.get(selected.actor, false)):
				_drag_group_original_starts[selected] = maxf(
					selected.start_seconds,
					0.0
				)
				_drag_group_preview_starts[selected] = maxf(
					selected.start_seconds,
					0.0
				)
		var pointer_time := pixels_to_time(
			position.x - LANE_LABEL_WIDTH
		)
		_drag_pointer_offset_seconds = pointer_time - _drag_original_start


## Pulls a dragged time onto the nearest other beat's start or end when it comes
## within snapping distance, so beats butt together exactly instead of leaving a
## hairline gap or overlapping by a hundredth of a second.
##
## The threshold is in pixels rather than seconds: at low zoom a whole second is
## a few pixels wide and a seconds-based threshold would drag everything into a
## magnet, while at high zoom it would never reach. Holding the grid-bypass
## modifier turns this off with everything else, which is how a beat gets placed
## deliberately close to a neighbour without touching it.
func _snap_to_neighbour_edges(seconds: float, bypass: bool) -> float:
	if bypass or not _has_valid_context():
		return seconds
	var threshold := _NEIGHBOUR_SNAP_PIXELS / maxf(_resolved_zoom(-1.0), 0.001)
	var best := seconds
	var best_distance := threshold
	for beat in _context.sequence.beats:
		if beat == null or beat == _drag_beat:
			continue
		var start := maxf(beat.start_seconds, 0.0)
		for edge in [start, start + maxf(beat.duration_seconds, 0.0)]:
			var distance := absf(edge - seconds)
			if distance < best_distance:
				best_distance = distance
				best = edge
	# Zero is an edge too: the sequence's own start is the one every opening
	# beat wants to sit exactly on.
	if absf(seconds) < best_distance:
		best = 0.0
	return maxf(best, 0.0)


func _update_drag(position: Vector2, event: InputEvent) -> void:
	if _drag_mode == &"scrub":
		_set_scrub_time(
			pixels_to_time(position.x - LANE_LABEL_WIDTH),
			true
		)
		return
	if _drag_beat == null:
		return
	var bypass_grid := _event_bypasses_grid(event)
	if _drag_mode == &"resize":
		var right_edge_time := pixels_to_time(
			position.x - LANE_LABEL_WIDTH
		)
		var snapped_right_edge := snap_time(
			right_edge_time,
			_grid_seconds,
			bypass_grid
		)
		_drag_preview_duration = clamp_duration_after_resize(
			_drag_original_start,
			_snap_to_neighbour_edges(snapped_right_edge, bypass_grid)
		)
	else:
		var pointer_time := pixels_to_time(
			position.x - LANE_LABEL_WIDTH
		)
		var proposed_start := pointer_time - _drag_pointer_offset_seconds
		var gridded_start := snap_time(
			proposed_start,
			_grid_seconds,
			bypass_grid
		)
		# Snapping the beat's own end as well as its start, so a beat can be
		# butted up against the one after it and not only the one before it.
		var duration := maxf(_drag_original_duration, 0.0)
		var snapped_start := _snap_to_neighbour_edges(
			gridded_start,
			bypass_grid
		)
		if is_equal_approx(snapped_start, gridded_start) and duration > 0.0:
			var snapped_end := _snap_to_neighbour_edges(
				gridded_start + duration,
				bypass_grid
			)
			snapped_start = snapped_end - duration
		_drag_preview_start = maxf(snapped_start, 0.0)
		if not _drag_group_original_starts.is_empty():
			var delta := _drag_preview_start - _drag_original_start
			var earliest := INF
			for original_variant in _drag_group_original_starts.values():
				earliest = minf(earliest, float(original_variant))
			delta = maxf(delta, -earliest)
			for selected_variant in _drag_group_original_starts.keys():
				var selected := selected_variant as CutsceneBeat
				if selected == null:
					continue
				_drag_group_preview_starts[selected] = (
					float(_drag_group_original_starts[selected]) + delta
				)
			_drag_preview_start = float(
				_drag_group_preview_starts.get(
					_drag_beat,
					_drag_preview_start
				)
			)
		var lane_actor := _actor_for_lane_position(position.y)
		if lane_actor != &"__outside__":
			_drag_preview_actor = lane_actor
	if _canvas != null:
		_canvas.queue_redraw()


func _finish_drag() -> void:
	if _drag_mode == &"scrub":
		_drag_mode = &""
		if _canvas != null:
			_canvas.queue_redraw()
		return
	if _drag_beat == null:
		_stop_drag_without_commit()
		return
	if _drag_mode == &"move" and not _drag_group_preview_starts.is_empty():
		var start_changes: Dictionary = {}
		for selected_variant in _drag_group_preview_starts.keys():
			var selected := selected_variant as CutsceneBeat
			if selected == null:
				continue
			var preview_start := float(_drag_group_preview_starts[selected])
			if not is_equal_approx(preview_start, selected.start_seconds):
				start_changes[selected] = preview_start
		_commit_beat_start_changes(start_changes, "Move cutscene beats")
		if _drag_preview_actor != _drag_original_actor:
			_commit_resource_changes(
				_drag_beat,
				{
					&"actor": {
						"before": _drag_original_actor,
						"after": _drag_preview_actor,
					}
				},
				"Move cutscene beat to lane"
			)
		_stop_drag_without_commit()
		_rebuild_lane_data()
		_refresh_validation()
		_update_timeline_size()
		return
	var changes: Dictionary = {}
	if not is_equal_approx(_drag_preview_start, _drag_original_start):
		changes["start_seconds"] = {
			"before": _drag_original_start,
			"after": _drag_preview_start,
		}
	if not is_equal_approx(_drag_preview_duration, _drag_original_duration):
		changes["duration_seconds"] = {
			"before": _drag_original_duration,
			"after": _drag_preview_duration,
		}
	if _drag_preview_actor != _drag_original_actor:
		changes["actor"] = {
			"before": _drag_original_actor,
			"after": _drag_preview_actor,
		}
	if not changes.is_empty():
		_commit_resource_changes(
			_drag_beat,
			changes,
			"Edit cutscene beat"
		)
	_drag_beat = null
	_drag_mode = &""
	_drag_group_original_starts.clear()
	_drag_group_preview_starts.clear()
	_rebuild_lane_data()
	_refresh_validation()
	_update_timeline_size()
	if _canvas != null:
		_canvas.queue_redraw()


func _stop_drag_without_commit() -> void:
	_drag_mode = &""
	_drag_beat = null
	_drag_group_original_starts.clear()
	_drag_group_preview_starts.clear()
	if _canvas != null:
		_canvas.queue_redraw()


## Selects a beat and moves the playhead to the moment it begins.
##
## Clicking a beat is how a designer asks "what does this one do", and the
## answer is in the viewport, not in this panel. Without the scrub the cast
## stays frozen wherever the playhead happened to be, so the selected beat
## highlights a box on a chart while the stage shows an unrelated instant.
func _select_beat(beat: CutsceneBeat, additive: bool = false) -> void:
	if not additive:
		_set_selection([beat] if beat != null else [], beat)
		return
	var next_selection: Array[CutsceneBeat] = _selected_beats.duplicate()
	if next_selection.has(beat):
		next_selection.erase(beat)
	else:
		next_selection.append(beat)
	var active: CutsceneBeat = beat if next_selection.has(beat) else (
		next_selection.back() if not next_selection.is_empty() else null
	)
	_set_selection(next_selection, active)


func _set_selection(beats: Array, active: CutsceneBeat) -> void:
	_selected_beats.clear()
	for beat_variant in beats:
		var beat := beat_variant as CutsceneBeat
		if beat != null and not _selected_beats.has(beat):
			_selected_beats.append(beat)
	if active != null and _selected_beats.has(active):
		_selected_beat = active
	else:
		_selected_beat = (
			_selected_beats.back() if not _selected_beats.is_empty() else null
		)
	if _selected_beat != null and not _is_playing:
		_set_scrub_time(maxf(_selected_beat.start_seconds, 0.0), true)
	beat_selected.emit(_selected_beat)
	beat_selection_changed.emit(_selected_beats)
	if _canvas != null:
		_canvas.queue_redraw()


func _begin_preview_evaluation() -> void:
	if _preview_player == null:
		_preview_player = CutsceneSequencePlayer.new()
	_preview_player.bind(
		Callable(self, "_resolve_preview_actor"),
		Callable(self, "_resolve_preview_marker"),
		Callable(),
		_context.stage
	)


func _set_scrub_time(seconds: float, emit_signal: bool) -> void:
	if not _has_valid_context():
		_scrub_time = 0.0
		return
	_scrub_time = clampf(seconds, 0.0, _sequence_duration())
	_apply_preview_at_time()
	_update_toolbar_readout()
	_update_playhead_readout()
	if _canvas != null:
		_canvas.queue_redraw()
	if emit_signal:
		scrub_time_changed.emit(_scrub_time)


## Re-places the stand-ins for the current playhead time. Public so the viewport
## can call it while a walk's destination is being dragged, and see the cast
## follow the pointer instead of waiting for the drag to finish.
func refresh_preview() -> void:
	if not _has_valid_context():
		return
	_apply_preview_at_time()
	if _canvas != null:
		_canvas.queue_redraw()


func _apply_preview_at_time() -> void:
	if not _has_valid_context():
		return
	_restore_preview_states()
	_begin_preview_evaluation()
	var result := _preview_player.evaluate_at(
		_context.sequence,
		_scrub_time
	)
	var actor_states: Dictionary = result.get(&"actors", {})
	var has_solo := not _solo_lanes.is_empty()
	for actor_id_text in _context.get_stage_actor_ids():
		var actor_id := StringName(actor_id_text)
		var preview := _context.get_actor_preview(actor_id) as Node2D
		if not is_instance_valid(preview):
			continue
		if bool(_muted_lanes.get(actor_id, false)) or (
			has_solo and not bool(_solo_lanes.get(actor_id, false))
		):
			preview.visible = false
			continue
		if not actor_states.has(actor_id):
			continue
		var state: Dictionary = actor_states[actor_id]
		if state.has(&"position"):
			preview.global_position = state[&"position"]
			# Remembered so the next restore can tell a position this panel
			# wrote from one the designer dragged.
			_preview_applied_states[actor_id] = preview.global_position
		if state.has(&"visible"):
			preview.visible = bool(state[&"visible"])
		if state.has(&"facing") and preview.has_method(&"set_facing_direction"):
			preview.call(&"set_facing_direction", int(state[&"facing"]))
		if state.has(&"pose"):
			var pose: StringName = state[&"pose"]
			preview.pose = pose
		if state.has(&"visual_offset"):
			preview.set_presentation_offset(state[&"visual_offset"])


func _capture_preview_states() -> void:
	_preview_base_states.clear()
	_preview_applied_states.clear()
	if not _has_valid_context():
		return
	for actor_id_text in _context.get_stage_actor_ids():
		var actor_id := StringName(actor_id_text)
		var preview := _context.get_actor_preview(actor_id) as Node2D
		if not is_instance_valid(preview):
			continue
		_preview_base_states[actor_id] = {
			"position": preview.global_position,
			"scale": preview.scale,
			"pose": preview.pose,
			"visible": preview.visible,
			"visual_offset": preview.get_presentation_offset(),
		}


## Puts the cast back where they stood before the playhead moved them.
##
## An actor the designer has since dragged is left alone and adopted as the new
## resting place instead. The base states are captured once when the panel is
## built, so without this check the first scrub after moving somebody snapped
## them back to where they were minutes ago and the move looked like it had
## silently failed. Anything the preview itself wrote is known, so a position
## that no longer matches can only have come from the designer.
func _restore_preview_states() -> void:
	if _context == null:
		return
	for actor_id_variant in _preview_base_states.keys():
		var actor_id := StringName(actor_id_variant)
		var preview := _context.get_actor_preview(actor_id) as Node2D
		if not is_instance_valid(preview):
			continue
		var base_state: Dictionary = _preview_base_states[actor_id_variant]
		if _preview_applied_states.has(actor_id):
			var applied: Vector2 = _preview_applied_states[actor_id]
			if not preview.global_position.is_equal_approx(applied):
				base_state["position"] = preview.global_position
				_preview_base_states[actor_id_variant] = base_state
				_preview_applied_states.erase(actor_id)
				continue
		elif not preview.global_position.is_equal_approx(
			base_state["position"]
		):
			# An actor with no beats has no preview-applied entry. Cast tools
			# still move that actor's real scene node, so adopt the changed
			# position instead of restoring the stale position captured when
			# the timeline opened.
			base_state["position"] = preview.global_position
			_preview_base_states[actor_id_variant] = base_state
			continue
		preview.global_position = base_state["position"]
		preview.scale = base_state["scale"]
		preview.pose = base_state["pose"]
		preview.visible = bool(base_state["visible"])
		preview.set_presentation_offset(base_state["visual_offset"])


func _prepare_for_stage_position_change() -> void:
	_restore_preview_states()
	# The next Cast notification must treat its committed transforms as authored
	# changes even when a target happens to equal the former playhead preview.
	_preview_applied_states.clear()


func _resolve_preview_actor(actor_id: StringName) -> Node2D:
	if not _has_valid_context():
		return null
	return _context.get_actor_preview(actor_id) as Node2D


func _resolve_preview_marker(marker_name: StringName) -> Vector2:
	if not _has_valid_context():
		return Vector2.ZERO
	return _context.get_marker_position(marker_name)


func _hit_test_beat(position: Vector2) -> Dictionary:
	if position.x < LANE_LABEL_WIDTH or position.y < RULER_HEIGHT:
		return {}
	var lane_index := floori((position.y - RULER_HEIGHT) / LANE_HEIGHT)
	if lane_index < 0 or lane_index >= _lane_count():
		return {}
	for beat in _context.sequence.beats:
		if beat == null:
			continue
		if _lane_index_for_actor(_display_actor(beat)) != lane_index:
			continue
		var rect := _beat_rect(beat)
		if rect.has_point(position):
			return {
				"beat": beat,
				"resize": position.x >= rect.end.x - EDGE_HOT_ZONE,
			}
	return {}


func _beat_rect(beat: CutsceneBeat) -> Rect2:
	var start := _display_start(beat)
	var duration := _display_duration(beat)
	var x := LANE_LABEL_WIDTH + time_to_pixels(start)
	var width := maxf(time_to_pixels(duration), MIN_BEAT_WIDTH)
	var y := RULER_HEIGHT + float(_lane_index_for_actor(_display_actor(beat))) * LANE_HEIGHT
	return Rect2(x, y + 10.0, width, LANE_HEIGHT - 18.0)


func _display_start(beat: CutsceneBeat) -> float:
	if _drag_group_preview_starts.has(beat):
		return float(_drag_group_preview_starts[beat])
	return _drag_preview_start if beat == _drag_beat else maxf(beat.start_seconds, 0.0)


func _display_duration(beat: CutsceneBeat) -> float:
	return (
		_drag_preview_duration
		if beat == _drag_beat
		else maxf(beat.duration_seconds, 0.0)
	)


func _display_actor(beat: CutsceneBeat) -> StringName:
	return _drag_preview_actor if beat == _drag_beat else beat.actor


func _actor_for_lane_position(y: float) -> StringName:
	if y < RULER_HEIGHT or y >= RULER_HEIGHT + float(_lane_count()) * LANE_HEIGHT:
		return &"__outside__"
	var index := floori((y - RULER_HEIGHT) / LANE_HEIGHT)
	if index == 0:
		return StringName()
	var actor_index := index - 1
	if actor_index >= 0 and actor_index < _lane_actor_ids.size():
		return StringName(_lane_actor_ids[actor_index])
	return &"__outside__"


func _rebuild_lane_data() -> void:
	_lane_actor_ids = PackedStringArray()
	if not _has_valid_context():
		return
	_lane_actor_ids = _context.get_stage_actor_ids()
	for beat in _context.sequence.beats:
		if beat == null or beat.actor.is_empty():
			continue
		if not _lane_actor_ids.has(str(beat.actor)):
			_lane_actor_ids.append(str(beat.actor))


func _lane_count() -> int:
	return 1 + _lane_actor_ids.size()


func _lane_index_for_actor(actor_id: StringName) -> int:
	if actor_id.is_empty():
		return 0
	var index := _lane_actor_ids.find(str(actor_id))
	return index + 1 if index >= 0 else 0


func _update_timeline_size() -> void:
	if _canvas == null or not _has_valid_context():
		return
	var timeline_end := _sequence_duration()
	if _drag_beat != null:
		timeline_end = maxf(
			timeline_end,
			_display_start(_drag_beat) + _display_duration(_drag_beat)
		)
	var width := LANE_LABEL_WIDTH + time_to_pixels(timeline_end + 1.0)
	width = maxf(width, 900.0)
	var height := RULER_HEIGHT + float(_lane_count()) * LANE_HEIGHT
	_canvas.custom_minimum_size = Vector2(width, height)
	_canvas.queue_redraw()


func _draw_timeline(canvas: Control) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color("#171b23"))
	if not _has_valid_context():
		return
	var lane_count := _lane_count()
	canvas.draw_rect(
		Rect2(0.0, 0.0, canvas.size.x, RULER_HEIGHT),
		Color("#222936")
	)
	canvas.draw_rect(
		Rect2(0.0, RULER_HEIGHT, LANE_LABEL_WIDTH, canvas.size.y),
		Color("#202631")
	)
	var font := ThemeDB.fallback_font
	for lane_index in range(lane_count):
		var lane_y := RULER_HEIGHT + float(lane_index) * LANE_HEIGHT
		var lane_color := Color("#1b2029") if lane_index % 2 == 0 else Color("#191e26")
		canvas.draw_rect(
			Rect2(LANE_LABEL_WIDTH, lane_y, canvas.size.x - LANE_LABEL_WIDTH, LANE_HEIGHT),
			lane_color
		)
		canvas.draw_line(
			Vector2(0.0, lane_y),
			Vector2(canvas.size.x, lane_y),
			Color("#39424f"),
			1.0
		)
		var lane_label := "Shared"
		var lane_actor := StringName()
		if lane_index > 0 and lane_index - 1 < _lane_actor_ids.size():
			lane_label = _lane_actor_ids[lane_index - 1]
			lane_actor = StringName(lane_label)
		if bool(_locked_lanes.get(lane_actor, false)):
			lane_label += "  [LOCK]"
		if bool(_muted_lanes.get(lane_actor, false)):
			lane_label += "  [MUTE]"
			canvas.draw_rect(
				Rect2(
					LANE_LABEL_WIDTH,
					lane_y,
					canvas.size.x - LANE_LABEL_WIDTH,
					LANE_HEIGHT
				),
				Color(0.04, 0.05, 0.07, 0.52)
			)
		if bool(_solo_lanes.get(lane_actor, false)):
			lane_label += "  [SOLO]"
		canvas.draw_string(
			font,
			Vector2(12.0, lane_y + 34.0),
			lane_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			LANE_LABEL_WIDTH - 20.0,
			13,
			Color("#c7cfda")
		)
	canvas.draw_line(
			Vector2(LANE_LABEL_WIDTH, 0.0),
			Vector2(LANE_LABEL_WIDTH, canvas.size.y),
			Color("#657080"),
			1.0
	)
	_draw_time_ruler(canvas, font)
	if _loop_end_seconds > _loop_start_seconds + 0.00001:
		var loop_start_x := LANE_LABEL_WIDTH + time_to_pixels(_loop_start_seconds)
		var loop_end_x := LANE_LABEL_WIDTH + time_to_pixels(_loop_end_seconds)
		canvas.draw_rect(
			Rect2(
				loop_start_x,
				0.0,
				maxf(loop_end_x - loop_start_x, 1.0),
				canvas.size.y
			),
			Color(0.95, 0.78, 0.35, 0.07 if _loop_enabled else 0.035)
		)
		canvas.draw_line(
			Vector2(loop_start_x, 0.0),
			Vector2(loop_start_x, canvas.size.y),
			Color(0.95, 0.78, 0.35, 0.72),
			1.0
		)
		canvas.draw_line(
			Vector2(loop_end_x, 0.0),
			Vector2(loop_end_x, canvas.size.y),
			Color(0.95, 0.78, 0.35, 0.72),
			1.0
		)
	for beat_index in range(_context.sequence.beats.size()):
		var beat := _context.sequence.beats[beat_index]
		if beat == null:
			continue
		_draw_beat(canvas, font, beat, beat_index)
	var playhead_x := LANE_LABEL_WIDTH + time_to_pixels(_scrub_time)
	canvas.draw_line(
		Vector2(playhead_x, 0.0),
		Vector2(playhead_x, canvas.size.y),
		Color("#f1c75b"),
		2.0
	)
	canvas.draw_colored_polygon(
		PackedVector2Array([
			Vector2(playhead_x - 6.0, 0.0),
			Vector2(playhead_x + 6.0, 0.0),
			Vector2(playhead_x, 8.0),
		]),
		Color("#f1c75b")
	)


func _draw_time_ruler(canvas: Control, font: Font) -> void:
	var tick_step := _ruler_tick_step()
	var duration := maxf(_sequence_duration(), 1.0)
	var tick := 0.0
	while tick <= duration + tick_step:
		var x := LANE_LABEL_WIDTH + time_to_pixels(tick)
		if x > canvas.size.x:
			break
		canvas.draw_line(
			Vector2(x, RULER_HEIGHT - 11.0),
			Vector2(x, RULER_HEIGHT),
			Color("#aab4c2"),
			1.0
		)
		canvas.draw_line(
			Vector2(x, RULER_HEIGHT),
			Vector2(x, canvas.size.y),
			Color(0.35, 0.4, 0.48, 0.24),
			1.0
		)
		canvas.draw_string(
			font,
			Vector2(x + 4.0, 15.0),
			_format_time(tick),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			11,
			Color("#c9d1dd")
		)
		tick += tick_step


func _draw_beat(
	canvas: Control,
	font: Font,
	beat: CutsceneBeat,
	beat_index: int
) -> void:
	var rect := _beat_rect(beat)
	var color: Color = KIND_COLORS.get(
		beat.kind,
		Color("#7e8794")
	)
	if _invalid_beat_indices.has(beat_index):
		color = color.lerp(Color("#d94343"), 0.38)
	canvas.draw_style_box(
		_make_beat_box(color, _selected_beats.has(beat)),
		rect
	)
	var label := _kind_name(beat.kind)
	if beat == _selected_beat:
		label = "● " + label
	var text_width := maxf(rect.size.x - 10.0, 0.0)
	canvas.draw_string(
		font,
		rect.position + Vector2(7.0, 20.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		text_width,
		11,
		Color("#f4f6f8")
	)
	var detail := _beat_detail_label(beat)
	if not detail.is_empty() and rect.size.x >= 60.0:
		canvas.draw_string(
			font,
			rect.position + Vector2(7.0, 35.0),
			_fit_draw_text(font, detail, 10, text_width),
			HORIZONTAL_ALIGNMENT_LEFT,
			text_width,
			10,
			Color("#e7ebf0")
		)
	if _invalid_beat_indices.has(beat_index):
		canvas.draw_line(
			Vector2(rect.position.x, rect.end.y - 2.0),
			Vector2(rect.end.x, rect.end.y - 2.0),
			Color("#ff6c6c"),
			2.0
		)


func _beat_detail_label(beat: CutsceneBeat) -> String:
	match beat.kind:
		CutsceneBeat.Kind.MOVE, CutsceneBeat.Kind.POSE:
			return str(beat.pose) if not beat.pose.is_empty() else ""
		CutsceneBeat.Kind.BOUNCE:
			return "%dx to (%g, %g)" % [
				beat.bounce_count,
				beat.bounce_offset.x,
				beat.bounce_offset.y,
			]
		CutsceneBeat.Kind.STAGE_CUE:
			return str(beat.cue) if not beat.cue.is_empty() else ""
		CutsceneBeat.Kind.DIALOGUE:
			return _dialogue_preview(beat)
		CutsceneBeat.Kind.CAMERA:
			return CutsceneBeat.CameraAction.keys()[beat.camera_action]
		CutsceneBeat.Kind.AUDIO:
			if beat.audio_stream != null:
				return beat.audio_stream.resource_path.get_file()
			return CutsceneBeat.AudioAction.keys()[beat.audio_action]
		CutsceneBeat.Kind.VFX:
			if beat.vfx_scene != null:
				return beat.vfx_scene.resource_path.get_file()
			return CutsceneBeat.VfxAction.keys()[beat.vfx_action]
	return ""


## Returns the opening words a DIALOGUE beat says, prefixed by its speaker.
##
## A row of identical teal boxes reading "DIALOGUE" tells a writer nothing about
## which one holds which exchange. Showing the words makes the timeline readable
## as a script; the label is truncated to the box, so a wider beat shows more.
func _dialogue_preview(beat: CutsceneBeat) -> String:
	if beat.conversation == null:
		return "(no conversation)"
	var lines := beat.conversation.lines
	if lines.is_empty():
		return "(empty conversation)"
	var first := beat.line_range.x
	if first < 0 or first >= lines.size():
		first = 0
	var line: DialogueLine = lines[first]
	if line == null:
		return ""
	var spoken := line.text.strip_edges().replace("\n", " ")
	if spoken.is_empty():
		return "(blank line)"
	if line.speaker_slot.is_empty():
		return spoken
	return "%s: %s" % [line.speaker_slot, spoken]


func _fit_draw_text(
	font: Font,
	text: String,
	font_size: int,
	available_width: float
) -> String:
	if available_width <= 0.0:
		return ""
	if font.get_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	).x <= available_width:
		return text
	var shortened := text
	while shortened.length() > 1:
		shortened = shortened.left(shortened.length() - 1)
		var candidate := shortened + "..."
		if font.get_string_size(
			candidate,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size
		).x <= available_width:
			return candidate
	return ""


func _make_beat_box(color: Color, selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color("#fff0ad") if selected else color.lightened(0.22)
	box.set_border_width_all(2 if selected else 1)
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_left = 4
	box.corner_radius_bottom_right = 4
	return box


func _refresh_validation() -> void:
	_invalid_beat_indices.clear()
	if _validation_list == null:
		return
	_validation_list.clear()
	if not _has_valid_context():
		return
	var errors := _context.sequence.validate(_context.get_stage_actor_ids())
	for error_text in errors:
		_validation_list.add_item(error_text)
		for beat_index in range(_context.sequence.beats.size()):
			if error_text.begins_with("Beat %d:" % (beat_index + 1)):
				_invalid_beat_indices[beat_index] = true
				_validation_list.set_item_metadata(
					_validation_list.item_count - 1,
					beat_index
				)
	if errors.is_empty():
		_validation_list.add_item("No validation errors.")


func _on_validation_selected(item_index: int) -> void:
	if not _has_valid_context() or _validation_list == null:
		return
	var metadata: Variant = _validation_list.get_item_metadata(item_index)
	if metadata == null:
		return
	var beat_index := int(metadata)
	if beat_index < 0 or beat_index >= _context.sequence.beats.size():
		return
	_select_beat(_context.sequence.beats[beat_index])


func _on_context_data_changed() -> void:
	if not _has_valid_context():
		_show_empty_state()
		return
	# Coming back from the empty state, there is nothing to refresh: the empty
	# message replaced the toolbar, canvas and status bar, so every update below
	# would write to controls that no longer exist. Selecting a cutscene that
	# has a timeline has to build the panel, not repaint it.
	if _canvas == null:
		_build_valid_panel()
		return
	_rebuild_lane_data()
	_refresh_validation()
	_update_timeline_size()
	_apply_preview_at_time()
	_update_toolbar_readout()
	_update_playhead_readout()
	if _canvas != null:
		_canvas.queue_redraw()


func _commit_beat_start_changes(
	changes: Dictionary,
	action_name: String
) -> void:
	if changes.is_empty():
		return
	var undo_redo: EditorUndoRedoManager = null
	if _context != null:
		undo_redo = _context.undo_redo
	if undo_redo == null:
		for beat_variant in changes.keys():
			var beat := beat_variant as CutsceneBeat
			if beat != null:
				beat.start_seconds = float(changes[beat_variant])
	else:
		undo_redo.create_action(action_name)
		for beat_variant in changes.keys():
			var beat := beat_variant as CutsceneBeat
			if beat == null:
				continue
			undo_redo.add_do_property(
				beat,
				&"start_seconds",
				float(changes[beat_variant])
			)
			undo_redo.add_undo_property(
				beat,
				&"start_seconds",
				beat.start_seconds
			)
		undo_redo.commit_action()
	if _context != null:
		_context.notify_authored_data_changed()
	_rebuild_lane_data()
	_refresh_validation()
	_update_timeline_size()
	if _canvas != null:
		_canvas.queue_redraw()


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
			var change_variant: Variant = changes[property_name]
			var after_value: Variant = change_variant
			if change_variant is Dictionary and change_variant.has("after"):
				after_value = change_variant["after"]
			target.set(property_name, after_value)
	else:
		undo_redo.create_action(action_name)
		for property_name in changes.keys():
			var change_variant: Variant = changes[property_name]
			var before_value: Variant = target.get(property_name)
			var after_value: Variant = change_variant
			if change_variant is Dictionary and change_variant.has("after"):
				after_value = change_variant["after"]
				before_value = change_variant.get("before", before_value)
			undo_redo.add_do_property(target, property_name, after_value)
			undo_redo.add_undo_property(target, property_name, before_value)
		undo_redo.commit_action()
	if _context != null:
		_context.notify_authored_data_changed()


func _update_toolbar_readout() -> void:
	if _time_label == null or _duration_label == null:
		return
	_time_label.text = _format_time(_scrub_time)
	_duration_label.text = "/ %s" % _format_time(_sequence_duration())


func _update_playhead_readout() -> void:
	if _playhead_readout == null:
		return
	if not _has_valid_context():
		_playhead_readout.text = "Playhead: no cutscene"
		return
	_begin_preview_evaluation()
	var result := _preview_player.evaluate_at(
		_context.sequence,
		_scrub_time
	)
	var actor_states: Dictionary = result.get(&"actors", {})
	var stage_cue_text := str(result.get(&"stage_cue", StringName()))
	if stage_cue_text.is_empty():
		stage_cue_text = "none"
	var entries := PackedStringArray()
	for actor_id_text in _lane_actor_ids:
		var actor_id := StringName(actor_id_text)
		var state: Dictionary = actor_states.get(actor_id, {})
		var pose_text := str(state.get(&"pose", StringName()))
		if pose_text.is_empty():
			pose_text = "none"
		entries.append(
			"%s: pose %s, anim %s" % [
				actor_id_text,
				pose_text,
				stage_cue_text,
			]
		)
	if entries.is_empty():
		_playhead_readout.text = "At %s | no actors" % _format_time(_scrub_time)
		return
	_playhead_readout.text = "At %s | %s" % [
		_format_time(_scrub_time),
		" | ".join(entries),
	]
	_playhead_readout.tooltip_text = _playhead_readout.text


func _sequence_duration() -> float:
	return _context.sequence.get_duration_seconds() if _has_valid_context() else 0.0


func _resolved_zoom(requested_zoom: float) -> float:
	return _pixels_per_second if requested_zoom <= 0.0 else maxf(requested_zoom, 0.001)


func _ruler_tick_step() -> float:
	var target_seconds := 64.0 / maxf(_pixels_per_second, 0.001)
	var exponent := floorf(log(target_seconds) / log(10.0))
	var base := pow(10.0, exponent)
	for multiplier in [1.0, 2.0, 5.0, 10.0]:
		var candidate: float = base * float(multiplier)
		if candidate >= target_seconds:
			return candidate
	return base * 10.0


func _format_time(seconds: float) -> String:
	return "%0.2f s" % maxf(seconds, 0.0)


func _kind_name(kind: int) -> String:
	if kind < 0 or kind >= CutsceneBeat.Kind.size():
		return "UNKNOWN"
	return CutsceneBeat.Kind.keys()[kind]


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


func _default_duration_for_kind(kind: int) -> float:
	return 1.0 if kind in [
		CutsceneBeat.Kind.MOVE,
		CutsceneBeat.Kind.POSE,
		CutsceneBeat.Kind.BOUNCE,
		CutsceneBeat.Kind.WAIT,
		CutsceneBeat.Kind.DIALOGUE,
		CutsceneBeat.Kind.CAMERA,
	] else 0.0


func _event_bypasses_grid(_event: InputEvent) -> bool:
	return Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)
