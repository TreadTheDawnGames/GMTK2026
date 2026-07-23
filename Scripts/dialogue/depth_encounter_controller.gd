class_name DepthEncounterController
extends Node

## Runs the authored character encounters in their listed depth order.

signal final_encounter_reached(encounter_id: StringName)
signal departure_choice_requested

@export_category("Schedule")
@export var encounter_config: DepthEncounterConfig
@export var mining_config: MiningConfig

@export_category("Character Placement")
@export_range(-64, 64, 1) var horizontal_offset_cells: int = 22

@export_category("References")
@export var dialogue_director: DialogueDirector
@export var timing_window: TimingWindowTask
@export var merchant_scene: PackedScene
@export var merchant_parent: Node2D
@export var pickaxe_progression: PickaxeProgression
@export var mining_controller: MiningController

var _presenters: Array[MerchantPresenter] = []
var _next_encounter_index: int = 0
var _pending_encounter_index: int = -1
var _active_encounter_index: int = -1
var _is_initialized: bool = false
var _is_waiting_for_departure_choice: bool = false
var _active_conversation: DialogueConversation


## Creates every authored character before the player reaches their room.
func _ready() -> void:
	if not _prepare_authored_characters():
		return
	_is_initialized = true


## Pauses mining when the player reaches the next authored floor.
func _on_depth_changed(depth: int) -> void:
	if (
		not _is_initialized
		or _is_waiting_for_departure_choice
		or _active_encounter_index >= 0
		or _pending_encounter_index >= 0
		or _next_encounter_index >= encounter_config.encounters.size()
	):
		return
	var encounter := encounter_config.encounters[_next_encounter_index]
	if depth < encounter.resolve_depth(mining_config.total_run_depth):
		return

	_pending_encounter_index = _next_encounter_index
	timing_window.process_mode = Node.PROCESS_MODE_DISABLED
	mining_controller.set_swing_queue_paused(true)


## Starts the pending encounter only after the miner lands on its floor.
func _on_landing_reached(_mining_y: int) -> void:
	if _pending_encounter_index < 0 or _active_encounter_index >= 0:
		return
	_active_encounter_index = _pending_encounter_index
	_pending_encounter_index = -1
	_begin_active_encounter.call_deferred()


## Keeps all authored characters attached to their terrain floors.
func _on_view_y_changed(view_y: float) -> void:
	var cell_size := float(mining_config.terrain_cell_world_size)
	var terrain_left := (
		mining_config.terrain_screen_center_x
		- float(mining_config.terrain_width_cells) * cell_size * 0.5
	)
	merchant_parent.position = Vector2(
		terrain_left,
		mining_config.mining_face_screen_y - view_y * cell_size
	)


## Bounces the active character while one of their lines is presented.
func _on_dialogue_line_presented(
	conversation_id: StringName,
	_line_index: int,
	speaker_slot: StringName
) -> void:
	if _active_encounter_index < 0:
		return
	var encounter := encounter_config.encounters[_active_encounter_index]
	if (
		_active_conversation == null
		or conversation_id != _active_conversation.conversation_id
	):
		return
	for presenter in _presenters:
		presenter.reset_speech_motion()
	if _is_departure_encounter(_active_encounter_index):
		for presenter_index in range(_active_encounter_index):
			if (
				encounter_config.encounters[
					presenter_index
				].speaker_slot == speaker_slot
			):
				_presenters[presenter_index].react_to_presented_line()
				return
	elif speaker_slot == encounter.speaker_slot:
		_presenters[
			_active_encounter_index
		].react_to_presented_line()


## Opens dialogue or stops at the unwritten thief endpoint.
func _begin_active_encounter() -> void:
	var encounter := encounter_config.encounters[_active_encounter_index]
	var presenter := _presenters[_active_encounter_index]
	presenter.reset_speech_motion()
	if _is_departure_encounter(_active_encounter_index):
		_gather_departing_characters()
	timing_window.hide()
	_active_conversation = encounter.conversation
	if (
		encounter.encrypted_conversation != null
		and encounter.encrypted_conversation.has_payload()
	):
		_active_conversation = (
			encounter.encrypted_conversation.decrypt_conversation()
		)
	if encounter.occurs_at_run_bottom and _active_conversation == null:
		final_encounter_reached.emit(encounter.encounter_id)
		return
	if (
		_active_conversation != null
		and dialogue_director.start_conversation(_active_conversation)
	):
		return
	push_error(
		"Encounter '%s' could not start dialogue." % encounter.encounter_id
	)
	presenter.reset_speech_motion()
	_active_conversation = null
	if encounter.occurs_at_run_bottom:
		final_encounter_reached.emit(encounter.encounter_id)
		return
	_next_encounter_index = _active_encounter_index + 1
	_active_encounter_index = -1
	_restore_timing_window()


## Reports whether this conversation is the cast's final shared stop.
func _is_departure_encounter(encounter_index: int) -> bool:
	var next_index := encounter_index + 1
	return (
		next_index < encounter_config.encounters.size()
		and encounter_config.encounters[next_index].occurs_at_run_bottom
	)


## Places the four named characters together for their departure warning.
func _gather_departing_characters() -> void:
	var departure_y := _presenters[_active_encounter_index].position.y
	var group_x_cells: Array[int] = [32, 48, 80, 96]
	for presenter_index in range(
		mini(_active_encounter_index, group_x_cells.size())
	):
		var presenter := _presenters[presenter_index]
		presenter.position = Vector2(
			float(group_x_cells[presenter_index])
				* float(mining_config.terrain_cell_world_size),
			departure_y
		)
		presenter.show()
	_presenters[_active_encounter_index].hide()


## Grants the authored reward and advances to the next listed encounter.
func _on_conversation_finished(conversation_id: StringName) -> void:
	if _active_encounter_index < 0:
		return
	var encounter := encounter_config.encounters[_active_encounter_index]
	if (
		_active_conversation == null
		or conversation_id != _active_conversation.conversation_id
	):
		return

	if (
		encounter.pickaxe_reward != null
		and not pickaxe_progression.grant_upgrade(
			encounter.pickaxe_reward
		)
	):
		push_error(
			"Encounter '%s' could not grant pickaxe '%s'."
			% [conversation_id, encounter.pickaxe_reward.id]
		)
	_presenters[_active_encounter_index].reset_speech_motion()
	_active_conversation = null
	if encounter.occurs_at_run_bottom:
		final_encounter_reached.emit(encounter.encounter_id)
		return

	_next_encounter_index = _active_encounter_index + 1
	_active_encounter_index = -1
	if (
		_next_encounter_index < encounter_config.encounters.size()
		and encounter_config.encounters[
			_next_encounter_index
		].occurs_at_run_bottom
	):
		_is_waiting_for_departure_choice = true
		departure_choice_requested.emit()
		return
	_restore_mining_after_buffer()


## Removes the departing cast and begins the solitary descent.
func continue_after_departure() -> void:
	if not _is_waiting_for_departure_choice:
		return
	_is_waiting_for_departure_choice = false
	for presenter_index in range(_next_encounter_index):
		_presenters[presenter_index].hide()
	_restore_mining_after_buffer()


## Restores mining immediately or after the shared authored pause.
func _restore_mining_after_buffer() -> void:
	if encounter_config.post_dialogue_buffer_seconds > 0.0:
		var restore_timer := get_tree().create_timer(
			encounter_config.post_dialogue_buffer_seconds,
			true
		)
		restore_timer.timeout.connect(
			_restore_timing_window,
			CONNECT_ONE_SHOT
		)
		return
	_restore_timing_window()


## Instantiates the small fixed roster and rejects broken authored entries.
func _prepare_authored_characters() -> bool:
	if (
		encounter_config == null
		or mining_config == null
		or dialogue_director == null
		or timing_window == null
		or merchant_scene == null
		or merchant_parent == null
		or pickaxe_progression == null
		or mining_controller == null
	):
		push_error("Character encounter references are incomplete.")
		return false
	if encounter_config.encounters.is_empty():
		push_error("At least one authored character encounter is required.")
		return false

	var previous_depth := -1
	var bottom_encounters := 0
	for encounter_index in range(encounter_config.encounters.size()):
		var encounter := encounter_config.encounters[encounter_index]
		if encounter == null or encounter.appearance == null:
			push_error(
				"Character encounter %d is incomplete."
				% (encounter_index + 1)
			)
			return false
		var encounter_depth := encounter.resolve_depth(
			mining_config.total_run_depth
		)
		if encounter_depth <= previous_depth:
			push_error("Character encounters must be listed by depth.")
			return false
		if (
			not encounter.occurs_at_run_bottom
			and encounter.conversation == null
		):
			push_error(
				"Encounter '%s' requires a conversation."
				% encounter.encounter_id
			)
			return false
		if encounter.occurs_at_run_bottom:
			if (
				encounter.conversation != null
				or encounter.encrypted_conversation == null
			):
				push_error(
					"Bottom encounter '%s' requires its encrypted dialogue resource."
					% encounter.encounter_id
				)
				return false
			bottom_encounters += 1
		previous_depth = encounter_depth
	if bottom_encounters != 1:
		push_error("Exactly one encounter must be at zero remaining depth.")
		return false

	var cell_size := float(mining_config.terrain_cell_world_size)
	for encounter in encounter_config.encounters:
		var presenter := merchant_scene.instantiate() as MerchantPresenter
		if presenter == null:
			push_error("Merchant Presenter could not be instantiated.")
			return false
		merchant_parent.add_child(presenter)
		presenter.apply_appearance(encounter.appearance)
		presenter.position = Vector2(
			(
				float(mining_config.terrain_width_cells) * 0.5
				+ float(horizontal_offset_cells)
			) * cell_size,
			float(
				mining_config.initial_surface_row
				+ encounter.resolve_depth(mining_config.total_run_depth)
			) * cell_size
		)
		_presenters.append(presenter)
	_on_view_y_changed(float(mining_config.initial_surface_row))
	return true


## Makes the timing bar usable after a completed character conversation.
func _restore_timing_window() -> void:
	mining_controller.set_swing_queue_paused(false)
	timing_window.process_mode = Node.PROCESS_MODE_INHERIT
	timing_window.show()
