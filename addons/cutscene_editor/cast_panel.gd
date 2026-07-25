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
const _MINER_RIG_SCENE := preload("res://Scenes/mining/miner_rig.tscn")

var _context: CutsceneEditorContext
var _status_label: Label
var _actor_choice: OptionButton
## Parallel to _actor_choice's items: {"actor_id": StringName, "appearance":
## CharacterAppearance} per entry, so a pick resolves without reparsing labels.
var _actor_choice_entries: Array[Dictionary] = []
var _prop_picker: EditorResourcePicker
var _prop_name_edit: LineEdit
var _marker_root_selector: OptionButton
var _marker_name_edit: LineEdit
var _selected_preview: CutsceneActorPreview
var _standalone_test_undo_redo: UndoRedo


func _init() -> void:
	name = &"Cast"
	_rebuild()


## Rebinds the panel to one open stage, or shows a safe empty state.
func set_context(context: CutsceneEditorContext) -> void:
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
	if (
		_context != null
		and not _context.cast_changed.is_connected(
			_on_cast_changed
		)
	):
		_context.cast_changed.connect(_on_cast_changed)
	_rebuild()


## Supplies the base UndoRedo used only by standalone verification, where the
## editor's abstract manager cannot be constructed outside an editor process.
func set_standalone_test_undo_redo(undo_redo: UndoRedo) -> void:
	_standalone_test_undo_redo = undo_redo
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
	_actor_choice = null
	_actor_choice_entries.clear()
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
	# MinerRig's cutscene order is z 3 while terrain stratum one is z 2, so the
	# editor shows him standing clear of the foreground rock, which is what the
	# encounter itself will draw.
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
	var miner_sprite := rig_root.get_node_or_null(
		"VisualRoot/DrawnMinerSprite"
	) as Sprite2D
	var landing_foot_anchor := rig_root.get_node_or_null(
		"VisualRoot/LandingFootAnchor"
	) as Marker2D
	if rig == null or miner_sprite == null or landing_foot_anchor == null:
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
	_on_actor_row_pressed(actor)


func _on_remove_actor_pressed() -> void:
	if not _has_valid_context():
		return
	var preview := _get_selected_actor_preview()
	if preview == null or preview.get_parent() == null:
		_set_status("Select an actor stand-in to remove it.")
		return
	var parent := preview.get_parent()
	var undo_redo: Variant = _get_undo_redo()
	undo_redo.create_action("Remove cutscene actor")
	undo_redo.add_do_method(parent, &"remove_child", preview)
	undo_redo.add_do_method(
		_context,
		&"notify_cast_changed"
	)
	undo_redo.add_undo_method(
		_context,
		&"notify_cast_changed"
	)
	undo_redo.add_undo_method(parent, &"add_child", preview)
	undo_redo.commit_action()
	_selected_preview = null


func _get_selected_actor_preview() -> CutsceneActorPreview:
	var selection = EditorInterface.get_selection()
	if selection != null:
		for selected: Node in selection.get_selected_nodes():
			if selected is CutsceneActorPreview:
				return selected
	if is_instance_valid(_selected_preview):
		return _selected_preview
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
