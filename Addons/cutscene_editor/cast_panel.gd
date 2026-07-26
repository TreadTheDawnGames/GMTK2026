@tool
class_name CutsceneCastPanel
extends VBoxContainer

## How it works:
## - Reads the shared context and builds cast, prop, and marker controls in code.
## - Structural edits are staged through the context's undo manager.
## - Rows multi-select real stage nodes; compact tools align, space, and floor
##   snap them through one undoable transform action.
## - Actor position actions request MOVE-beat edits through the shared context,
##   leaving timeline ownership and timing outside this panel.
## - The context signal rebuilds this panel after edits and undo/redo.
## The invariant is that every authored node has the edited scene as owner and
## every structural change has a matching undo operation and one notification.

enum AlignMode {
	LEFT,
	HORIZONTAL_CENTER,
	RIGHT,
	TOP,
	VERTICAL_CENTER,
	BOTTOM,
}

enum DistributeAxis {
	HORIZONTAL,
	VERTICAL,
}

const _MARKER_ROOT_NAMES: Array[StringName] = [
	&"ActorMarkers",
	&"PropMarkers",
	&"ActionMarkers",
]
## What each marker root is for, in the same order as _MARKER_ROOT_NAMES. The
## node names mean nothing to someone dressing a scene; what the markers are used
## for does.
const _MARKER_ROOT_LABELS: Array[String] = [
	"Where people stand",
	"Where scenery sits",
	"Where things happen",
]
## The spots a stage almost always wants. Offering them by name is what stops a
## beat targeting "Converstaion" and walking nowhere with no error.
const _MARKER_NAME_SUGGESTIONS: Array[String] = [
	"Entrance",
	"Conversation",
	"Work",
	"Rest",
	"Exit",
]
const _CUSTOM_MARKER_LABEL := "Something else..."
## Where prop scenes live. Scanned rather than listed, so art added to the folder
## shows up without this file being touched.
const _PROP_SCENE_DIR := "res://Scenes/props"
## How far along the floor each new prop is placed from the last.
const _PROP_PLACEMENT_STEP_PIXELS: float = 96.0

const _MINER_RIG_SCENE := preload("res://Scenes/mining/miner_rig.tscn")

var _context: CutsceneEditorContext
var _status_label: Label
var _actor_choice: OptionButton
## Parallel to _actor_choice's items: {"actor_id": StringName, "appearance":
## CharacterAppearance} per entry, so a pick resolves without reparsing labels.
var _actor_choice_entries: Array[Dictionary] = []
var _prop_choice: OptionButton
## Prop scene paths the dropdown currently offers, parallel to its items.
var _prop_choice_paths: PackedStringArray = PackedStringArray()
var _marker_choice: OptionButton
var _marker_root_selector: OptionButton
var _marker_name_edit: LineEdit
var _selected_preview: CutsceneActorPreview
## The panel mirrors EditorSelection but keeps the same explicit selection in
## standalone verification, where EditorInterface does not exist.
var _selected_stage_nodes: Array[Node2D] = []
var _selection_checks: Dictionary[int, CheckBox] = {}
var _syncing_editor_selection: bool = false
var _standalone_test_undo_redo: UndoRedo


func _init() -> void:
	name = &"Cast"
	_rebuild()


## Rebinds the panel to one open stage, or shows a safe empty state.
func set_context(context: CutsceneEditorContext) -> void:
	var context_changed := _context != context
	if (
		_context != null
		and is_instance_valid(_context)
		and _context != context
		and _context.cast_changed.is_connected(
			_on_cast_changed
		)
	):
		_context.cast_changed.disconnect(_on_cast_changed)
	_context = context
	if context_changed:
		_selected_stage_nodes.clear()
		_selected_preview = null
	if (
		_context != null
		and not _context.cast_changed.is_connected(
			_on_cast_changed
		)
	):
		_context.cast_changed.connect(_on_cast_changed)
	_connect_editor_selection()
	_rebuild()


## Supplies the base UndoRedo used only by standalone verification, where the
## editor's abstract manager cannot be constructed outside an editor process.
func set_standalone_test_undo_redo(undo_redo: UndoRedo) -> void:
	_standalone_test_undo_redo = undo_redo
	_rebuild()


func _rebuild() -> void:
	_clear_contents()
	if not _has_valid_context():
		_selected_stage_nodes.clear()
		_selected_preview = null
		var message := Label.new()
		message.text = "Open a cutscene stage to edit its cast and props."
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(message)
		return
	_prune_selected_stage_nodes()
	_refresh_selection_from_editor()
	_build_controls()


func _clear_contents() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_status_label = null
	_actor_choice = null
	_actor_choice_entries.clear()
	_prop_choice = null
	_prop_choice_paths = PackedStringArray()
	_marker_choice = null
	_marker_root_selector = null
	_marker_name_edit = null
	_selection_checks.clear()


func _has_valid_context() -> bool:
	return (
		_context != null
		and is_instance_valid(_context)
		and _context.is_valid()
		and is_instance_valid(_context.scene_root)
		and _get_undo_redo() != null
	)


func _build_controls() -> void:
	var title := Label.new()
	title.text = "Cast and Stage Dressing"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	# No "Populate from encounter" or "Show the miner" buttons: opening a stage
	# now places the encounter's cast and the miner on its own, so a button to
	# do it by hand only ever restates what already happened. Both calls are
	# still public - the plugin makes them on scene_changed.
	if not Engine.is_editor_hint():
		return

	add_child(_make_section_label("In this cutscene"))
	var cast_scroll := ScrollContainer.new()
	cast_scroll.custom_minimum_size.y = 138.0
	cast_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cast_list := VBoxContainer.new()
	cast_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cast_scroll.add_child(cast_list)
	add_child(cast_scroll)
	_build_stage_rows(cast_list)

	var selection_row := HFlowContainer.new()
	var select_all_button := _make_compact_button(
		"All",
		"Select every actor and composed prop in this stage.",
		_on_select_all_pressed
	)
	selection_row.add_child(select_all_button)
	var clear_selection_button := _make_compact_button(
		"None",
		"Clear the stage selection.",
		_on_clear_selection_pressed
	)
	selection_row.add_child(clear_selection_button)
	var remove_button := Button.new()
	remove_button.text = "Remove actors"
	remove_button.tooltip_text = (
		"Remove selected actor stand-ins. Props and their authored children "
		+ "are left untouched."
	)
	remove_button.pressed.connect(_on_remove_selected_actors_pressed)
	selection_row.add_child(remove_button)
	add_child(selection_row)

	add_child(_make_section_label("Stage selected objects"))
	var staging_tools := HFlowContainer.new()
	staging_tools.add_theme_constant_override(&"h_separation", 4)
	staging_tools.add_theme_constant_override(&"v_separation", 4)
	for definition: Dictionary in [
		{
			"text": "Floor",
			"tip": (
				"Put each selected actor or prop origin on the first sculpted "
				+ "rock surface below it. Horizontal placement is preserved."
			),
			"call": _on_snap_to_floor_pressed,
		},
		{
			"text": "Left",
			"tip": "Align selected origins to the leftmost selected object.",
			"call": _on_align_pressed.bind(AlignMode.LEFT),
		},
		{
			"text": "Center X",
			"tip": "Align selected origins on one shared horizontal center.",
			"call": _on_align_pressed.bind(AlignMode.HORIZONTAL_CENTER),
		},
		{
			"text": "Right",
			"tip": "Align selected origins to the rightmost selected object.",
			"call": _on_align_pressed.bind(AlignMode.RIGHT),
		},
		{
			"text": "Top",
			"tip": "Align selected origins to the highest selected object.",
			"call": _on_align_pressed.bind(AlignMode.TOP),
		},
		{
			"text": "Center Y",
			"tip": "Align selected origins on one shared vertical center.",
			"call": _on_align_pressed.bind(AlignMode.VERTICAL_CENTER),
		},
		{
			"text": "Bottom",
			"tip": "Align selected origins to the lowest selected object.",
			"call": _on_align_pressed.bind(AlignMode.BOTTOM),
		},
		{
			"text": "Space X",
			"tip": (
				"Evenly distribute three or more selected objects from left "
				+ "to right while keeping the endpoints fixed."
			),
			"call": _on_distribute_pressed.bind(DistributeAxis.HORIZONTAL),
		},
		{
			"text": "Space Y",
			"tip": (
				"Evenly distribute three or more selected objects from top "
				+ "to bottom while keeping the endpoints fixed."
			),
			"call": _on_distribute_pressed.bind(DistributeAxis.VERTICAL),
		},
	]:
		staging_tools.add_child(_make_compact_button(
			definition["text"],
			definition["tip"],
			definition["call"]
		))
	add_child(staging_tools)

	var movement_tools := HFlowContainer.new()
	movement_tools.add_theme_constant_override(&"h_separation", 4)
	movement_tools.add_theme_constant_override(&"v_separation", 4)
	movement_tools.add_child(_make_compact_button(
		"Use as start",
		(
			"Record each selected actor's visible stage position as the "
			+ "selected MOVE beat's authored start."
		),
		_on_record_start_pressed
	))
	movement_tools.add_child(_make_compact_button(
		"Use as destination",
		(
			"Record each selected actor's visible stage position as the "
			+ "selected MOVE beat's destination."
		),
		_on_record_destination_pressed
	))
	movement_tools.add_child(_make_compact_button(
		"Create move here",
		(
			"Create one MOVE beat per selected actor, targeting where each "
			+ "actor currently stands in the 2D scene."
		),
		_on_create_movement_pressed
	))
	add_child(movement_tools)

	add_child(HSeparator.new())
	add_child(_make_section_label("Add someone to this cutscene"))
	# A dropdown of the run's own characters rather than a typed id and a
	# resource path. Adding Cheese Girl should not require knowing that she is
	# "cheese_girl" and that her art lives in a .tres two folders away; picking
	# her by name fills in both, and the ids the timeline keys its lanes by stay
	# spelled correctly because nobody types them.
	_actor_choice = OptionButton.new()
	_actor_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actor_choice.tooltip_text = (
		"Everyone the run's schedule knows about. Picking a name brings their "
		+ "real artwork with them."
	)
	_rebuild_actor_choices()
	_add_labeled_control("Character", _actor_choice)
	var add_actor_button := Button.new()
	add_actor_button.text = "Add to cutscene"
	add_actor_button.pressed.connect(_on_add_actor_pressed)
	add_child(add_actor_button)

	add_child(HSeparator.new())
	add_child(_make_section_label("Add scenery"))
	# A list of the props that exist, not a path to hunt for. Dressing a set
	# means reaching for a table, and a designer should not have to know that
	# the table is a PackedScene two folders down.
	_prop_choice = OptionButton.new()
	_prop_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prop_choice.tooltip_text = (
		"Everything in %s. Added standing on the stage floor, ready to drag."
		% _PROP_SCENE_DIR
	)
	_rebuild_prop_choices()
	_add_labeled_control("Prop", _prop_choice)
	var add_prop_button := Button.new()
	add_prop_button.text = "Add to cutscene"
	add_prop_button.pressed.connect(_on_add_prop_pressed)
	add_child(add_prop_button)

	add_child(HSeparator.new())
	add_child(_make_section_label("Add a spot to walk to"))
	# The roots are named after what they hold rather than after the node, and
	# the common marker names are offered outright: a beat targets a marker by
	# name, so a typo here is a walk that silently goes nowhere.
	_marker_root_selector = OptionButton.new()
	for root_index in range(_MARKER_ROOT_NAMES.size()):
		_marker_root_selector.add_item(_MARKER_ROOT_LABELS[root_index])
	_marker_root_selector.select(0)
	_add_labeled_control("Used for", _marker_root_selector)
	_marker_choice = OptionButton.new()
	_marker_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for suggestion in _MARKER_NAME_SUGGESTIONS:
		_marker_choice.add_item(suggestion)
	_marker_choice.add_item(_CUSTOM_MARKER_LABEL)
	_marker_choice.item_selected.connect(_on_marker_choice_selected)
	_add_labeled_control("Spot", _marker_choice)
	_marker_name_edit = LineEdit.new()
	_marker_name_edit.placeholder_text = "Name a beat will target"
	_marker_name_edit.visible = false
	_add_labeled_control("Custom name", _marker_name_edit)
	var add_marker_button := Button.new()
	add_marker_button.text = "Add to cutscene"
	add_marker_button.pressed.connect(_on_add_marker_pressed)
	add_child(add_marker_button)


## Lists every prop scene on disk, so art dropped into the folder appears here
## without anyone editing this panel.
func _rebuild_prop_choices() -> void:
	_prop_choice.clear()
	_prop_choice_paths = PackedStringArray()
	var directory := DirAccess.open(_PROP_SCENE_DIR)
	if directory == null:
		_prop_choice.add_item("No %s folder" % _PROP_SCENE_DIR.get_file())
		_prop_choice.disabled = true
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	var names := PackedStringArray()
	while entry != "":
		if not directory.current_is_dir() and entry.ends_with(".tscn"):
			names.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	names.sort()
	for scene_name in names:
		_prop_choice.add_item(
			scene_name.get_basename().replace("_", " ").capitalize()
		)
		_prop_choice_paths.append("%s/%s" % [_PROP_SCENE_DIR, scene_name])
	if _prop_choice_paths.is_empty():
		_prop_choice.add_item("No props authored yet")
		_prop_choice.disabled = true
		return
	_prop_choice.disabled = false
	_prop_choice.select(0)


## Shows the free-text box only when the designer wants a name that is not one
## of the usual spots, so the common path stays a single choice.
func _on_marker_choice_selected(index: int) -> void:
	if not is_instance_valid(_marker_name_edit):
		return
	_marker_name_edit.visible = index >= _MARKER_NAME_SUGGESTIONS.size()


## Returns the marker name to create: a chosen suggestion, or whatever was typed
## when "Something else" is selected.
func _get_chosen_marker_name() -> String:
	if not is_instance_valid(_marker_choice):
		return ""
	var index := _marker_choice.selected
	if index >= 0 and index < _MARKER_NAME_SUGGESTIONS.size():
		return _MARKER_NAME_SUGGESTIONS[index]
	if not is_instance_valid(_marker_name_edit):
		return ""
	return _marker_name_edit.text.strip_edges()


## Fills the character dropdown from the run's schedule, leaving out anyone
## already standing in this cutscene so the list is only people you can add.
##
## Names come from the actor id with its underscores opened up, because the
## schedule is the only place a character's identity is written down and a
## second hand-kept table of display names would drift from it.
func _rebuild_actor_choices() -> void:
	_actor_choice.clear()
	_actor_choice_entries.clear()
	if not _has_valid_context():
		return
	var schedule: DepthEncounterConfig = _context.preview.get_encounter_config()
	if schedule == null:
		return
	var placed := _context.get_stage_actor_ids()
	var seen: Dictionary = {}
	for scheduled: DepthCharacterEncounter in schedule.encounters:
		if scheduled == null or String(scheduled.actor_id).is_empty():
			continue
		var actor_id := scheduled.actor_id
		if seen.has(actor_id) or placed.has(String(actor_id)):
			continue
		seen[actor_id] = true
		var label := String(actor_id).replace("_", " ").capitalize()
		if scheduled.appearance == null:
			label += "  (no artwork yet)"
		_actor_choice.add_item(label)
		_actor_choice_entries.append({
			"actor_id": actor_id,
			"appearance": scheduled.appearance,
		})
	if _actor_choice.item_count == 0:
		_actor_choice.add_item("Everyone is already here")
		_actor_choice.disabled = true
	else:
		_actor_choice.disabled = false
		_actor_choice.select(0)


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


func _make_compact_button(
	text: String,
	tooltip: String,
	callback: Callable
) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	return button


func _build_stage_rows(cast_list: VBoxContainer) -> void:
	var row_count := 0
	for actor_id: StringName in _context.get_stage_actor_ids():
		var preview := _context.get_actor_preview(actor_id)
		if preview == null:
			continue
		var row := HBoxContainer.new()
		_add_selection_check(row, preview)
		var select_button := Button.new()
		select_button.text = "Actor: %s" % (
			String(preview.actor_id) if not preview.actor_id.is_empty()
			else "<unnamed actor>"
		)
		select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select_button.tooltip_text = (
			"Select only this actor in the 2D editor. Use the checkbox to "
			+ "build a group selection."
		)
		select_button.pressed.connect(
			_on_stage_item_row_pressed.bind(preview)
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
	for prop in _context.get_stage_props():
		var prop_row := HBoxContainer.new()
		_add_selection_check(prop_row, prop)
		var prop_button := Button.new()
		prop_button.text = "Prop: %s" % prop.name
		prop_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		prop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prop_button.tooltip_text = (
			"Select this composed prop in the 2D editor. Its child sprites stay "
			+ "together as one stage object."
		)
		prop_button.pressed.connect(_on_stage_item_row_pressed.bind(prop))
		prop_row.add_child(prop_button)
		var prop_type := Label.new()
		prop_type.text = prop.get_class()
		prop_type.custom_minimum_size.x = 150.0
		prop_row.add_child(prop_type)
		cast_list.add_child(prop_row)
		row_count += 1
	if row_count == 0:
		var empty_label := Label.new()
		empty_label.text = "No actors or props placed in this stage."
		cast_list.add_child(empty_label)


func _add_selection_check(row: HBoxContainer, node: Node2D) -> void:
	var check := CheckBox.new()
	check.tooltip_text = (
		"Include this object in floor snap, alignment, and spacing actions."
	)
	check.button_pressed = _selected_stage_nodes.has(node)
	check.toggled.connect(_on_stage_item_toggled.bind(node))
	row.add_child(check)
	_selection_checks[node.get_instance_id()] = check


func _get_appearance_name(appearance: CharacterAppearance) -> String:
	if appearance == null:
		return "No appearance"
	if not appearance.resource_name.is_empty():
		return appearance.resource_name
	if not appearance.resource_path.is_empty():
		return appearance.resource_path.get_file().get_basename()
	return "Unnamed appearance"


## Adds the encounter's currently present actors without disturbing authored
## stand-ins. The returned x/y values are added and already-placed counts.
func populate_from_encounter() -> Vector2i:
	if not _has_valid_context():
		_set_status("Open a valid cutscene stage first.")
		return Vector2i.ZERO
	if _context.encounter == null:
		_set_status("This stage has no encounter to populate.")
		return Vector2i.ZERO
	var mining_config := _get_stage_mining_config()
	if mining_config == null:
		_set_status("The stage has no mining config for cast placement.")
		return Vector2i.ZERO

	var encounter := _context.encounter
	var encounter_config := _context.preview.get_encounter_config()
	if encounter_config == null:
		_set_status("The stage has no encounter schedule to populate from.")
		return Vector2i.ZERO
	var appearance_by_actor_id: Dictionary[StringName, CharacterAppearance] = {}
	for scheduled_encounter: DepthCharacterEncounter in (
		encounter_config.encounters
	):
		if (
			scheduled_encounter != null
			and not scheduled_encounter.actor_id.is_empty()
			and not appearance_by_actor_id.has(scheduled_encounter.actor_id)
		):
			appearance_by_actor_id[scheduled_encounter.actor_id] = (
				scheduled_encounter.appearance
			)
	if not appearance_by_actor_id.has(encounter.actor_id):
		appearance_by_actor_id[encounter.actor_id] = encounter.appearance

	var horizontal_offset_cells := _get_encounter_horizontal_offset_cells(
		encounter_config
	)
	var actor_ids: Array[StringName] = []
	var actor_positions: Dictionary[StringName, Vector2] = {}
	if not encounter.actor_id.is_empty():
		actor_ids.append(encounter.actor_id)
		actor_positions[encounter.actor_id] = Vector2(
			float(horizontal_offset_cells)
				* float(mining_config.terrain_cell_world_size),
			0.0
		)
	if encounter.gathers_cast:
		var gathering_positions := _get_gathering_positions(
			mining_config,
			horizontal_offset_cells,
			encounter_config.gathering_actor_ids.size()
		)
		for actor_index in range(
			min(
				encounter_config.gathering_actor_ids.size(),
				gathering_positions.size()
			)
		):
			var actor_id := encounter_config.gathering_actor_ids[actor_index]
			if actor_id.is_empty():
				continue
			if not actor_ids.has(actor_id):
				actor_ids.append(actor_id)
			actor_positions[actor_id] = gathering_positions[actor_index]

	# Anyone the stage's own artwork already draws. Placing their stand-in too
	# would show the same character twice in the same shot.
	var drawn_into_set: Array = []
	var drawn_value: Variant = _context.stage.get(&"actors_drawn_into_set")
	if drawn_value is Array:
		drawn_into_set = drawn_value

	# The whole cast shares the miner's cutscene draw order. Only he was being
	# given one, so everyone else defaulted to zero and stood behind both the
	# walkway and the foreground rock - Cheese Girl's legs disappeared into the
	# floor while the miner's did not, standing on the same line.
	var cast_draw_order: int = _read_miner_rig().get("draw_order", 0)

	var additions: Array[CutsceneActorPreview] = []
	var already_placed := 0
	for actor_id in actor_ids:
		if drawn_into_set.has(actor_id):
			continue
		if _context.get_actor_preview(actor_id) != null:
			already_placed += 1
			continue
		var actor := CutsceneActorPreview.new()
		actor.name = _make_unique_child_name(_context.stage, String(actor_id))
		actor.actor_id = actor_id
		actor.appearance = appearance_by_actor_id.get(actor_id) as CharacterAppearance
		actor.position = actor_positions.get(actor_id, Vector2.ZERO)
		actor.z_index = cast_draw_order
		additions.append(actor)

	if not additions.is_empty():
		_commit_actor_additions(additions, "Populate cutscene cast")
	_set_status(
		"Added %d, left %d already placed."
		% [additions.size(), already_placed]
	)
	return Vector2i(additions.size(), already_placed)


## Adds the always-present miner once, preserving any designer placement.
func show_miner() -> bool:
	if not _has_valid_context():
		_set_status("Open a valid cutscene stage first.")
		return false
	if _context.get_actor_preview(&"miner") != null:
		_set_status("Miner already placed.")
		return false
	# One instantiation for both answers. Building the rig twice to read two of
	# its fields is work repeated on every scene the editor opens.
	var miner_rig_facts := _read_miner_rig()
	var miner_appearance: CharacterAppearance = miner_rig_facts.get("appearance")
	if miner_appearance == null:
		_set_status("The miner rig art could not be resolved for preview.")
		return false
	var miner_z_index: int = miner_rig_facts.get("draw_order", -1)
	if miner_z_index < 0:
		_set_status("The miner gameplay draw order could not be resolved.")
		return false
	var miner := CutsceneActorPreview.new()
	miner.name = _make_unique_child_name(_context.stage, "Miner")
	miner.actor_id = &"miner"
	miner.appearance = miner_appearance
	miner.position = Vector2.ZERO
	# Read the rig's current order so the editor previews the same second-stratum
	# placement as the encounter instead of carrying a stale literal.
	miner.z_index = miner_z_index
	_commit_actor_additions([miner], "Show cutscene miner")
	_set_status("Added the miner.")
	return true


func _get_stage_mining_config() -> MiningConfig:
	if _context.preview == null:
		return null
	var terrain_manager := _context.preview.terrain_manager
	if not is_instance_valid(terrain_manager):
		return null
	return terrain_manager.config


func _get_undo_redo() -> Variant:
	if _context != null and _context.undo_redo != null:
		return _context.undo_redo
	return _standalone_test_undo_redo


func _get_encounter_horizontal_offset_cells(
	encounter_config: DepthEncounterConfig
) -> int:
	return encounter_config.encounter_horizontal_offset_cells


func _get_gathering_positions(
	mining_config: MiningConfig,
	horizontal_offset_cells: int,
	actor_count: int
) -> Array[Vector2]:
	# Mirrors DepthEncounterController._gather_cafe_characters in stage space.
	var positions: Array[Vector2] = []
	var edge_margin_cells := clampi(
		absi(horizontal_offset_cells) / 2,
		4,
		maxi(mining_config.terrain_width_cells / 4, 4)
	)
	var minimum_cell_x := float(edge_margin_cells)
	var maximum_cell_x := float(
		maxi(
			mining_config.terrain_width_cells - 1 - edge_margin_cells,
			edge_margin_cells
		)
	)
	var spacing_cells := (
		0.0
		if actor_count <= 1
		else minf(
			16.0,
			(maximum_cell_x - minimum_cell_x)
				/ float(actor_count - 1)
		)
	)
	var group_span_cells := spacing_cells * float(maxi(actor_count - 1, 0))
	var group_start_cell_x := clampf(
		float(mining_config.terrain_width_cells) * 0.5
			- group_span_cells * 0.5,
		minimum_cell_x,
		maxf(maximum_cell_x - group_span_cells, minimum_cell_x)
	)
	var terrain_center_cell_x := float(mining_config.terrain_width_cells) * 0.5
	var cell_size := float(mining_config.terrain_cell_world_size)
	for actor_index in range(actor_count):
		positions.append(Vector2(
			(
				group_start_cell_x
					+ float(actor_index) * spacing_cells
					- terrain_center_cell_x
			) * cell_size,
			0.0
		))
	return positions


func _commit_actor_additions(
	additions: Array[CutsceneActorPreview],
	action_name: String
) -> void:
	var undo_redo: Variant = _get_undo_redo()
	undo_redo.create_action(action_name)
	for actor: CutsceneActorPreview in additions:
		if undo_redo is UndoRedo:
			undo_redo.add_do_method(
				Callable(_context.stage, &"add_child").bind(actor)
			)
		else:
			undo_redo.add_do_method(_context.stage, &"add_child", actor)
		undo_redo.add_do_property(actor, &"owner", _context.scene_root)
		if undo_redo is UndoRedo:
			undo_redo.add_do_method(Callable(actor, &"_sync_sprite_owner"))
		else:
			undo_redo.add_do_method(actor, &"_sync_sprite_owner")
		if undo_redo is UndoRedo:
			undo_redo.add_undo_method(
				Callable(_context, &"notify_cast_changed")
			)
			undo_redo.add_undo_method(
				Callable(_context.stage, &"remove_child").bind(actor)
			)
		else:
			undo_redo.add_undo_method(
				_context,
				&"notify_cast_changed"
			)
			undo_redo.add_undo_method(_context.stage, &"remove_child", actor)
		undo_redo.add_do_reference(actor)
	if undo_redo is UndoRedo:
		undo_redo.add_do_method(
			Callable(_context, &"notify_cast_changed")
		)
	else:
		undo_redo.add_do_method(
			_context,
			&"notify_cast_changed"
		)
	undo_redo.commit_action()


## Reads everything the preview needs off one throwaway MinerRig: the artwork to
## mirror, and the draw order a cutscene puts him at.
##
## Returns {"appearance": CharacterAppearance, "draw_order": int}, with a null
## appearance and -1 order when the rig cannot answer. One instantiation for
## both, because building the scene is the expensive half of this and it happens
## every time a stage is opened.
func _read_miner_rig() -> Dictionary:
	var unresolved := {"appearance": null, "draw_order": -1}
	var rig_root := _MINER_RIG_SCENE.instantiate()
	var rig := rig_root as MinerRig
	if rig == null:
		rig_root.free()
		return unresolved
	# Exported references survive internal scene reparenting such as PoseRoot;
	# literal child paths do not.
	var miner_sprite := rig.drawn_miner_sprite
	var landing_foot_anchor := rig.landing_foot_anchor
	if miner_sprite == null or landing_foot_anchor == null:
		rig_root.free()
		return unresolved

	var appearance := CharacterAppearance.new()
	appearance.texture = miner_sprite.texture
	if appearance.texture == null:
		appearance.texture = rig.idle_miner_texture
	appearance.horizontal_frames = miner_sprite.hframes
	appearance.vertical_frames = miner_sprite.vframes
	appearance.frame = miner_sprite.frame
	appearance.sprite_scale = miner_sprite.scale
	appearance.sprite_offset = (
		miner_sprite.position - landing_foot_anchor.position
	)
	appearance.tint = miner_sprite.modulate
	appearance.flip_h = miner_sprite.flip_h

	# The cutscene order, not the mining one: what the editor draws has to be
	# what the encounter will actually show, and a cutscene lifts him in front
	# of the foreground layer.
	var cutscene_draw_order: Variant = rig.get("cutscene_draw_order")
	rig_root.free()
	if cutscene_draw_order == null:
		return unresolved
	return {
		"appearance": appearance,
		"draw_order": int(cutscene_draw_order),
	}


func _on_populate_from_encounter_pressed() -> void:
	populate_from_encounter()


func _on_show_miner_pressed() -> void:
	show_miner()


func _on_cast_changed() -> void:
	_rebuild()


func _connect_editor_selection() -> void:
	if not Engine.is_editor_hint():
		return
	var selection = EditorInterface.get_selection()
	if (
		selection != null
		and not selection.selection_changed.is_connected(
			_on_editor_selection_changed
		)
	):
		selection.selection_changed.connect(_on_editor_selection_changed)


func _on_editor_selection_changed() -> void:
	if _syncing_editor_selection:
		return
	_refresh_selection_from_editor()
	_refresh_selection_checks()


func _refresh_selection_from_editor() -> void:
	if not Engine.is_editor_hint() or not _has_valid_context():
		return
	var selection = EditorInterface.get_selection()
	if selection == null:
		return
	_selected_stage_nodes.clear()
	_selected_preview = null
	for selected: Node in selection.get_selected_nodes():
		var selected_2d := selected as Node2D
		if (
			selected_2d != null
			and _context.is_stage_manipulable(selected_2d)
		):
			_selected_stage_nodes.append(selected_2d)
			if selected_2d is CutsceneActorPreview:
				_selected_preview = selected_2d


func _prune_selected_stage_nodes() -> void:
	var valid_nodes: Array[Node2D] = []
	for selected in _selected_stage_nodes:
		if (
			is_instance_valid(selected)
			and _context != null
			and _context.is_stage_manipulable(selected)
		):
			valid_nodes.append(selected)
	_selected_stage_nodes = valid_nodes
	if (
		is_instance_valid(_selected_preview)
		and not _selected_stage_nodes.has(_selected_preview)
	):
		_selected_preview = null


func _refresh_selection_checks() -> void:
	for instance_id: int in _selection_checks:
		var check := _selection_checks[instance_id]
		if not is_instance_valid(check):
			continue
		var selected := false
		for node in _selected_stage_nodes:
			if node.get_instance_id() == instance_id:
				selected = true
				break
		check.set_pressed_no_signal(selected)


## Public selection seam used by editor actions and standalone verification.
func set_selected_stage_nodes(nodes: Array[Node2D]) -> void:
	_selected_stage_nodes.clear()
	if _context != null:
		for node in nodes:
			if (
				is_instance_valid(node)
				and _context.is_stage_manipulable(node)
				and not _selected_stage_nodes.has(node)
			):
				_selected_stage_nodes.append(node)
	_selected_preview = null
	for selected in _selected_stage_nodes:
		if selected is CutsceneActorPreview:
			_selected_preview = selected
			break
	_sync_editor_selection()
	_refresh_selection_checks()


func get_selected_stage_nodes() -> Array[Node2D]:
	_refresh_selection_from_editor()
	_prune_selected_stage_nodes()
	return _selected_stage_nodes.duplicate()


func _sync_editor_selection() -> void:
	if not Engine.is_editor_hint():
		return
	var selection = EditorInterface.get_selection()
	if selection == null:
		return
	_syncing_editor_selection = true
	selection.clear()
	for node in _selected_stage_nodes:
		selection.add_node(node)
	_syncing_editor_selection = false


func _on_stage_item_toggled(selected: bool, node: Node2D) -> void:
	if not is_instance_valid(node):
		return
	var next_selection := get_selected_stage_nodes()
	if selected and not next_selection.has(node):
		next_selection.append(node)
	elif not selected:
		next_selection.erase(node)
	set_selected_stage_nodes(next_selection)


func _on_stage_item_row_pressed(node: Node2D) -> void:
	if not is_instance_valid(node):
		return
	set_selected_stage_nodes([node])


func _on_select_all_pressed() -> void:
	if not _has_valid_context():
		return
	set_selected_stage_nodes(_context.get_stage_manipulable_nodes())
	_set_status("Selected %d stage objects." % _selected_stage_nodes.size())


func _on_clear_selection_pressed() -> void:
	set_selected_stage_nodes([])
	_set_status("Stage selection cleared.")


func _on_add_actor_pressed() -> void:
	if not _has_valid_context():
		return
	var choice_index := _actor_choice.selected
	if choice_index < 0 or choice_index >= _actor_choice_entries.size():
		_set_status("Pick a character to add.")
		return
	var choice := _actor_choice_entries[choice_index]
	var actor_id: StringName = choice.get("actor_id", &"")
	if String(actor_id).is_empty():
		_set_status("Pick a character to add.")
		return
	if _context.get_stage_actor_ids().has(String(actor_id)):
		_set_status("%s is already in this cutscene." % actor_id)
		return
	var appearance: CharacterAppearance = choice.get("appearance")
	if appearance == null:
		_set_status(
			"%s has no artwork authored yet, so there is nothing to show."
			% actor_id
		)
		return

	var actor := CutsceneActorPreview.new()
	actor.name = _make_unique_child_name(_context.stage, String(actor_id))
	actor.actor_id = actor_id
	actor.appearance = appearance
	# Same order the populated cast gets, so a hand-added character stands in
	# front of the floor rather than behind it.
	actor.z_index = _read_miner_rig().get("draw_order", 0)
	var conversation_marker := _get_conversation_marker()
	if conversation_marker != null:
		actor.position = _context.stage.to_local(
			conversation_marker.global_position
		)
	var undo_redo: Variant = _get_undo_redo()
	undo_redo.create_action("Add cutscene actor")
	undo_redo.add_do_method(
		_context.stage,
		&"add_child",
		actor
	)
	undo_redo.add_do_property(actor, &"owner", _context.scene_root)
	undo_redo.add_do_method(actor, &"_sync_sprite_owner")
	undo_redo.add_undo_method(
		_context,
		&"notify_cast_changed"
	)
	undo_redo.add_undo_method(_context.stage, &"remove_child", actor)
	undo_redo.add_do_reference(actor)
	undo_redo.add_do_method(
		_context,
		&"notify_cast_changed"
	)
	undo_redo.commit_action()
	_selected_preview = actor
	_on_stage_item_row_pressed(actor)


func _on_remove_selected_actors_pressed() -> void:
	if not _has_valid_context():
		return
	var removals: Array[CutsceneActorPreview] = []
	for selected in get_selected_stage_nodes():
		var preview := selected as CutsceneActorPreview
		if preview != null and preview.get_parent() != null:
			removals.append(preview)
	if removals.is_empty():
		_set_status("Select one or more actor stand-ins to remove.")
		return
	var undo_redo: Variant = _get_undo_redo()
	undo_redo.create_action(
		"Remove cutscene actor"
		if removals.size() == 1
		else "Remove cutscene actors"
	)
	undo_redo.add_undo_method(
		_context,
		&"notify_cast_changed"
	)
	for preview in removals:
		var parent := preview.get_parent()
		undo_redo.add_do_method(parent, &"remove_child", preview)
		undo_redo.add_undo_method(parent, &"add_child", preview)
	undo_redo.add_do_method(
		_context,
		&"notify_cast_changed"
	)
	undo_redo.commit_action()
	_selected_stage_nodes.clear()
	_selected_preview = null


## Aligns two or more selected actor/prop origins in stage space and returns the
## number that moved.
func align_selected(mode: AlignMode) -> int:
	var selected := get_selected_stage_nodes()
	if selected.size() < 2:
		_set_status("Select at least two actors or props to align.")
		return 0
	var positions: Dictionary[Node2D, Vector2] = {}
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for node in selected:
		var position := _context.get_stage_local_position(node)
		if not _is_finite_vector(position):
			continue
		positions[node] = position
		minimum = minimum.min(position)
		maximum = maximum.max(position)
	if positions.size() < 2:
		_set_status("The selected objects do not have usable stage positions.")
		return 0
	var target := Vector2.ZERO
	match mode:
		AlignMode.LEFT:
			target.x = minimum.x
		AlignMode.HORIZONTAL_CENTER:
			target.x = (minimum.x + maximum.x) * 0.5
		AlignMode.RIGHT:
			target.x = maximum.x
		AlignMode.TOP:
			target.y = minimum.y
		AlignMode.VERTICAL_CENTER:
			target.y = (minimum.y + maximum.y) * 0.5
		AlignMode.BOTTOM:
			target.y = maximum.y
	var targets: Dictionary[Node2D, Vector2] = {}
	for node in positions:
		var position: Vector2 = positions[node]
		if mode in [
			AlignMode.LEFT,
			AlignMode.HORIZONTAL_CENTER,
			AlignMode.RIGHT,
		]:
			position.x = target.x
		else:
			position.y = target.y
		targets[node] = position
	var changed := _commit_stage_positions(targets, "Align cutscene staging")
	_set_status("Aligned %d selected objects." % changed)
	return changed


## Evenly distributes three or more selected origins while preserving the
## outer two positions.
func distribute_selected(axis: DistributeAxis) -> int:
	var selected := get_selected_stage_nodes()
	if selected.size() < 3:
		_set_status("Select at least three actors or props to distribute.")
		return 0
	var ordered: Array[Node2D] = []
	for node in selected:
		if _is_finite_vector(_context.get_stage_local_position(node)):
			ordered.append(node)
	if ordered.size() < 3:
		_set_status("The selected objects do not have usable stage positions.")
		return 0
	_sort_nodes_by_axis(ordered, axis)
	var first := _context.get_stage_local_position(ordered.front())
	var last := _context.get_stage_local_position(ordered.back())
	var span := last.x - first.x
	if axis == DistributeAxis.VERTICAL:
		span = last.y - first.y
	var step := span / float(ordered.size() - 1)
	var targets: Dictionary[Node2D, Vector2] = {}
	for index in range(1, ordered.size() - 1):
		var node := ordered[index]
		var position := _context.get_stage_local_position(node)
		if axis == DistributeAxis.HORIZONTAL:
			position.x = first.x + step * float(index)
		else:
			position.y = first.y + step * float(index)
		targets[node] = position
	var changed := _commit_stage_positions(
		targets,
		"Distribute cutscene staging"
	)
	_set_status("Distributed %d selected objects." % ordered.size())
	return changed


## Snaps every selected origin to the first logical terrain surface below it.
func snap_selected_to_floor() -> int:
	var selected := get_selected_stage_nodes()
	if selected.is_empty():
		_set_status("Select actors or props to snap to the floor.")
		return 0
	var targets: Dictionary[Node2D, Vector2] = {}
	var unresolved := 0
	for node in selected:
		var target := _context.get_floor_snap_stage_position(node)
		if not _is_finite_vector(target):
			unresolved += 1
			continue
		targets[node] = target
	var changed := _commit_stage_positions(
		targets,
		"Snap cutscene staging to floor"
	)
	if unresolved > 0:
		_set_status(
			"Snapped %d; %d had no sculpted floor below them."
			% [changed, unresolved]
		)
	else:
		_set_status("Snapped %d selected objects to the floor." % changed)
	return changed


## Captures each selected actor into the current MOVE beat's authored start.
func record_selected_positions_as_start() -> int:
	return _request_selected_actor_positions(&"start")


## Captures each selected actor into the current MOVE beat's destination.
func record_selected_positions_as_destination() -> int:
	return _request_selected_actor_positions(&"destination")


## Requests one new MOVE beat per selected actor at its staged position.
func create_movements_from_selected_positions() -> int:
	return _request_selected_actor_positions(&"create")


func _request_selected_actor_positions(action: StringName) -> int:
	if not _has_valid_context():
		return 0
	var requested := 0
	for selected in get_selected_stage_nodes():
		var actor := selected as CutsceneActorPreview
		if actor == null:
			continue
		var accepted := false
		match action:
			&"start":
				accepted = _context.request_movement_start_position(actor)
			&"destination":
				accepted = _context.request_movement_destination_position(actor)
			&"create":
				accepted = _context.request_movement_beat_creation(actor)
		if accepted:
			requested += 1
	if requested == 0:
		_set_status("Select one or more actors; props do not own MOVE lanes.")
	else:
		_set_status(
			"Sent %d staged actor position%s to the timeline."
			% [requested, "" if requested == 1 else "s"]
		)
	return requested


func _commit_stage_positions(
	stage_targets: Dictionary[Node2D, Vector2],
	action_name: String
) -> int:
	if not _has_valid_context() or stage_targets.is_empty():
		return 0
	# Timeline scrubbing temporarily writes presentation positions onto the
	# same preview nodes. Restore their authored transforms before capturing
	# undo, while keeping the already-computed visible targets for the edit.
	_context.notify_stage_positions_will_change()
	var changes: Array[Dictionary] = []
	for node in stage_targets:
		if not is_instance_valid(node):
			continue
		var after := _context.stage_position_to_parent_position(
			node,
			stage_targets[node]
		)
		if not _is_finite_vector(after) or node.position.is_equal_approx(after):
			continue
		changes.append({
			"node": node,
			"before": node.position,
			"after": after,
		})
	if changes.is_empty():
		# The pre-change notification restored the playhead preview. Reapply it
		# even when every requested target already matched its authored value.
		_context.notify_cast_changed()
		return 0
	var undo_redo: Variant = _get_undo_redo()
	undo_redo.create_action(action_name)
	for change: Dictionary in changes:
		var node: Node2D = change["node"]
		undo_redo.add_do_property(node, &"position", change["after"])
		undo_redo.add_undo_property(node, &"position", change["before"])
	if undo_redo is UndoRedo:
		undo_redo.add_do_method(
			Callable(_context, &"notify_cast_changed")
		)
		undo_redo.add_undo_method(
			Callable(_context, &"notify_cast_changed")
		)
	else:
		undo_redo.add_do_method(_context, &"notify_cast_changed")
		undo_redo.add_undo_method(_context, &"notify_cast_changed")
	undo_redo.commit_action()
	return changes.size()


func _sort_nodes_by_axis(
	nodes: Array[Node2D],
	axis: DistributeAxis
) -> void:
	for right_index in range(1, nodes.size()):
		var node := nodes[right_index]
		var node_position := _context.get_stage_local_position(node)
		var left_index := right_index - 1
		while left_index >= 0:
			var left_position := _context.get_stage_local_position(
				nodes[left_index]
			)
			var belongs_before := (
				node_position.x < left_position.x
				if axis == DistributeAxis.HORIZONTAL
				else node_position.y < left_position.y
			)
			if not belongs_before:
				break
			nodes[left_index + 1] = nodes[left_index]
			left_index -= 1
		nodes[left_index + 1] = node


func _is_finite_vector(value: Vector2) -> bool:
	return (
		not is_nan(value.x)
		and not is_inf(value.x)
		and not is_nan(value.y)
		and not is_inf(value.y)
	)


func _on_align_pressed(mode: AlignMode) -> void:
	align_selected(mode)


func _on_distribute_pressed(axis: DistributeAxis) -> void:
	distribute_selected(axis)


func _on_snap_to_floor_pressed() -> void:
	snap_selected_to_floor()


func _on_record_start_pressed() -> void:
	record_selected_positions_as_start()


func _on_record_destination_pressed() -> void:
	record_selected_positions_as_destination()


func _on_create_movement_pressed() -> void:
	create_movements_from_selected_positions()


func _on_add_prop_pressed() -> void:
	if not _has_valid_context():
		return
	var choice_index := _prop_choice.selected
	if choice_index < 0 or choice_index >= _prop_choice_paths.size():
		_set_status("Pick a prop to add.")
		return
	var prop_path: String = _prop_choice_paths[choice_index]
	var prop_scene: PackedScene = load(prop_path)
	if prop_scene == null:
		_set_status("'%s' could not be loaded." % prop_path.get_file())
		return
	# Named after the scene rather than typed. The name only has to be unique
	# and recognisable in the Scene dock, and _make_unique_child_name already
	# guarantees the first of those.
	var prop_name := prop_path.get_file().get_basename().to_pascal_case()
	var prop_root := _get_stage_root(&"PropMarkers")
	if prop_root == null:
		_set_status("This stage has no PropMarkers root.")
		return
	var prop := prop_scene.instantiate()
	if prop == null:
		_set_status("The selected prop scene could not be instantiated.")
		return
	prop.name = _make_unique_child_name(prop_root, prop_name)
	# Stepped along the floor by however much scenery is already there. Every
	# prop dropped at the origin lands on the miner and on each other, so a
	# second one looks like the first simply failed to appear.
	var prop_2d := prop as Node2D
	if prop_2d != null:
		prop_2d.position = Vector2(
			_PROP_PLACEMENT_STEP_PIXELS * float(prop_root.get_child_count()),
			0.0
		)
	var undo_redo: Variant = _get_undo_redo()
	undo_redo.create_action("Add cutscene prop")
	undo_redo.add_do_method(prop_root, &"add_child", prop)
	undo_redo.add_do_property(prop, &"owner", _context.scene_root)
	undo_redo.add_undo_method(
		_context,
		&"notify_cast_changed"
	)
	undo_redo.add_undo_method(prop_root, &"remove_child", prop)
	undo_redo.add_do_reference(prop)
	undo_redo.add_do_method(
		_context,
		&"notify_cast_changed"
	)
	undo_redo.commit_action()
	if prop_2d != null:
		set_selected_stage_nodes([prop_2d])


func _on_add_marker_pressed() -> void:
	if not _has_valid_context():
		return
	var marker_name := _get_chosen_marker_name()
	if marker_name.is_empty():
		_set_status("Name the spot before adding it.")
		return
	if _context.get_marker_names().has(marker_name):
		_set_status("'%s' already exists on this stage." % marker_name)
		return
	var root_index := _marker_root_selector.selected
	var marker_root := _get_stage_root(_MARKER_ROOT_NAMES[root_index])
	if marker_root == null:
		_set_status("This stage has no selected marker root.")
		return
	var marker := Marker2D.new()
	marker.name = _make_unique_child_name(marker_root, marker_name)
	var undo_redo: Variant = _get_undo_redo()
	undo_redo.create_action("Add cutscene marker")
	undo_redo.add_do_method(marker_root, &"add_child", marker)
	undo_redo.add_do_property(marker, &"owner", _context.scene_root)
	undo_redo.add_undo_method(
		_context,
		&"notify_cast_changed"
	)
	undo_redo.add_undo_method(marker_root, &"remove_child", marker)
	undo_redo.add_do_reference(marker)
	undo_redo.add_do_method(
		_context,
		&"notify_cast_changed"
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
