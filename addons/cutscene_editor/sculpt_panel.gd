@tool
class_name CutsceneSculptPanel
extends VBoxContainer

## How it works:
## - Owns the brush settings a designer sculpts a cutscene room with: which
##   operation is armed, how big and soft the brush is, and which stratum it
##   edits. The plugin reads that state when a click reaches the viewport.
## - Owns nothing about terrain. Every edit goes through CutsceneSculptBrush
##   onto the encounter's CutsceneTerrainSculpt, and the preview redraws itself
##   from the resource's own `changed` signal.
## - Reports the room's health back: authoring errors, how much is open, and
##   where a falling miner would actually touch down.
## The invariant is that arming a tool changes no terrain by itself; nothing
## here writes a cell until the plugin forwards a real click.

signal armed_changed(is_armed: bool)
signal brush_settings_changed

## A mined hit is not a brush stroke: it adds an authored impact marker and
## digs it through the production TerrainManager, exactly as a pickaxe would.
## It stays on this row because it is the same gesture — click the rock to
## change it — and it is how a designer checks a room reads correctly once
## the miner has broken into it.
const OP_DIG_HIT: StringName = &"dig_hit"

const OPERATION_LABELS: Array[String] = [
	"Carve",
	"Fill",
	"Smooth",
	"Roughen",
	"Dig hit",
]
const OPERATIONS: Array[StringName] = [
	CutsceneSculptBrush.OP_CARVE,
	CutsceneSculptBrush.OP_FILL,
	CutsceneSculptBrush.OP_SMOOTH,
	CutsceneSculptBrush.OP_ROUGHEN,
	OP_DIG_HIT,
]
## One line per tool saying what it is for, because a row of five verbs does
## not tell a designer which one shapes a room and which one breaks into it.
const OPERATION_TOOLTIPS: Array[String] = [
	"Open rock. This is how a room is cut.",
	"Close rock. Leaves pillars, ledges and walls the chamber never had.",
	"Wear an edge down toward its neighbours, softening a wall.",
	"Jag an edge. Only cells already on a solid/open boundary move, so it "
		+ "roughens a silhouette without punching holes through solid rock.",
	"Break in with a real mining hit through the production terrain, so you "
		+ "can see the room as it looks once the miner has arrived. "
		+ "Alt-click heals one.",
]

var _context: CutsceneEditorContext
var _brush := CutsceneSculptBrush.new()
var _operation_index: int = 0
var _is_armed: bool = false

var _status_label: Label
var _landing_label: Label
var _arm_button: Button
var _operation_buttons: Array[Button] = []
var _radius_slider: HSlider
var _strength_slider: HSlider
var _falloff_slider: HSlider
var _layer_selector: OptionButton
var _smoothing_slider: HSlider
var _floor_rows_spin: SpinBox
var _create_button: Button
var _missing_label: Label
var _controls_root: HBoxContainer
var _encounter_selector: OptionButton
var _focus_selector: OptionButton
var _focus_mode_selector: OptionButton
var _dim_slider: HSlider
var _follow_sculpt_layer: CheckBox
# -1 shows every stratum; otherwise the one stratum left fully visible.
var _focused_layer: int = -1


func _init() -> void:
	name = "Sculpt"
	_build_controls()


## Rebinds every control to a newly opened scene.
func set_context(context: CutsceneEditorContext) -> void:
	# A stratum left dimmed in the scene being closed would carry over into the
	# next one, where nothing explains why the rock is faded.
	if _context != null and _context.is_valid():
		var previous: TerrainLayerRenderer = _context.preview.terrain_renderer
		if previous != null:
			previous.clear_layer_display_overrides()
	_context = context
	_focused_layer = -1
	set_armed(false)
	refresh()


## Returns the brush the plugin applies on a viewport click.
func get_brush() -> CutsceneSculptBrush:
	return _brush


## Returns which operation is armed.
func get_operation() -> StringName:
	return OPERATIONS[_operation_index]


## Reports whether viewport clicks should sculpt instead of select.
func is_armed() -> bool:
	return _is_armed and _context != null and _context.can_sculpt()


## Arms or disarms sculpting, so the plugin can drop the tool when the scene
## changes without the panel and the viewport disagreeing about the mode.
func set_armed(armed: bool) -> void:
	var resolved := armed and _context != null and _context.can_sculpt()
	if resolved == _is_armed:
		return
	_is_armed = resolved
	if _arm_button != null:
		_arm_button.button_pressed = _is_armed
	armed_changed.emit(_is_armed)


## Rereads the open scene and redraws the panel's reported state.
func refresh() -> void:
	var has_stage := _context != null and _context.is_valid()
	_encounter_selector.get_parent().visible = has_stage
	if has_stage:
		_sync_encounter_selector()
	var sculpt := _context.sculpt if has_stage else null
	_controls_root.visible = sculpt != null
	_create_button.visible = has_stage and sculpt == null
	_missing_label.visible = not has_stage
	if not has_stage:
		_missing_label.text = (
			"Open a cutscene stage scene to sculpt its room."
		)
		return
	if sculpt == null:
		# A button that can do nothing must say so rather than absorb the
		# click. Until an encounter is chosen there is nothing to build a room
		# for, and pressing this looked like the tool was broken.
		var has_encounter := _context.encounter != null
		_create_button.disabled = not has_encounter
		_create_button.text = (
			"Create a room for this encounter"
			if has_encounter
			else "Pick the encounter above first"
		)
		_missing_label.visible = true
		_missing_label.text = (
			(
				"This encounter uses the generated chamber. Creating a room "
				+ "copies that same chamber so nothing changes at first; the "
				+ "brush tools appear once it exists."
			)
			if has_encounter
			else (
				"Choose which encounter this stage is authoring. The preview "
				+ "moves to its depth and shows its room."
			)
		)
		return
	_missing_label.visible = false
	_create_button.disabled = false
	_sync_layer_selector()
	_sync_sculpt_controls(sculpt)
	_update_status(sculpt)


func _build_controls() -> void:
	var encounter_row := HBoxContainer.new()
	var encounter_label := Label.new()
	encounter_label.text = "Authoring encounter"
	encounter_label.tooltip_text = (
		"Most encounters share one stage scene, so this picks which one the "
		+ "preview sits at. It moves the view to that encounter's depth and "
		+ "shows that encounter's room."
	)
	encounter_row.add_child(encounter_label)
	_encounter_selector = OptionButton.new()
	_encounter_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_encounter_selector.item_selected.connect(_on_encounter_selected)
	encounter_row.add_child(_encounter_selector)
	add_child(encounter_row)

	_missing_label = Label.new()
	_missing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_missing_label)

	_create_button = Button.new()
	_create_button.pressed.connect(_on_create_pressed)
	add_child(_create_button)

	# Three named columns rather than one tall stack. Stacked, these controls
	# stood taller than the 2D viewport they exist to serve, which is the wrong
	# way round for a tool used by looking at the terrain.
	_controls_root = HBoxContainer.new()
	_controls_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_controls_root)

	var brush_column := _add_column("Brush")
	_arm_button = Button.new()
	_arm_button.text = "Sculpt Terrain"
	_arm_button.toggle_mode = true
	_arm_button.tooltip_text = (
		"Arms the brush. While it is on, dragging in the 2D viewport sculpts "
		+ "instead of selecting. Hold Alt to swap carve and fill mid-drag."
	)
	_arm_button.toggled.connect(_on_arm_toggled)
	brush_column.add_child(_arm_button)

	var operation_grid := GridContainer.new()
	operation_grid.columns = 3
	brush_column.add_child(operation_grid)
	for operation_index in range(OPERATION_LABELS.size()):
		var button := Button.new()
		button.text = OPERATION_LABELS[operation_index]
		button.toggle_mode = true
		button.button_pressed = operation_index == 0
		button.tooltip_text = OPERATION_TOOLTIPS[operation_index]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_operation_pressed.bind(operation_index))
		operation_grid.add_child(button)
		_operation_buttons.append(button)

	_radius_slider = _add_slider(
		brush_column, "Size", 1.0, 40.0, 0.5, 6.0,
		"Brush radius in terrain cells."
	)
	_strength_slider = _add_slider(
		brush_column, "Strength", 0.05, 1.0, 0.05, 1.0,
		"How far into the brush the cut reaches. Below one it bites a smaller "
		+ "disc; it never scatters loose cells."
	)
	_falloff_slider = _add_slider(
		brush_column, "Falloff", 0.0, 1.0, 0.05, 0.5,
		"How quickly the brush weakens toward its rim."
	)

	var layer_column := _add_column("Layers")
	_layer_selector = _add_dropdown(
		layer_column, "Sculpting",
		"Shape moves the rock and the ground the miner stands on together. A "
		+ "single stratum changes only what that layer draws."
	)
	_layer_selector.item_selected.connect(_on_layer_selected)
	_focus_selector = _add_dropdown(
		layer_column, "See only",
		"Isolates one stratum while you work on it. The foreground rock covers "
		+ "everything behind it, so a buried layer cannot be judged until the "
		+ "layers in front get out of the way. Nothing the game draws changes."
	)
	_focus_selector.item_selected.connect(_on_focus_selected)
	_focus_mode_selector = _add_dropdown(
		layer_column, "Others",
		"Whether the strata you are not looking at fade or disappear."
	)
	_focus_mode_selector.add_item("dim")
	_focus_mode_selector.add_item("hide")
	_focus_mode_selector.item_selected.connect(_on_focus_mode_selected)
	_dim_slider = _add_slider(
		layer_column, "Dimmed to", 0.0, 1.0, 0.05, 0.15,
		"How faint the other strata go. Dimming keeps them as context; hiding "
		+ "removes them entirely."
	)
	_dim_slider.value_changed.connect(_on_dim_changed)
	_follow_sculpt_layer = CheckBox.new()
	_follow_sculpt_layer.text = "Follow sculpted layer"
	_follow_sculpt_layer.button_pressed = true
	_follow_sculpt_layer.tooltip_text = (
		"Picking a stratum to sculpt also isolates it."
	)
	_follow_sculpt_layer.toggled.connect(_on_follow_toggled)
	layer_column.add_child(_follow_sculpt_layer)

	var room_column := _add_column("Room")
	_smoothing_slider = _add_slider(
		room_column, "Rock smoothing", 0.0, 1.0, 0.05, 1.0,
		"How much the drawn rock rounds off the cell grid. Zero leaves hard "
		+ "cell edges; jaggedness is better made with the Roughen brush."
	)
	_smoothing_slider.value_changed.connect(_on_smoothing_changed)

	var floor_row := HBoxContainer.new()
	var floor_label := Label.new()
	floor_label.text = "Guarded floor"
	floor_label.custom_minimum_size.x = 90.0
	floor_label.tooltip_text = (
		"Rows at the encounter floor kept solid whatever you paint over them. "
		+ "The miner arrives by falling, so carving through the floor drops him "
		+ "past the cast. Set it to zero only for a deliberately floorless room."
	)
	floor_row.add_child(floor_label)
	_floor_rows_spin = SpinBox.new()
	_floor_rows_spin.min_value = 0
	_floor_rows_spin.max_value = 16
	_floor_rows_spin.value_changed.connect(_on_floor_rows_changed)
	floor_row.add_child(_floor_rows_spin)
	room_column.add_child(floor_row)

	var action_row := HBoxContainer.new()
	room_column.add_child(action_row)
	_add_action(
		action_row, "Reset", _on_bake_pressed,
		"Throws the room away and rebuilds the chamber the game generates."
	)
	_add_action(
		action_row, "Fill solid", _on_fill_all_pressed,
		"Fills every cell with rock, to carve a room out from nothing."
	)
	_add_action(
		action_row, "Open all", _on_clear_all_pressed,
		"Empties the room, leaving only the guarded floor."
	)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_column.add_child(_status_label)
	_landing_label = Label.new()
	_landing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_landing_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_column.add_child(_landing_label)


## Starts one titled column, so every control sits under a heading saying what
## it is for instead of in one anonymous run of rows.
func _add_column(title: String) -> VBoxContainer:
	if _controls_root.get_child_count() > 0:
		_controls_root.add_child(VSeparator.new())
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controls_root.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_color_override("font_color", Color(0.62, 0.72, 0.86))
	column.add_child(heading)
	return column


func _add_dropdown(
	parent: VBoxContainer,
	label_text: String,
	tooltip: String
) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 90.0
	label.tooltip_text = tooltip
	row.add_child(label)
	var dropdown := OptionButton.new()
	dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dropdown.tooltip_text = tooltip
	row.add_child(dropdown)
	parent.add_child(row)
	return dropdown


func _add_slider(
	parent: VBoxContainer,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	value: float,
	tooltip: String
) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 90.0
	label.tooltip_text = tooltip
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.tooltip_text = tooltip
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 80.0
	row.add_child(slider)
	var readout := Label.new()
	readout.text = "%.2f" % value
	readout.custom_minimum_size.x = 38.0
	row.add_child(readout)
	slider.value_changed.connect(
		func(new_value: float) -> void:
			readout.text = "%.2f" % new_value
			_on_brush_slider_changed()
	)
	parent.add_child(row)
	return slider


func _add_action(
	row: HBoxContainer,
	label_text: String,
	handler: Callable,
	tooltip: String
) -> void:
	var button := Button.new()
	button.text = label_text
	button.tooltip_text = tooltip
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	row.add_child(button)



func _on_arm_toggled(pressed: bool) -> void:
	set_armed(pressed)


func _on_operation_pressed(operation_index: int) -> void:
	_operation_index = operation_index
	for button_index in range(_operation_buttons.size()):
		_operation_buttons[button_index].button_pressed = (
			button_index == operation_index
		)
	brush_settings_changed.emit()


func _on_brush_slider_changed() -> void:
	_brush.radius_cells = _radius_slider.value
	_brush.strength = _strength_slider.value
	_brush.falloff = _falloff_slider.value
	brush_settings_changed.emit()


func _on_layer_selected(selected_index: int) -> void:
	# Index zero is the shape itself; every later entry is one stratum.
	_brush.target_layer = selected_index - 1
	if _brush.target_layer >= 0 and _context != null and _context.sculpt != null:
		_context.sculpt.ensure_layer_masks(_brush.target_layer + 1)
	if _follow_sculpt_layer.button_pressed:
		_set_focused_layer(_brush.target_layer)
	brush_settings_changed.emit()


func _on_focus_selected(selected_index: int) -> void:
	_set_focused_layer(selected_index - 1)


func _on_focus_mode_selected(_selected_index: int) -> void:
	_apply_layer_focus()


func _on_dim_changed(_value: float) -> void:
	_apply_layer_focus()


func _on_follow_toggled(pressed: bool) -> void:
	if pressed:
		_set_focused_layer(_brush.target_layer)


func _set_focused_layer(layer_index: int) -> void:
	_focused_layer = layer_index
	if _focus_selector.item_count > 0:
		_focus_selector.select(
			clampi(layer_index + 1, 0, _focus_selector.item_count - 1)
		)
	_apply_layer_focus()


## Dims or hides every stratum except the focused one. Restores all of them
## when nothing is focused, so leaving the tool never leaves the preview in a
## state a designer has to undo by hand.
func _apply_layer_focus() -> void:
	if _context == null or not _context.is_valid():
		return
	var renderer: TerrainLayerRenderer = _context.preview.terrain_renderer
	if renderer == null or renderer.profile == null:
		return
	if _focused_layer < 0:
		renderer.clear_layer_display_overrides()
		return
	var others_opacity := (
		0.0
		if _focus_mode_selector.selected == 1
		else _dim_slider.value
	)
	for layer_index in range(renderer.profile.get_layer_count()):
		renderer.set_layer_display_opacity(
			layer_index,
			1.0 if layer_index == _focused_layer else others_opacity
		)


func _on_smoothing_changed(value: float) -> void:
	if _context == null or _context.sculpt == null:
		return
	_context.sculpt.edge_smoothing = value
	_context.notify_authored_data_changed()


func _on_floor_rows_changed(value: float) -> void:
	if _context == null or _context.sculpt == null:
		return
	_context.sculpt.protected_floor_rows = int(value)
	_context.notify_authored_data_changed()
	_update_status(_context.sculpt)


func _on_bake_pressed() -> void:
	if _context == null or _context.sculpt == null:
		return
	CutsceneSculptBaker.bake_procedural_chamber(
		_context.sculpt,
		_context.preview.get_encounter_config(),
		_context.encounter,
		_context.preview.terrain_manager.config
	)
	_context.notify_authored_data_changed()
	refresh()


func _on_fill_all_pressed() -> void:
	_fill_room(true)


func _on_clear_all_pressed() -> void:
	_fill_room(false)


func _fill_room(solid: bool) -> void:
	if _context == null or _context.sculpt == null:
		return
	_context.sculpt.fill_all(solid)
	_context.notify_authored_data_changed()
	refresh()


## Creates and saves a room for the open stage's encounter, seeded from the
## chamber the game already generates so the first thing a designer sees is
## the room they already have rather than a wall of rock.
func _on_create_pressed() -> void:
	if _context == null or _context.encounter == null:
		_missing_label.visible = true
		_missing_label.text = (
			"This stage's terrain preview has no Encounter Config and "
			+ "Encounter Id, so there is no encounter to build a room for."
		)
		return
	var sculpt := CutsceneTerrainSculpt.new()
	CutsceneSculptBaker.bake_procedural_chamber(
		sculpt,
		_context.preview.get_encounter_config(),
		_context.encounter,
		_context.preview.terrain_manager.config
	)
	var directory := "res://resources/cinematics/sculpts"
	DirAccess.make_dir_recursive_absolute(directory)
	var sculpt_path := "%s/%s_room.tres" % [
		directory,
		String(_context.encounter.encounter_id),
	]
	if ResourceSaver.save(sculpt, sculpt_path) != OK:
		_missing_label.visible = true
		_missing_label.text = "Could not save the room to %s." % sculpt_path
		return
	sculpt.take_over_path(sculpt_path)
	_context.encounter.terrain_sculpt = sculpt
	if not _context.encounter.resource_path.is_empty():
		ResourceSaver.save(_context.encounter, _context.encounter.resource_path)
	_context.sculpt = sculpt
	_context.notify_authored_data_changed()
	refresh()


## Lists the run's encounters in schedule order and marks which already have a
## room, so a designer picking one can see what is authored and what is not.
func _sync_encounter_selector() -> void:
	var encounter_config: DepthEncounterConfig = (
		_context.preview.get_encounter_config()
	)
	_encounter_selector.clear()
	if encounter_config == null:
		# The usual cause is a deleted or moved room file. An encounter holding
		# a reference to a resource that is no longer there fails to load, and
		# it takes the whole schedule down with it, so the panel would
		# otherwise report only that everything is missing.
		_encounter_selector.add_item("Encounter schedule could not be loaded")
		_encounter_selector.disabled = true
		_missing_label.visible = true
		_missing_label.text = (
			"resources/encounters/depth_encounter_config.tres did not load. "
			+ "If a room .tres under resources/cinematics/sculpts/ was deleted "
			+ "or moved, the encounter pointing at it fails to load and takes "
			+ "the schedule with it. Check the Output dock for the file it "
			+ "cannot find, and clear that encounter's Terrain Sculpt."
		)
		return
	_encounter_selector.disabled = false
	var selected_index := 0
	# A stage that names no encounter must not show one as if it were chosen.
	# Selecting an item programmatically emits nothing, so a dropdown reading
	# "cheese_girl_first" while the preview holds no encounter id would leave
	# every button below it refusing to act for no visible reason.
	if _context.preview.encounter_id.is_empty():
		_encounter_selector.add_item("— pick the encounter to author —")
		_encounter_selector.set_item_metadata(0, &"")
	for encounter in encounter_config.encounters:
		if encounter == null:
			continue
		var item_index := _encounter_selector.item_count
		_encounter_selector.add_item(
			"%s  (depth %d)%s" % [
				encounter.encounter_id,
				encounter.depth_from_surface,
				"  •room" if encounter.terrain_sculpt != null else "",
			]
		)
		_encounter_selector.set_item_metadata(item_index, encounter.encounter_id)
		if encounter.encounter_id == _context.preview.encounter_id:
			selected_index = item_index
	if _encounter_selector.item_count > 0:
		_encounter_selector.select(selected_index)


func _on_encounter_selected(item_index: int) -> void:
	if _context == null or _context.preview == null:
		return
	var chosen: StringName = _encounter_selector.get_item_metadata(item_index)
	if chosen.is_empty():
		return
	_context.preview.encounter_id = chosen
	_context.encounter = _context.preview.get_encounter()
	_context.sculpt = _context.preview.get_sculpt()
	_context.notify_authored_data_changed()
	refresh()


func _sync_layer_selector() -> void:
	var layer_count := 0
	if (
		_context.preview != null
		and _context.preview.terrain_renderer != null
		and _context.preview.terrain_renderer.profile != null
	):
		layer_count = (
			_context.preview.terrain_renderer.profile.get_gameplay_layer_count()
		)
	if _layer_selector.item_count == layer_count + 1:
		return
	_layer_selector.clear()
	_layer_selector.add_item("Shape (all strata)")
	_focus_selector.clear()
	_focus_selector.add_item("All strata")
	for layer_index in range(layer_count):
		_layer_selector.add_item("Stratum %d only" % (layer_index + 1))
		_focus_selector.add_item("Stratum %d" % (layer_index + 1))
	_layer_selector.select(clampi(_brush.target_layer + 1, 0, layer_count))
	_focus_selector.select(clampi(_focused_layer + 1, 0, layer_count))


func _sync_sculpt_controls(sculpt: CutsceneTerrainSculpt) -> void:
	if not is_equal_approx(_smoothing_slider.value, sculpt.edge_smoothing):
		_smoothing_slider.set_value_no_signal(sculpt.edge_smoothing)
	if int(_floor_rows_spin.value) != sculpt.protected_floor_rows:
		_floor_rows_spin.set_value_no_signal(sculpt.protected_floor_rows)


## Reports the room's shape and, more importantly, where a falling miner would
## actually stop. A room can look finished and still drop him onto a ledge
## twenty rows above the cast.
func _update_status(sculpt: CutsceneTerrainSculpt) -> void:
	var sculpt_error := sculpt.get_sculpt_error()
	if not sculpt_error.is_empty():
		_status_label.text = sculpt_error
		_landing_label.text = ""
		return
	var open_cells := sculpt.get_open_cell_count()
	var total_cells := sculpt.grid_size.x * sculpt.grid_size.y
	_status_label.text = "Room %d x %d cells, %d open (%d%%)." % [
		sculpt.grid_size.x,
		sculpt.grid_size.y,
		open_cells,
		roundi(100.0 * float(open_cells) / float(maxi(total_cells, 1))),
	]
	_landing_label.text = _describe_landing(sculpt)


func _describe_landing(sculpt: CutsceneTerrainSculpt) -> String:
	if _context.preview == null or _context.preview.terrain_manager == null:
		return ""
	var config: MiningConfig = _context.preview.terrain_manager.config
	var landing_rows := sculpt.get_landing_local_rows(
		config.snake_half_span_cells
	)
	if landing_rows.is_empty():
		return "The room does not contain its own floor row."
	var floor_row := sculpt.get_floor_local_row()
	var highest_landing := floor_row
	var sealed_columns := 0
	for landing_row in landing_rows:
		if landing_row < 0:
			sealed_columns += 1
			continue
		highest_landing = mini(highest_landing, landing_row)
	if sealed_columns > 0:
		return (
			"%d of the columns the miner can arrive down have no opening to "
			% sealed_columns
			+ "fall into; he would break the ceiling onto solid rock."
		)
	if highest_landing >= floor_row:
		return "The miner lands on the room's floor from every entry column."
	return (
		"The miner lands up to %d rows above the floor on some columns; "
		% (floor_row - highest_landing)
		+ "that is a ledge catching him before the cast."
	)
