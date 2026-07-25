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

const RULER_HEIGHT: float = 34.0
const LANE_LABEL_WIDTH: float = 140.0
const LANE_HEIGHT: float = 58.0
const MIN_BEAT_WIDTH: float = 20.0
const EDGE_HOT_ZONE: float = 7.0
const MIN_PIXELS_PER_SECOND: float = 20.0
const MAX_PIXELS_PER_SECOND: float = 240.0
const DEFAULT_PIXELS_PER_SECOND: float = 80.0
const DEFAULT_GRID_SECONDS: float = 0.1

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
		set_process_input(true)

	func _draw() -> void:
		if _draw_handler.is_valid():
			_draw_handler.call(self)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var motion := event as InputEventMouseMotion
			_update_cursor(motion.position)
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
var _toolbar: HBoxContainer
var _status_bar: HBoxContainer
var _playhead_readout: Label
var _legend: HBoxContainer
var _kind_option: OptionButton
var _actor_option: OptionButton
var _zoom_spin: SpinBox
var _grid_spin: SpinBox
var _play_button: Button
var _time_label: Label
var _duration_label: Label
var _validation_list: ItemList
var _empty_message: Label

var _lane_actor_ids: PackedStringArray = PackedStringArray()
var _invalid_beat_indices: Dictionary = {}
var _selected_beat: CutsceneBeat
var _selected_kind: int = CutsceneBeat.Kind.MOVE
var _pixels_per_second: float = DEFAULT_PIXELS_PER_SECOND
var _grid_seconds: float = DEFAULT_GRID_SECONDS
var _scrub_time: float = 0.0
var _is_playing: bool = false

var _drag_mode: StringName = &""
var _drag_beat: CutsceneBeat
var _drag_original_start: float = 0.0
var _drag_original_duration: float = 0.0
var _drag_original_actor: StringName
var _drag_pointer_offset_seconds: float = 0.0
var _drag_preview_start: float = 0.0
var _drag_preview_duration: float = 0.0
var _drag_preview_actor: StringName

var _preview_player: CutsceneSequencePlayer
var _preview_base_states: Dictionary = {}


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
	var next_time := minf(_scrub_time + maxf(delta, 0.0), duration)
	_set_scrub_time(next_time, true)
	if is_equal_approx(next_time, duration):
		_set_playing(false)


## Rebuilds the panel for the supplied scene context.
func set_context(context: CutsceneEditorContext) -> void:
	_restore_preview_states()
	_stop_drag_without_commit()
	if _context != null and _context.authored_data_changed.is_connected(
		_on_context_data_changed
	):
		_context.authored_data_changed.disconnect(_on_context_data_changed)
	_context = context
	_selected_beat = null
	_scrub_time = 0.0
	_set_playing(false)
	_preview_base_states.clear()
	if not _has_valid_context():
		_show_empty_state()
		return
	if not _context.authored_data_changed.is_connected(_on_context_data_changed):
		_context.authored_data_changed.connect(_on_context_data_changed)
	_build_valid_panel()


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
	var scroll := ScrollContainer.new()
	scroll.name = "TimelineScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, 190.0)
	scroll.add_child(_canvas)
	add_child(scroll)
	_validation_list = ItemList.new()
	_validation_list.name = "ValidationMessages"
	_validation_list.select_mode = ItemList.SELECT_MULTI
	_validation_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_validation_list.custom_minimum_size = Vector2(0.0, 64.0)
	add_child(_validation_list)
	_rebuild_lane_data()
	_capture_preview_states()
	_refresh_validation()
	_update_timeline_size()
	_update_toolbar_readout()
	_update_playhead_readout()
	set_process(true)


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "TimelineToolbar"
	_toolbar.custom_minimum_size = Vector2(0.0, 34.0)
	add_child(_toolbar)

	var add_label := Label.new()
	add_label.text = "Add"
	_toolbar.add_child(add_label)
	_kind_option = OptionButton.new()
	_kind_option.name = "BeatKind"
	_kind_option.custom_minimum_size = Vector2(112.0, 0.0)
	for kind in range(CutsceneBeat.Kind.size()):
		_kind_option.add_item(_kind_name(kind))
	_toolbar.add_child(_kind_option)
	if not _kind_option.item_selected.is_connected(_on_kind_selected):
		_kind_option.item_selected.connect(_on_kind_selected)

	_actor_option = OptionButton.new()
	_actor_option.name = "BeatActor"
	_actor_option.custom_minimum_size = Vector2(130.0, 0.0)
	_populate_actor_option()
	_toolbar.add_child(_actor_option)
	if not _actor_option.item_selected.is_connected(_on_actor_selected):
		_actor_option.item_selected.connect(_on_actor_selected)

	var add_button := Button.new()
	add_button.text = "+ Beat"
	add_button.tooltip_text = "Add a beat at the current playhead time."
	_toolbar.add_child(add_button)
	if not add_button.pressed.is_connected(_add_beat):
		add_button.pressed.connect(_add_beat)

	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.tooltip_text = "Delete the selected beat."
	_toolbar.add_child(delete_button)
	if not delete_button.pressed.is_connected(_delete_selected):
		delete_button.pressed.connect(_delete_selected)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_toolbar.add_child(_zoom_spin)
	if not _zoom_spin.value_changed.is_connected(_on_zoom_changed):
		_zoom_spin.value_changed.connect(_on_zoom_changed)

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
	_toolbar.add_child(_grid_spin)
	if not _grid_spin.value_changed.is_connected(_on_grid_changed):
		_grid_spin.value_changed.connect(_on_grid_changed)

	_play_button = Button.new()
	_play_button.name = "PlayPause"
	_play_button.text = "Play"
	_play_button.toggle_mode = true
	_play_button.custom_minimum_size = Vector2(72.0, 0.0)
	_toolbar.add_child(_play_button)
	if not _play_button.toggled.is_connected(_on_play_toggled):
		_play_button.toggled.connect(_on_play_toggled)

	_time_label = Label.new()
	_time_label.name = "CurrentTime"
	_time_label.custom_minimum_size = Vector2(72.0, 0.0)
	_toolbar.add_child(_time_label)
	_duration_label = Label.new()
	_duration_label.name = "TotalDuration"
	_duration_label.custom_minimum_size = Vector2(82.0, 0.0)
	_toolbar.add_child(_duration_label)
	_update_actor_option_state()


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
	# The actor choice is read when the next beat is added.
	pass


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


func _add_beat() -> void:
	if not _has_valid_context():
		return
	var beat := CutsceneBeat.new()
	beat.kind = _selected_kind
	beat.start_seconds = snap_time(_scrub_time)
	beat.duration_seconds = _default_duration_for_kind(_selected_kind)
	if _kind_uses_actor(_selected_kind) and _actor_option.item_count > 0:
		var selected_index := _actor_option.selected
		if selected_index < 0:
			selected_index = 0
		beat.actor = _actor_option.get_item_metadata(selected_index)
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
	_selected_beat = beat
	beat_selected.emit(beat)
	_rebuild_lane_data()
	_refresh_validation()
	_update_timeline_size()
	if _canvas != null:
		_canvas.queue_redraw()


func _delete_selected() -> void:
	if not _has_valid_context() or _selected_beat == null:
		return
	var next_beats: Array[CutsceneBeat] = []
	var found := false
	for existing in _context.sequence.beats:
		if existing == _selected_beat:
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
	_selected_beat = null
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
		&"press":
			if position.y < RULER_HEIGHT and position.x >= LANE_LABEL_WIDTH:
				_begin_scrub(pixels_to_time(position.x - LANE_LABEL_WIDTH))
				return true
			var hit := _hit_test_beat(position)
			if hit.is_empty():
				return false
			var beat := hit["beat"] as CutsceneBeat
			_select_beat(beat)
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
	if not resize:
		var pointer_time := pixels_to_time(
			position.x - LANE_LABEL_WIDTH
		)
		_drag_pointer_offset_seconds = pointer_time - _drag_original_start


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
			snapped_right_edge
		)
	else:
		var pointer_time := pixels_to_time(
			position.x - LANE_LABEL_WIDTH
		)
		var proposed_start := pointer_time - _drag_pointer_offset_seconds
		_drag_preview_start = snap_time(
			proposed_start,
			_grid_seconds,
			bypass_grid
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
	_rebuild_lane_data()
	_refresh_validation()
	_update_timeline_size()
	if _canvas != null:
		_canvas.queue_redraw()


func _stop_drag_without_commit() -> void:
	_drag_mode = &""
	_drag_beat = null
	if _canvas != null:
		_canvas.queue_redraw()


func _select_beat(beat: CutsceneBeat) -> void:
	_selected_beat = beat
	beat_selected.emit(beat)
	if _canvas != null:
		_canvas.queue_redraw()


func _begin_preview_evaluation() -> void:
	if _preview_player == null:
		_preview_player = CutsceneSequencePlayer.new()
	_preview_player.bind(
		Callable(self, "_resolve_preview_actor"),
		Callable(self, "_resolve_preview_marker"),
		Callable(),
		null
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
	for actor_id_text in _context.get_stage_actor_ids():
		var actor_id := StringName(actor_id_text)
		if not actor_states.has(actor_id):
			continue
		var preview := _context.get_actor_preview(actor_id) as Node2D
		if not is_instance_valid(preview):
			continue
		var state: Dictionary = actor_states[actor_id]
		if state.has(&"position"):
			preview.global_position = state[&"position"]
		if state.has(&"visible"):
			preview.visible = bool(state[&"visible"])
		if state.has(&"facing") and preview.has_method(&"set_facing_direction"):
			preview.call(&"set_facing_direction", int(state[&"facing"]))
		if state.has(&"pose"):
			var pose: StringName = state[&"pose"]
			preview.pose = pose


func _capture_preview_states() -> void:
	_preview_base_states.clear()
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
		}


func _restore_preview_states() -> void:
	if _context == null:
		return
	for actor_id_variant in _preview_base_states.keys():
		var actor_id := StringName(actor_id_variant)
		var preview := _context.get_actor_preview(actor_id) as Node2D
		if not is_instance_valid(preview):
			continue
		var base_state: Dictionary = _preview_base_states[actor_id_variant]
		preview.global_position = base_state["position"]
		preview.scale = base_state["scale"]
		preview.pose = base_state["pose"]
		preview.visible = bool(base_state["visible"])


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
		if lane_index > 0 and lane_index - 1 < _lane_actor_ids.size():
			lane_label = _lane_actor_ids[lane_index - 1]
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
		_make_beat_box(color, beat == _selected_beat),
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
		CutsceneBeat.Kind.STAGE_CUE:
			return str(beat.cue) if not beat.cue.is_empty() else ""
	return ""


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
	if errors.is_empty():
		_validation_list.add_item("No validation errors.")


func _on_context_data_changed() -> void:
	if not _has_valid_context():
		_show_empty_state()
		return
	_rebuild_lane_data()
	_refresh_validation()
	_update_timeline_size()
	_apply_preview_at_time()
	_update_toolbar_readout()
	_update_playhead_readout()
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
	]


func _default_duration_for_kind(kind: int) -> float:
	return 1.0 if kind in [
		CutsceneBeat.Kind.MOVE,
		CutsceneBeat.Kind.POSE,
		CutsceneBeat.Kind.WAIT,
		CutsceneBeat.Kind.DIALOGUE,
	] else 0.0


func _event_bypasses_grid(_event: InputEvent) -> bool:
	return Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)
