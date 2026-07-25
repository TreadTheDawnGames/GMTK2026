@tool
extends EditorPlugin

## How it works:
## - Hosts the cutscene editor: a bottom panel of Overview, Sculpt, Cast and
##   Timeline tabs, and the 2D viewport interaction that turns a drag into
##   terrain. Overview leads, because which of the run's cutscenes are authored
##   is the first thing worth knowing.
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
var _manager_panel: CutsceneManagerPanel
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
## The beat the timeline has selected, so the viewport can draw its walk.
var _selected_beat: CutsceneBeat
## Which end of the selected walk is being dragged: "start", "target", or empty
## for none.
var _dragging_handle: StringName = &""
## The offset that end had when the drag began. Captured because the beat is
## written live during the drag, so by release it no longer remembers what undo
## has to put back.
var _move_offset_before_drag := Vector2.ZERO
## Colours for the selected walk: the line it travels and the handle that ends
## it. Green reads as "this is the path", matching the landing line's language.
const MOVE_PATH_COLOR := Color(0.45, 0.9, 1.0, 0.85)
const MOVE_HANDLE_COLOR := Color(1.0, 0.85, 0.3, 0.95)
## How near the pointer has to be, in screen pixels, to grab the walk's end.
const _MOVE_HANDLE_GRAB_PIXELS: float = 14.0
# Outline segments cached in scene space; see _rebuild_layer_outline.
var _outline_points := PackedVector2Array()


func _enter_tree() -> void:
	_manager_panel = CutsceneManagerPanel.new()
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
	# The overview comes first: a designer opening this panel wants to know
	# which of the run's cutscenes are authored before working on one of them.
	tabs.add_child(_manager_panel)
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
	_context.cast_changed.connect(_on_cast_changed)
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
	# Deferred because on scene_changed the stage's terrain preview has not
	# resolved its mining config yet, and cast placement reads it.
	_auto_populate_cast.call_deferred()


## Places the encounter's own cast and the miner the moment a stage is opened.
## Seeing who is in the room is the reason to open one, and a designer should
## not have to know that the cast exists behind two buttons on another tab.
##
## Both calls skip anything already in the scene, so reopening a stage that is
## already cast adds nothing, commits no undo action, and leaves the scene
## unmodified. That is what makes this safe to run on every scene switch.
func _auto_populate_cast() -> void:
	if not _context.is_valid() or _context.encounter == null:
		return
	_cast_panel.populate_from_encounter()
	_cast_panel.show_miner()


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
	_manager_panel.set_context(_context)
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
	_manager_panel.set_context(_context)
	_rebuild_layer_outline()
	update_overlays()


## Handles a cast, prop or marker edit. Deliberately does not rebuild the
## terrain preview or retrace the room outline: neither depends on who is
## standing in the room, and both cost a full pass over the room's cells.
func _on_cast_changed() -> void:
	update_overlays()


func _on_armed_changed(_is_armed: bool) -> void:
	update_overlays()


func _on_brush_settings_changed() -> void:
	# The outline follows the selected stratum, so changing what the brush cuts
	# changes what is traced.
	_rebuild_layer_outline()
	update_overlays()


func _on_beat_selected(beat: CutsceneBeat) -> void:
	_selected_beat = beat
	_beat_inspector.show_beat(beat)
	update_overlays()


## Returns where the selected MOVE beat puts its actor, in scene space, or the
## no-target sentinel when the selection is not a move at all.
##
## The destination is a marker plus an offset, which is two numbers in an
## Inspector and nothing on screen. Resolving it here is what lets the viewport
## show the walk as a line the designer can see and grab.
func _get_selected_move_target() -> Variant:
	if _selected_beat == null or not _context.is_valid():
		return null
	if _selected_beat.kind != CutsceneBeat.Kind.MOVE:
		return null
	var target := _selected_beat.target_offset
	if not _selected_beat.target_marker.is_empty():
		target += _context.get_marker_position(_selected_beat.target_marker)
	elif _selected_beat.target_offset == Vector2.ZERO:
		return null
	return target


## Returns where the selected beat's actor stands when that beat begins, so the
## drawn path starts where the walk actually starts rather than at wherever the
## stand-in was last parked.
func _get_selected_move_origin() -> Variant:
	if _selected_beat == null or _context.sequence == null:
		return null
	if not _context.is_valid() or _selected_beat.actor.is_empty():
		return null
	# An authored start is the answer outright: it is where the walk begins by
	# definition, and evaluating the sequence would return the same point the
	# long way round.
	if _selected_beat.starts_from_authored_point:
		var authored := _selected_beat.start_offset
		if not _selected_beat.start_marker.is_empty():
			authored += _context.get_marker_position(
				_selected_beat.start_marker
			)
		return authored
	var player := CutsceneSequencePlayer.new()
	player.bind(
		_context.get_actor_preview,
		_context.get_marker_position,
		Callable(),
		null
	)
	var states: Dictionary = player.evaluate_at(
		_context.sequence,
		maxf(_selected_beat.start_seconds, 0.0)
	)
	var actor_states: Dictionary = states.get(&"actors", {})
	if not actor_states.has(_selected_beat.actor):
		return null
	var state: Dictionary = actor_states[_selected_beat.actor]
	return state.get(&"position")


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
	# Before the armed check: dragging a walk's destination is a selection-mode
	# gesture, not a sculpting one. It only claims the click when the pointer is
	# actually on the handle, so ordinary selection is untouched.
	if _handle_move_target_input(event):
		return true
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
				motion.alt_pressed,
				motion.ctrl_pressed
			)
			return true
		return false

	# Number keys pick a tool and the bracket keys resize the brush, the two
	# bindings every painting tool has. They are claimed only while the brush
	# is armed, so ordinary editor shortcuts are untouched the rest of the time.
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				_sculpt_panel.select_operation(key.keycode - KEY_1)
				update_overlays()
				return true
			KEY_BRACKETLEFT:
				_sculpt_panel.step_brush_size(-1)
				update_overlays()
				return true
			KEY_BRACKETRIGHT:
				_sculpt_panel.step_brush_size(1)
				update_overlays()
				return true
			KEY_X:
				# Swap carve and fill outright, for when Alt-dragging is not
				# the gesture wanted.
				_sculpt_panel.toggle_carve_fill()
				update_overlays()
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
		_begin_stroke(local_cell, button.alt_pressed, button.ctrl_pressed)
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


func _begin_stroke(
	local_cell: Vector2,
	invert: bool,
	smooth: bool
) -> void:
	_stroke_before = CutsceneTerrainSculpt.new()
	_stroke_before.copy_shape_from(_context.sculpt)
	_stroke_origin_local = local_cell
	_is_stroking = true
	_last_stroke_local = local_cell
	_apply_operation(local_cell, local_cell, invert, smooth)


func _stroke_to(
	local_cell: Vector2,
	invert: bool,
	smooth: bool
) -> void:
	_apply_operation(_last_stroke_local, local_cell, invert, smooth)
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
	_manager_panel.set_context(_context)
	_rebuild_layer_outline()
	update_overlays()


## Applies one segment of the stroke. Alt swaps carve and fill, which is the
## fastest way to correct an overshoot without leaving the drag.
func _apply_operation(
	from_local: Vector2,
	to_local: Vector2,
	invert: bool,
	smooth: bool
) -> void:
	var operation := _sculpt_panel.get_operation()
	# Holding ctrl smooths whatever is under the brush without changing the
	# armed tool, so a wall can be softened mid-cut and the cut resumed by
	# letting go. Alt still swaps carve and fill; ctrl wins when both are held,
	# because smoothing an inverted stroke means nothing.
	if smooth:
		operation = CutsceneSculptBrush.OP_SMOOTH
	elif invert:
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
## Drags the selected walk's destination, writing it back as the beat's offset
## from its marker.
##
## The offset is what moves, never the marker: a marker is shared by every beat
## that names it and by the stage's own opening walk, so dragging one walk's
## end would silently move everyone else's. Shift snaps to the marker itself,
## which is how an offset nudged by hand gets zeroed again.
##
## Returns whether the gesture was claimed.
func _handle_move_target_input(event: InputEvent) -> bool:
	var target_variant := _get_selected_move_target()
	if target_variant == null:
		_dragging_handle = &""
		return false
	var target: Vector2 = target_variant
	var transform := _get_viewport_transform()

	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			# The start is tested first: when a walk has not been given a length
			# yet both ends sit on the same point, and grabbing the end you can
			# still move is the useful outcome.
			if _selected_beat.starts_from_authored_point:
				var origin_variant := _get_selected_move_origin()
				if origin_variant != null:
					var origin_screen := transform * (origin_variant as Vector2)
					if (
						origin_screen.distance_to(button.position)
						<= _MOVE_HANDLE_GRAB_PIXELS
					):
						_dragging_handle = &"start"
						_move_offset_before_drag = _selected_beat.start_offset
						return true
			var handle_screen := transform * target
			if (
				handle_screen.distance_to(button.position)
				> _MOVE_HANDLE_GRAB_PIXELS
			):
				return false
			_dragging_handle = &"target"
			_move_offset_before_drag = _selected_beat.target_offset
			return true
		if not _dragging_handle.is_empty():
			# One undo entry for the whole drag, committed on release, rather
			# than one per motion event.
			_commit_move_handle_offset()
			_dragging_handle = &""
			return true
		return false

	var motion := event as InputEventMouseMotion
	if motion == null or _dragging_handle.is_empty():
		return false
	var is_start := _dragging_handle == &"start"
	var marker_name: StringName = (
		_selected_beat.start_marker
		if is_start
		else _selected_beat.target_marker
	)
	var world := _to_world_position(motion.position)
	var marker_origin := Vector2.ZERO
	if not marker_name.is_empty():
		marker_origin = _context.get_marker_position(marker_name)
	var offset := world - marker_origin
	if motion.shift_pressed:
		offset = Vector2.ZERO
	# Written straight onto the beat while dragging so the overlay and the
	# stand-ins follow the pointer; the undo entry is created on release.
	if is_start:
		_selected_beat.start_offset = offset
	else:
		_selected_beat.target_offset = offset
	_beat_inspector.show_beat(_selected_beat)
	_timeline_panel.refresh_preview()
	update_overlays()
	return true


## Records the finished drag as one undoable change.
func _commit_move_handle_offset() -> void:
	if _selected_beat == null or _context.undo_redo == null:
		return
	var property: StringName = (
		&"start_offset" if _dragging_handle == &"start" else &"target_offset"
	)
	var final_offset: Vector2 = _selected_beat.get(property)
	if final_offset.is_equal_approx(_move_offset_before_drag):
		return
	var undo_redo := _context.undo_redo
	undo_redo.create_action(
		"Move cutscene walk start"
		if _dragging_handle == &"start"
		else "Move cutscene walk target"
	)
	undo_redo.add_do_property(_selected_beat, property, final_offset)
	undo_redo.add_undo_property(
		_selected_beat, property, _move_offset_before_drag
	)
	undo_redo.commit_action()


## Returns the selected beat's kind as a word for the overlay label.
func _get_beat_kind_label() -> String:
	if _selected_beat == null:
		return ""
	var kind_names := CutsceneBeat.Kind.keys()
	if _selected_beat.kind < 0 or _selected_beat.kind >= kind_names.size():
		return "beat"
	return String(kind_names[_selected_beat.kind]).to_lower()


## Rings whoever the selected beat acts on, for the kinds that have no path to
## draw - a pose, a turn, a bounce, an appearance.
##
## Selecting a beat should always answer "who does this happen to" on the stage
## itself. A MOVE gets its walk drawn instead; everything else at least gets its
## subject picked out of the cast, which is the difference between reading a
## chart and looking at the scene.
func _draw_selected_actor_marker(
	overlay: Control,
	transform: Transform2D
) -> void:
	if _selected_beat == null or not _context.is_valid():
		return
	if _selected_beat.actor.is_empty():
		return
	var actor := _context.get_actor_preview(_selected_beat.actor)
	if not is_instance_valid(actor):
		return
	var actor_screen := transform * actor.global_position
	overlay.draw_arc(
		actor_screen, 13.0, 0.0, TAU, 28, MOVE_HANDLE_COLOR, 2.0
	)
	var font := overlay.get_theme_default_font()
	if font == null:
		return
	overlay.draw_string(
		font,
		actor_screen + Vector2(17.0, -14.0),
		"%s: %s" % [_selected_beat.actor, _get_beat_kind_label()],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		MOVE_HANDLE_COLOR
	)


## Draws the selected walk: where the actor starts, the line they travel, and a
## grabbable handle on the spot they finish at.
##
## Without this a MOVE beat is a marker name and an offset in the Inspector, and
## the only way to find out where somebody actually ends up is to scrub the
## playhead and watch. Drawing it makes the walk a thing on screen, and the
## handle makes it a thing you can move.
func _draw_selected_move_path(overlay: Control, transform: Transform2D) -> void:
	var target_variant := _get_selected_move_target()
	if target_variant == null:
		_draw_selected_actor_marker(overlay, transform)
		return
	var target: Vector2 = target_variant
	var target_screen := transform * target
	var origin_variant := _get_selected_move_origin()
	if origin_variant != null:
		var origin: Vector2 = origin_variant
		var origin_screen := transform * origin
		overlay.draw_line(origin_screen, target_screen, MOVE_PATH_COLOR, 2.0)
		if _selected_beat.starts_from_authored_point:
			# An authored start is draggable, so it is drawn as a handle. An
			# inherited one is just where the actor happened to be, and a handle
			# there would invite a drag that does nothing.
			overlay.draw_arc(
				origin_screen, 8.0, 0.0, TAU, 22, MOVE_PATH_COLOR, 2.0
			)
			overlay.draw_circle(origin_screen, 3.0, MOVE_PATH_COLOR)
			var start_font := overlay.get_theme_default_font()
			if start_font != null:
				overlay.draw_string(
					start_font,
					origin_screen + Vector2(12.0, 18.0),
					"starts here",
					HORIZONTAL_ALIGNMENT_LEFT,
					-1.0,
					12,
					MOVE_PATH_COLOR
				)
		else:
			overlay.draw_circle(origin_screen, 4.0, MOVE_PATH_COLOR)

	# A ring rather than a dot: the destination sits on top of the actor once
	# the playhead is past this beat, and a filled dot would hide them.
	overlay.draw_arc(
		target_screen, 9.0, 0.0, TAU, 24, MOVE_HANDLE_COLOR, 2.0
	)
	overlay.draw_arc(
		target_screen, 3.0, 0.0, TAU, 12, MOVE_HANDLE_COLOR, 2.0
	)
	var font := overlay.get_theme_default_font()
	if font == null:
		return
	var label := "%s walks here" % _selected_beat.actor
	if not _selected_beat.target_marker.is_empty():
		label += "  (%s)" % _selected_beat.target_marker
	overlay.draw_string(
		font,
		target_screen + Vector2(14.0, -12.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		MOVE_HANDLE_COLOR
	)


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	var preview := _context.preview
	var sculpt := _context.sculpt
	if preview == null or sculpt == null:
		return
	var transform := _get_viewport_transform()
	_draw_room_bounds(overlay, preview, sculpt, transform)
	_draw_layer_outline(overlay, transform)
	_draw_landing_line(overlay, preview, sculpt, transform)
	_draw_selected_move_path(overlay, transform)
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
			else "layer %d" % (layer_index + 1)
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
		"1-5 tool  ·  [ ] or wheel size  ·  ctrl+wheel layer"
		+ "  ·  shift straight  ·  ctrl smooth  ·  alt invert  ·  x swap"
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
