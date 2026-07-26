@tool
class_name CutsceneManagerPanel
extends VBoxContainer

## How it works:
## - Reads the run schedule through the shared editor context.
## - Produces plain row and summary data, then renders the same data in a table.
## - Owns only that derived data and the compact table controls.
## - Selecting a row changes the preview encounter for every editor panel.
## - Missing rooms remain valid generated chambers, not validation failures.
## The invariant is that every visible row maps to exactly one scheduled
## encounter and keeps the schedule's resolved depth order.

const _COLUMN_CUTSCENE: int = 0
const _COLUMN_DEPTH: int = 1
const _COLUMN_ROOM: int = 2
const _COLUMN_SEQUENCE: int = 3
const _COLUMN_STAGE: int = 4
const _COLUMN_CONVERSATION: int = 5
const _COLUMN_APPEARANCE: int = 6
const _COLUMN_STATUS: int = 7
const _COLUMN_COUNT: int = 8

const _HEALTHY_COLOR: Color = Color(0.58, 0.86, 0.62)
const _UNAUTHORED_COLOR: Color = Color(0.80, 0.72, 0.48)
const _PROBLEM_COLOR: Color = Color(1.0, 0.48, 0.42)

var _context: CutsceneEditorContext
var _summary_label: Label
var _table: Tree
var _row_data: Array[Dictionary] = []
var _summary_data: Dictionary = {}
var _is_rebuilding: bool = false


func _init() -> void:
	name = "Manager"

	_summary_label = Label.new()
	_summary_label.tooltip_text = (
		"Authored means the encounter has its own room. Generated means it "
		+ "still uses the procedural chamber. Problems are authored rows whose "
		+ "existing room, landing, sequence, or conversation checks fail."
	)
	add_child(_summary_label)

	_table = Tree.new()
	_table.columns = _COLUMN_COUNT
	_table.column_titles_visible = true
	_table.hide_root = true
	_table.select_mode = Tree.SELECT_ROW
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table.custom_minimum_size.y = 150.0
	_table.tooltip_text = (
		"Select a row to make every cutscene editor tab author that encounter."
	)
	var titles: Array[String] = [
		"Cutscene",
		"Depth",
		"Room",
		"Sequence",
		"Stage",
		"Conversation",
		"Appearance",
		"Status",
	]
	for column_index: int in range(titles.size()):
		_table.set_column_title(column_index, titles[column_index])
	_table.set_column_expand(_COLUMN_CUTSCENE, true)
	_table.set_column_expand_ratio(_COLUMN_CUTSCENE, 2)
	_table.set_column_expand(_COLUMN_DEPTH, false)
	_table.set_column_custom_minimum_width(_COLUMN_DEPTH, 62)
	_table.set_column_expand(_COLUMN_ROOM, true)
	_table.set_column_expand_ratio(_COLUMN_ROOM, 2)
	_table.set_column_expand(_COLUMN_SEQUENCE, false)
	_table.set_column_custom_minimum_width(_COLUMN_SEQUENCE, 82)
	for column_index: int in [
		_COLUMN_STAGE,
		_COLUMN_CONVERSATION,
		_COLUMN_APPEARANCE,
	]:
		_table.set_column_expand(column_index, false)
		_table.set_column_custom_minimum_width(column_index, 88)
	_table.set_column_expand(_COLUMN_STATUS, true)
	_table.set_column_expand_ratio(_COLUMN_STATUS, 3)
	if not _table.item_selected.is_connected(_on_row_selected):
		_table.item_selected.connect(_on_row_selected)
	if not _table.item_activated.is_connected(_on_row_activated):
		_table.item_activated.connect(_on_row_activated)
	add_child(_table)
	_refresh()


## Rebinds the overview to the scene context shared by every editor panel.
func set_context(context: CutsceneEditorContext) -> void:
	if (
		_context != null
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
	_refresh()


## Returns a detached plain-data snapshot in displayed depth order.
func get_row_data() -> Array[Dictionary]:
	var copied_rows: Array[Dictionary] = []
	for row: Dictionary in _row_data:
		copied_rows.append(row.duplicate(true))
	return copied_rows


## Returns counts derived from the same rows the table displays.
func get_summary_data() -> Dictionary:
	return _summary_data.duplicate(true)


func _refresh() -> void:
	_is_rebuilding = true
	_row_data.clear()
	_summary_data = {
		"encounter_count": 0,
		"authored_count": 0,
		"generated_count": 0,
		"problem_count": 0,
	}
	_table.clear()
	var root_item: TreeItem = _table.create_item()
	if _context == null or not _context.is_valid():
		_summary_label.text = "Open a cutscene stage to review the run."
		var empty_item: TreeItem = _table.create_item(root_item)
		empty_item.set_text(_COLUMN_CUTSCENE, "No cutscene context")
		_is_rebuilding = false
		return

	var schedule: DepthEncounterConfig = _context.preview.get_encounter_config()
	if schedule == null:
		_summary_label.text = "Encounter schedule could not be loaded."
		var error_item: TreeItem = _table.create_item(root_item)
		error_item.set_text(_COLUMN_CUTSCENE, "Schedule unavailable")
		_is_rebuilding = false
		return

	var mining_config: MiningConfig = null
	if (
		is_instance_valid(_context.preview.terrain_manager)
		and _context.preview.terrain_manager.config != null
	):
		mining_config = _context.preview.terrain_manager.config
	var total_run_depth: int = (
		mining_config.total_run_depth if mining_config != null else 0
	)
	var scheduled: Array[DepthCharacterEncounter] = []
	for encounter: DepthCharacterEncounter in schedule.encounters:
		if encounter == null:
			continue
		var depth: int = _resolve_depth(encounter, total_run_depth)
		var insertion_index: int = scheduled.size()
		while insertion_index > 0:
			var previous: DepthCharacterEncounter = scheduled[
				insertion_index - 1
			]
			if _resolve_depth(previous, total_run_depth) <= depth:
				break
			insertion_index -= 1
		scheduled.insert(insertion_index, encounter)

	var authored_count: int = 0
	var generated_count: int = 0
	var problem_count: int = 0
	for encounter: DepthCharacterEncounter in scheduled:
		var row: Dictionary = _build_row_data(
			encounter,
			_resolve_depth(encounter, total_run_depth),
			mining_config
		)
		_row_data.append(row)
		authored_count += 1 if row["authored"] else 0
		generated_count += 1 if not row["authored"] else 0
		problem_count += 1 if row["problem"] else 0
		var item: TreeItem = _table.create_item(root_item)
		_populate_item(item, row)
		if (
			_context.preview.encounter_id
			== StringName(row["encounter_id"])
		):
			item.select(_COLUMN_CUTSCENE)

	_summary_data = {
		"encounter_count": _row_data.size(),
		"authored_count": authored_count,
		"generated_count": generated_count,
		"problem_count": problem_count,
	}
	_summary_label.text = (
		"%d encounters: %d authored, %d generated chamber, %d problems."
		% [
			_row_data.size(),
			authored_count,
			generated_count,
			problem_count,
		]
	)
	_is_rebuilding = false


func _resolve_depth(
	encounter: DepthCharacterEncounter,
	total_run_depth: int
) -> int:
	if encounter.occurs_at_run_bottom and total_run_depth > 0:
		return encounter.resolve_depth(total_run_depth)
	return encounter.depth_from_surface


func _build_row_data(
	encounter: DepthCharacterEncounter,
	depth: int,
	mining_config: MiningConfig
) -> Dictionary:
	var sculpt: CutsceneTerrainSculpt = encounter.terrain_sculpt
	var sequence: CutsceneSequence = encounter.sequence
	var row: Dictionary = {
		"encounter_id": String(encounter.encounter_id),
		"depth": depth,
		"is_run_bottom": encounter.occurs_at_run_bottom,
		"authored": sculpt != null,
		"has_room": sculpt != null,
		"open_cells": -1,
		"total_cells": 0,
		"open_percent": -1,
		"sculpt_error": "",
		"landing_checked": false,
		"landing_error": "",
		"has_sequence": sequence != null,
		"sequence_duration_seconds": (
			sequence.get_duration_seconds() if sequence != null else 0.0
		),
		"sequence_error": "",
		"has_stage_scene": encounter.stage_scene != null,
		"has_conversation": encounter.conversation != null,
		"has_appearance": encounter.appearance != null,
		"status_kind": "unauthored",
		"status_message": "Unauthored - generated chamber",
		"problem": false,
	}
	# The generated chamber is an intentional fallback. No authored resource
	# exists to validate, so other missing authoring does not turn it red.
	if sculpt == null:
		return row

	var total_cells: int = sculpt.grid_size.x * sculpt.grid_size.y
	var sculpt_error: String = sculpt.get_sculpt_error()
	row["total_cells"] = total_cells
	row["sculpt_error"] = sculpt_error
	if sculpt_error.is_empty():
		var open_cells: int = sculpt.get_open_cell_count()
		row["open_cells"] = open_cells
		row["open_percent"] = roundi(
			100.0 * float(open_cells) / float(maxi(total_cells, 1))
		)

	var landing_error: String = ""
	if sculpt_error.is_empty() and mining_config != null:
		row["landing_checked"] = true
		landing_error = _get_landing_error(
			sculpt,
			mining_config.snake_half_span_cells
		)
		row["landing_error"] = landing_error

	var sequence_error: String = ""
	if sequence != null:
		# The manager has resources for every stage, but only the currently
		# open stage has instantiated cast nodes. Supplying the ids referenced
		# by this sequence preserves all resource-local validation without
		# inventing a second actor-roster rule.
		var errors: PackedStringArray = sequence.validate(
			sequence.get_actor_ids()
		)
		if not errors.is_empty():
			sequence_error = String(errors[0])
			row["sequence_error"] = sequence_error

	var status_message: String = "Healthy"
	if not sculpt_error.is_empty():
		status_message = sculpt_error
	elif not landing_error.is_empty():
		status_message = landing_error
	elif not sequence_error.is_empty():
		status_message = "Sequence: %s" % sequence_error
	elif encounter.conversation == null and not encounter.occurs_at_run_bottom:
		status_message = "Conversation is missing."

	row["status_kind"] = (
		"healthy" if status_message == "Healthy" else "problem"
	)
	row["status_message"] = status_message
	row["problem"] = status_message != "Healthy"
	return row


## Applies the sculpt panel's landing rule: every entry column must open, and
## no ledge may catch the miner above the encounter floor.
func _get_landing_error(
	sculpt: CutsceneTerrainSculpt,
	half_span_cells: int
) -> String:
	var landing_rows: PackedInt32Array = sculpt.get_landing_local_rows(
		half_span_cells
	)
	if landing_rows.is_empty():
		return "Landing: the room does not contain its own floor row."
	var floor_row: int = sculpt.get_floor_local_row()
	var highest_landing: int = floor_row
	var sealed_columns: int = 0
	for landing_row: int in landing_rows:
		if landing_row < 0:
			sealed_columns += 1
			continue
		highest_landing = mini(highest_landing, landing_row)
	if sealed_columns > 0:
		return (
			"Landing: %d entry columns have no opening to fall into."
			% sealed_columns
		)
	if highest_landing < floor_row:
		return (
			"Landing: a ledge catches the miner %d rows above the floor."
			% (floor_row - highest_landing)
		)
	return ""


func _populate_item(item: TreeItem, row: Dictionary) -> void:
	var room_text: String = "generated"
	if row["has_room"]:
		room_text = (
			"%d%% open / clear" % row["open_percent"]
			if String(row["sculpt_error"]).is_empty()
			else "room error"
		)
	var sequence_text: String = (
		"%.1fs" % row["sequence_duration_seconds"]
		if row["has_sequence"]
		else "-"
	)
	var values: Array[String] = [
		String(row["encounter_id"]),
		"%d" % row["depth"],
		room_text,
		sequence_text,
		"yes" if row["has_stage_scene"] else "-",
		"yes" if row["has_conversation"] else "-",
		"yes" if row["has_appearance"] else "-",
		String(row["status_message"]),
	]
	for column_index: int in range(values.size()):
		item.set_text(column_index, values[column_index])
	item.set_metadata(_COLUMN_CUTSCENE, row["encounter_id"])
	item.set_tooltip_text(
		_COLUMN_CUTSCENE,
		"Select this row to author '%s' in every tab." % row["encounter_id"]
	)
	item.set_tooltip_text(
		_COLUMN_DEPTH,
		"Resolved gameplay depth%s."
		% (" at the run bottom" if row["is_run_bottom"] else "")
	)
	item.set_tooltip_text(
		_COLUMN_ROOM,
		(
			"Authored room: %d of %d cells open. Sculpt validation is clear."
			% [row["open_cells"], row["total_cells"]]
			if row["has_room"] and String(row["sculpt_error"]).is_empty()
			else (
				String(row["sculpt_error"])
				if row["has_room"]
				else "No terrain sculpt; gameplay uses the generated chamber."
			)
		)
	)
	item.set_tooltip_text(
		_COLUMN_STATUS,
		String(row["status_message"])
	)
	var status_color: Color = _HEALTHY_COLOR
	if row["status_kind"] == "unauthored":
		status_color = _UNAUTHORED_COLOR
	elif row["status_kind"] == "problem":
		status_color = _PROBLEM_COLOR
	item.set_custom_color(_COLUMN_STATUS, status_color)


## Highlights a row and nothing more.
##
## This used to repoint the open scene's preview at whichever cutscene was
## clicked, from back when one shared stage previewed them all. Every cutscene
## now has its own scene, so that write did real damage: clicking down the
## overview silently changed the open stage's Encounter Id and left it dirty, so
## Cheese Girl's scene ended up claiming to be Rotini's. Double-click opens the
## right scene; single-click selects, and selecting must not edit.
func _on_row_selected() -> void:
	pass


## Opens the double-clicked cutscene's own stage scene, so the overview is how a
## designer moves between cutscenes instead of a table they read and then go
## hunting the FileSystem dock for the matching scene. Opening the scene is what
## swaps the cast and the room: every panel rebuilds off scene_changed, so the
## whole editor follows the double-click rather than just this table's selection.
func _on_row_activated() -> void:
	var selected: TreeItem = _table.get_selected()
	if selected == null:
		return
	var metadata: Variant = selected.get_metadata(_COLUMN_CUTSCENE)
	var encounter_id := StringName(String(metadata))
	if encounter_id.is_empty():
		return
	var encounter := _find_scheduled_encounter(encounter_id)
	if encounter == null:
		return
	if encounter.stage_scene == null:
		_set_status(
			"'%s' has no stage scene to open yet." % encounter_id
		)
		return
	var scene_path := encounter.stage_scene.resource_path
	if scene_path.is_empty():
		_set_status(
			"'%s' has a stage scene that was never saved to disk." % encounter_id
		)
		return
	# Already open: reselecting it in the preview is all that is left to do, and
	# reopening would throw away whatever is unsaved in it.
	if EditorInterface.get_edited_scene_root() != null and (
		EditorInterface.get_edited_scene_root().scene_file_path == scene_path
	):
		_on_row_selected()
		return
	EditorInterface.open_scene_from_path(scene_path)


## Reports why a double-click could not open a cutscene. The next refresh
## rewrites this line with the run summary, which is the right lifetime for it:
## the message belongs to the click, not to the overview.
func _set_status(message: String) -> void:
	if is_instance_valid(_summary_label):
		_summary_label.text = message


## Returns one scheduled encounter by id, or null when the open stage's schedule
## does not carry it.
func _find_scheduled_encounter(
	encounter_id: StringName
) -> DepthCharacterEncounter:
	if _context == null or not _context.is_valid():
		return null
	var schedule: DepthEncounterConfig = _context.preview.get_encounter_config()
	if schedule == null:
		return null
	for encounter: DepthCharacterEncounter in schedule.encounters:
		if encounter != null and encounter.encounter_id == encounter_id:
			return encounter
	return null


func _on_authored_data_changed() -> void:
	_refresh()
