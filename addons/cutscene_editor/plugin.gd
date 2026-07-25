@tool
extends EditorPlugin

## How it works:
## - Hosts the cutscene editor: a bottom panel of Sculpt, Cast and Timeline
##   tabs, and the 2D viewport interaction that turns a drag into terrain.
## - Rebuilds one CutsceneEditorContext per opened scene and hands the same
##   instance to every panel, so no panel hunts the tree for what is being
##   edited.
## - While the sculpt tool is armed it claims viewport clicks and strokes the
##   brush along the drag; otherwise selection and marker dragging behave
##   normally. It draws the brush, the room's bounds, and the landing line over
##   the viewport so a designer aims at something.
## - It writes no terrain itself. Strokes go through CutsceneSculptBrush onto
##   the encounter's room resource, and the preview redraws from that.
## The invariant is that arming a tool is the only thing that changes viewport
## behaviour; switch it off and the editor is exactly as it was.

const ROOM_BOUNDS_COLOR := Color(0.45, 0.75, 1.0, 0.5)
const BRUSH_COLOR := Color(1.0, 0.85, 0.3, 0.9)
const LANDING_COLOR := Color(0.4, 1.0, 0.5, 0.75)
const BLOCKED_LANDING_COLOR := Color(1.0, 0.4, 0.35, 0.9)
## Healing claims the rock the designer aimed at, not a marker several hundred
## pixels away, so it only reaches within roughly one opening.
const _HEAL_RADIUS_PIXELS: float = 96.0

const PREVIEW_HARNESS_SCENE := "res://Scenes/cinematics/cinematic_preview.tscn"

var _dock: VBoxContainer
var _playtest_button: Button
var _sculpt_panel: CutsceneSculptPanel
var _cast_panel: CutsceneCastPanel
var _timeline_panel: CutsceneTimelinePanel
var _beat_inspector: CutsceneBeatInspector
var _context := CutsceneEditorContext.new()
var _is_stroking: bool = false
var _last_stroke_local := Vector2.ZERO
var _stroke_before: CutsceneTerrainSculpt
var _hover_local := Vector2.ZERO
var _has_hover: bool = false
var _stroke_origin_local := Vector2.ZERO
# Outline segments cached in scene space; see _rebuild_layer_outline.
var _outline_points := PackedVector2Array()


func _enter_tree() -> void:
	_sculpt_panel = CutsceneSculptPanel.new()
	_cast_panel = CutsceneCastPanel.new()
	_timeline_panel = CutsceneTimelinePanel.new()
	_beat_inspector = CutsceneBeatInspector.new()

	var timeline_tab := HSplitContainer.new()
	timeline_tab.name = "Timeline"
	timeline_tab.add_child(_timeline_panel)
	timeline_tab.add_child(_beat_inspector)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(_sculpt_panel)
	tabs.add_child(_cast_panel)
	tabs.add_child(timeline_tab)

	_playtest_button = Button.new()
	_playtest_button.text = "Playtest this cutscene"
	_playtest_button.tooltip_text = (
		"Runs the real game and breaks into this encounter's ceiling, so the "
		+ "miner falls into the room exactly as a player reaches it."
	)
	_playtest_button.pressed.connect(_on_playtest_pressed)
	var toolbar := HBoxContainer.new()
	toolbar.add_child(_playtest_button)

	# The panel scrolls rather than growing. Godot sizes a bottom panel to its
	# content, so a tall stack of controls pushed the 2D viewport down to a
	# strip — and this is a tool you use by looking at the viewport.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 190.0
	scroll.add_child(tabs)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_dock = VBoxContainer.new()
	_dock.name = "Cutscene"
	_dock.custom_minimum_size.y = 220.0
	_dock.add_child(toolbar)
	_dock.add_child(scroll)
	add_control_to_bottom_panel(_dock, "Cutscene")

	_sculpt_panel.armed_changed.connect(_on_armed_changed)
	_sculpt_panel.brush_settings_changed.connect(_on_brush_settings_changed)
	_timeline_panel.beat_selected.connect(_on_beat_selected)
	_timeline_panel.scrub_time_changed.connect(_on_scrub_time_changed)
	_context.authored_data_changed.connect(_on_authored_data_changed)
	scene_changed.connect(_on_scene_changed)
	_on_scene_changed(EditorInterface.get_edited_scene_root())


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null


## Claims the 2D viewport for cutscene stages. Without this Godot never calls
## the input or overlay hooks at all, whatever they contain.
func _handles(_object: Object) -> bool:
	return _find_preview() != null


func _on_scene_changed(_scene_root: Node) -> void:
	_rebuild_context()


## Rereads the open scene into the one context every panel shares.
func _rebuild_context() -> void:
	var preview := _find_preview()
	_context.scene_root = EditorInterface.get_edited_scene_root()
	_context.preview = preview
	_context.stage = (
		preview.get_parent() as Node2D if preview != null else null
	)
	_context.encounter = preview.get_encounter() if preview != null else null
	_context.sculpt = preview.get_sculpt() if preview != null else null
	_context.sequence = (
		_context.encounter.sequence if _context.encounter != null else null
	)
	_context.undo_redo = get_undo_redo()
	if _context.sequence == null and _context.stage != null:
		# A stage may carry its own timeline without an encounter behind it,
		# which is how a sequence is authored before it is scheduled.
		var stage_sequence: Variant = _context.stage.get(&"sequence")
		if stage_sequence is CutsceneSequence:
			_context.sequence = stage_sequence
	_sculpt_panel.set_context(_context)
	_cast_panel.set_context(_context)
	_timeline_panel.set_context(_context)
	_beat_inspector.set_context(_context)
	_rebuild_layer_outline()
	update_overlays()


func _on_authored_data_changed() -> void:
	if _context.preview != null:
		_context.preview.build_preview()
	_sculpt_panel.refresh()
	_rebuild_layer_outline()
	update_overlays()


func _on_armed_changed(_is_armed: bool) -> void:
	update_overlays()


func _on_brush_settings_changed() -> void:
	# The outline follows the selected stratum, so changing what the brush cuts
	# changes what is traced.
	_rebuild_layer_outline()
	update_overlays()


func _on_beat_selected(beat: CutsceneBeat) -> void:
	_beat_inspector.show_beat(beat)


## Places the cast where the sequence says they are at one instant, so
## dragging the playhead moves the stand-ins a designer positioned.
func _on_scrub_time_changed(seconds: float) -> void:
	if _context.sequence == null or not _context.is_valid():
		return
	var player := CutsceneSequencePlayer.new()
	player.bind(
		_context.get_actor_preview,
		_context.get_marker_position,
		Callable(),
		null
	)
	var states: Dictionary = player.evaluate_at(_context.sequence, seconds)
	for actor_id: StringName in states:
		var actor := _context.get_actor_preview(actor_id)
		if actor == null:
			continue
		var state: Dictionary = states[actor_id]
		if state.has("position"):
			actor.global_position = state["position"]
		if state.has("visible"):
			actor.visible = bool(state["visible"])
	player.free()
	update_overlays()


## Saves the room, names the encounter for the harness, and runs the real
## game. The harness crosses that encounter's actual ceiling rather than
## opening the cutscene directly, so a room that cannot be fallen into fails
## here exactly as it would fail in a run.
func _on_playtest_pressed() -> void:
	if _context.encounter == null:
		_playtest_button.text = "Pick an encounter first"
		return
	_playtest_button.text = "Playtest this cutscene"
	if _context.sculpt != null and not _context.sculpt.resource_path.is_empty():
		ResourceSaver.save(_context.sculpt, _context.sculpt.resource_path)
	var target := FileAccess.open(
		CinematicPreviewHarness.PLAYTEST_TARGET_PATH,
		FileAccess.WRITE
	)
	if target == null:
		_playtest_button.text = "Could not write the playtest target"
		return
	target.store_string(String(_context.encounter.encounter_id))
	target.close()
	EditorInterface.play_custom_scene(PREVIEW_HARNESS_SCENE)


## Sculpts along the drag while the tool is armed, and otherwise gets out of
## the way so ordinary selection keeps working.
func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _sculpt_panel.is_armed():
		return false
	var preview := _context.preview
	if preview == null or _context.sculpt == null:
		return false

	var motion := event as InputEventMouseMotion
	if motion != null:
		_hover_local = preview.global_position_to_sculpt_local(
			_to_world_position(motion.position)
		)
		_has_hover = true
		update_overlays()
		if _is_stroking:
			# Shift locks the stroke to the axis it started along, which is how
			# a flat floor or a straight wall gets cut without a steady hand.
			_stroke_to(
				_constrain_stroke(_hover_local, motion.shift_pressed),
				motion.alt_pressed
			)
			return true
		return false

	var button := event as InputEventMouseButton
	if button == null:
		return false
	# The wheel is the fastest control in any painting tool, so it resizes the
	# brush; with Ctrl it steps between strata instead, because choosing which
	# rock you are cutting is the other thing done constantly mid-stroke.
	if (
		button.pressed
		and (
			button.button_index == MOUSE_BUTTON_WHEEL_UP
			or button.button_index == MOUSE_BUTTON_WHEEL_DOWN
		)
	):
		var step := (
			1
			if button.button_index == MOUSE_BUTTON_WHEEL_UP
			else -1
		)
		if button.ctrl_pressed:
			_sculpt_panel.step_focused_layer(step)
		else:
			_sculpt_panel.step_brush_size(step)
		update_overlays()
		return true
	if button.button_index != MOUSE_BUTTON_LEFT:
		return false
	var local_cell := preview.global_position_to_sculpt_local(
		_to_world_position(button.position)
	)
	if _sculpt_panel.get_operation() == CutsceneSculptPanel.OP_DIG_HIT:
		if button.pressed:
			_dig_hit(_to_world_position(button.position), button.alt_pressed)
		return true
	if button.pressed:
		_begin_stroke(local_cell, button.alt_pressed)
		return true
	_end_stroke()
	return true


## Adds or removes one authored impact marker, the mined-hit workflow the
## preview already owns. Alt heals, so the same click both breaks and mends.
func _dig_hit(world_position: Vector2, heal: bool) -> void:
	var preview := _context.preview
	var undo_redo := get_undo_redo()
	if heal:
		if preview.heal_nearest_impact(world_position, _HEAL_RADIUS_PIXELS):
			undo_redo.create_action("Heal cutscene terrain")
			undo_redo.commit_action(false)
		return
	if preview.dig_at_world_position(world_position):
		undo_redo.create_action("Dig cutscene terrain")
		undo_redo.commit_action(false)


## Locks a held stroke to the axis it has travelled furthest along. The axis is
## chosen from the whole stroke rather than the last mouse move, so a wobble
## near the start cannot flip a long straight cut halfway through.
func _constrain_stroke(local_cell: Vector2, constrain: bool) -> Vector2:
	if not constrain:
		return local_cell
	var travel := local_cell - _stroke_origin_local
	if absf(travel.x) >= absf(travel.y):
		return Vector2(local_cell.x, _stroke_origin_local.y)
	return Vector2(_stroke_origin_local.x, local_cell.y)


func _begin_stroke(local_cell: Vector2, invert: bool) -> void:
	_stroke_before = CutsceneTerrainSculpt.new()
	_stroke_before.copy_shape_from(_context.sculpt)
	_stroke_origin_local = local_cell
	_is_stroking = true
	_last_stroke_local = local_cell
	_apply_operation(local_cell, local_cell, invert)


func _stroke_to(local_cell: Vector2, invert: bool) -> void:
	_apply_operation(_last_stroke_local, local_cell, invert)
	_last_stroke_local = local_cell


## Ends the drag as one undo entry. Recording per mouse-move would make a
## single stroke take dozens of presses of Ctrl+Z to take back.
func _end_stroke() -> void:
	if not _is_stroking:
		return
	_is_stroking = false
	var sculpt := _context.sculpt
	var after := CutsceneTerrainSculpt.new()
	after.copy_shape_from(sculpt)
	var undo_redo := get_undo_redo()
	undo_redo.create_action("Sculpt cutscene room")
	undo_redo.add_do_method(sculpt, &"copy_shape_from", after)
	undo_redo.add_undo_method(sculpt, &"copy_shape_from", _stroke_before)
	undo_redo.commit_action(false)
	_stroke_before = null
	if not sculpt.resource_path.is_empty():
		ResourceSaver.save(sculpt, sculpt.resource_path)
	_sculpt_panel.refresh()
	_rebuild_layer_outline()
	update_overlays()


## Applies one segment of the stroke. Alt swaps carve and fill, which is the
## fastest way to correct an overshoot without leaving the drag.
func _apply_operation(
	from_local: Vector2,
	to_local: Vector2,
	invert: bool
) -> void:
	var operation := _sculpt_panel.get_operation()
	if invert:
		if operation == CutsceneSculptBrush.OP_CARVE:
			operation = CutsceneSculptBrush.OP_FILL
		elif operation == CutsceneSculptBrush.OP_FILL:
			operation = CutsceneSculptBrush.OP_CARVE
	_sculpt_panel.get_brush().stamp_line(
		_context.sculpt,
		from_local,
		to_local,
		operation
	)


## Draws the room's bounds, the brush, and where a falling miner lands.
func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	var preview := _context.preview
	var sculpt := _context.sculpt
	if preview == null or sculpt == null:
		return
	var transform := _get_viewport_transform()
	_draw_room_bounds(overlay, preview, sculpt, transform)
	_draw_layer_outline(overlay, transform)
	_draw_landing_line(overlay, preview, sculpt, transform)
	if _sculpt_panel.is_armed():
		_draw_readout(overlay)
		if _has_hover:
			_draw_brush(overlay, preview, transform)


func _draw_room_bounds(
	overlay: Control,
	preview: CinematicTerrainPreview,
	sculpt: CutsceneTerrainSculpt,
	transform: Transform2D
) -> void:
	var top_left := transform * preview.sculpt_local_to_global_position(
		Vector2.ZERO
	)
	var bottom_right := transform * preview.sculpt_local_to_global_position(
		Vector2(sculpt.grid_size)
	)
	overlay.draw_rect(
		Rect2(top_left, bottom_right - top_left),
		ROOM_BOUNDS_COLOR,
		false,
		2.0
	)


## Draws the row the miner would first touch in each column he can arrive
## down. A designer carving a room needs to see the landing move as they cut,
## not discover it by playing to the encounter.
func _draw_landing_line(
	overlay: Control,
	preview: CinematicTerrainPreview,
	sculpt: CutsceneTerrainSculpt,
	transform: Transform2D
) -> void:
	var config: MiningConfig = preview.terrain_manager.config
	var landing_rows := sculpt.get_landing_local_rows(
		config.snake_half_span_cells
	)
	if landing_rows.is_empty():
		return
	var first_local_x := sculpt.get_landing_first_local_x(
		config.snake_half_span_cells
	)
	var floor_row := sculpt.get_floor_local_row()
	for column_index in range(landing_rows.size()):
		var landing_row := landing_rows[column_index]
		var local_x := float(first_local_x + column_index)
		var is_blocked := landing_row < 0 or landing_row < floor_row
		var drawn_row := float(floor_row if landing_row < 0 else landing_row)
		var left := transform * preview.sculpt_local_to_global_position(
			Vector2(local_x, drawn_row)
		)
		var right := transform * preview.sculpt_local_to_global_position(
			Vector2(local_x + 1.0, drawn_row)
		)
		overlay.draw_line(
			left,
			right,
			BLOCKED_LANDING_COLOR if is_blocked else LANDING_COLOR,
			3.0
		)


func _draw_brush(
	overlay: Control,
	preview: CinematicTerrainPreview,
	transform: Transform2D
) -> void:
	var center := transform * preview.sculpt_local_to_global_position(
		_hover_local
	)
	var edge := transform * preview.sculpt_local_to_global_position(
		_hover_local + Vector2(_sculpt_panel.get_brush().radius_cells, 0.0)
	)
	# The ring carries the selected stratum's colour, so what the brush will
	# cut is answered by looking at the cursor rather than at the panel.
	var brush_color: Color = _sculpt_panel.get_active_layer_color()
	overlay.draw_arc(
		center,
		center.distance_to(edge),
		0.0,
		TAU,
		48,
		brush_color,
		2.0
	)
	overlay.draw_arc(center, 2.0, 0.0, TAU, 8, brush_color, 2.0)


## Traces the selected stratum's solid/open boundary. The segments are cached
## in scene space and rebuilt only when the room or the selection changes: a
## 140x120 room is nearly seventeen thousand cells, and walking it on every
## mouse-move frame would stall the viewport.
func _draw_layer_outline(overlay: Control, transform: Transform2D) -> void:
	if _outline_points.size() < 2:
		return
	var color: Color = _sculpt_panel.get_active_layer_color()
	color.a = 0.85
	var screen_points := PackedVector2Array()
	screen_points.resize(_outline_points.size())
	for point_index in range(_outline_points.size()):
		screen_points[point_index] = transform * _outline_points[point_index]
	overlay.draw_multiline(screen_points, color, 1.0)


func _rebuild_layer_outline() -> void:
	_outline_points = PackedVector2Array()
	var preview := _context.preview
	var sculpt := _context.sculpt
	if preview == null or sculpt == null:
		return
	var layer_index: int = _sculpt_panel.get_outlined_layer()
	for local_y in range(sculpt.grid_size.y):
		for local_x in range(sculpt.grid_size.x):
			var cell := Vector2i(local_x, local_y)
			if not _is_outlined_solid(sculpt, layer_index, cell):
				continue
			# Only the sides facing open air are drawn, so the result is the
			# silhouette of the rock rather than a grid over it.
			if not _is_outlined_solid(
				sculpt, layer_index, cell + Vector2i.RIGHT
			):
				_append_outline_edge(
					preview,
					Vector2(local_x + 1, local_y),
					Vector2(local_x + 1, local_y + 1)
				)
			if not _is_outlined_solid(
				sculpt, layer_index, cell + Vector2i.LEFT
			):
				_append_outline_edge(
					preview,
					Vector2(local_x, local_y),
					Vector2(local_x, local_y + 1)
				)
			if not _is_outlined_solid(
				sculpt, layer_index, cell + Vector2i.DOWN
			):
				_append_outline_edge(
					preview,
					Vector2(local_x, local_y + 1),
					Vector2(local_x + 1, local_y + 1)
				)
			if not _is_outlined_solid(sculpt, layer_index, cell + Vector2i.UP):
				_append_outline_edge(
					preview,
					Vector2(local_x, local_y),
					Vector2(local_x + 1, local_y)
				)


func _is_outlined_solid(
	sculpt: CutsceneTerrainSculpt,
	layer_index: int,
	cell: Vector2i
) -> bool:
	if layer_index < 0:
		return sculpt.is_solid_local(cell)
	return sculpt.is_layer_solid_local(layer_index, cell)


func _append_outline_edge(
	preview: CinematicTerrainPreview,
	from_local: Vector2,
	to_local: Vector2
) -> void:
	_outline_points.append(preview.sculpt_local_to_global_position(from_local))
	_outline_points.append(preview.sculpt_local_to_global_position(to_local))


## States the tool, its size and what it is cutting, on the canvas where the
## work is happening, and lists the modifiers. A tool whose modifiers are only
## documented elsewhere may as well not have them.
func _draw_readout(overlay: Control) -> void:
	var font := overlay.get_theme_default_font()
	if font == null:
		return
	var brush := _sculpt_panel.get_brush()
	var layer_index: int = _sculpt_panel.get_outlined_layer()
	var headline := "%s  ·  size %.0f  ·  %s" % [
		_sculpt_panel.get_operation_label(),
		brush.radius_cells,
		(
			"shape"
			if layer_index < 0
			else "stratum %d" % (layer_index + 1)
		),
	]
	var origin := Vector2(12.0, 22.0)
	overlay.draw_string(
		font, origin + Vector2.ONE, headline, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 14, Color(0.0, 0.0, 0.0, 0.7)
	)
	overlay.draw_string(
		font, origin, headline, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 14, _sculpt_panel.get_active_layer_color()
	)
	var hint := (
		"wheel size  ·  ctrl+wheel layer  ·  shift straight  ·  alt invert"
	)
	overlay.draw_string(
		font, origin + Vector2(0.0, 18.0), hint, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 12, Color(0.82, 0.86, 0.92, 0.75)
	)


## The 2D editor reports clicks in its own control space; the viewport's canvas
## transform is the only thing that knows the current pan and zoom.
func _to_world_position(event_position: Vector2) -> Vector2:
	return _get_viewport_transform().affine_inverse() * event_position


func _get_viewport_transform() -> Transform2D:
	var editor_viewport := EditorInterface.get_editor_viewport_2d()
	if editor_viewport == null:
		return Transform2D.IDENTITY
	return editor_viewport.global_canvas_transform


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
