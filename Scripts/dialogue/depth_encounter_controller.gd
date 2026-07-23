class_name DepthEncounterController
extends Node

## Runs recurring NPC conversations that grant authored pickaxe upgrades.

@export_category("Schedule")
@export var encounter_config: DepthEncounterConfig
@export var mining_config: MiningConfig
@export var gift_encounters: Array[PickaxeGiftEncounter] = []

@export_category("References")
@export var dialogue_director: DialogueDirector
@export var timing_window: TimingWindowTask
@export var encounter_npc: Node2D
@export var pickaxe_progression: PickaxeProgression
@export var mining_controller: MiningController

var _next_floor_depth: int = -1
var _pending_floor_depth: int = -1
var _active_floor_depth: int = -1
var _completed_floor_depth: int = -1
var _next_gift_index: int = 0
var _active_gift: PickaxeGiftEncounter
var _is_initialized: bool = false


## Hides the NPC, validates its gifts, and schedules the first encounter.
func _ready() -> void:
	encounter_npc.hide()
	_validate_gift_encounters()
	_schedule_next_floor(0)
	_is_initialized = true


## Arms the next authored gift when the player reaches its chamber floor.
func _on_depth_changed(depth: int) -> void:
	# Ignore the initial depth signal sent before this node is ready.
	if not _is_initialized:
		return
	if _active_floor_depth >= 0 or _pending_floor_depth >= 0:
		return
	if _next_floor_depth < 0:
		return
	if (
		_completed_floor_depth >= 0
		and depth > _completed_floor_depth
	):
		encounter_npc.hide()
	if depth < _next_floor_depth:
		return

	_pending_floor_depth = _next_floor_depth
	_next_floor_depth = -1
	# Prevent another mining input while the floor moves up to the miner.
	timing_window.process_mode = Node.PROCESS_MODE_DISABLED
	mining_controller.set_swing_queue_paused(true)


## Starts the armed gift encounter after the miner physically lands.
func _on_landing_reached(_mining_y: int) -> void:
	if _pending_floor_depth < 0 or _active_floor_depth >= 0:
		return
	_active_floor_depth = _pending_floor_depth
	_pending_floor_depth = -1
	_begin_encounter.call_deferred()


## Shows the NPC and starts the conversation for the next pickaxe gift.
func _begin_encounter() -> void:
	if (
		_next_gift_index < 0
		or _next_gift_index >= gift_encounters.size()
	):
		_finish_failed_encounter(
			"No pickaxe gift is configured for this encounter."
		)
		return
	_active_gift = gift_encounters[_next_gift_index]
	if _active_gift == null or _active_gift.conversation == null:
		_finish_failed_encounter(
			"The current pickaxe gift has no conversation."
		)
		return

	encounter_npc.show()
	timing_window.hide()
	if dialogue_director.start_conversation(
		_active_gift.conversation
	):
		return
	_finish_failed_encounter(
		"The pickaxe gift conversation could not be started."
	)


## Grants the presented pickaxe and schedules the next gift encounter.
func _on_conversation_finished(conversation_id: StringName) -> void:
	if (
		_active_floor_depth < 0
		or _active_gift == null
		or _active_gift.conversation == null
		or conversation_id
			!= _active_gift.conversation.conversation_id
	):
		return

	var completed_depth := _active_floor_depth
	if not pickaxe_progression.grant_upgrade(_active_gift.pickaxe):
		push_error(
			"Encounter '%s' could not grant pickaxe '%s'."
			% [
				conversation_id,
				_active_gift.pickaxe.id
					if _active_gift.pickaxe != null
					else &"<missing>",
			]
		)
	_completed_floor_depth = completed_depth
	_active_floor_depth = -1
	_active_gift = null
	_next_gift_index += 1
	_schedule_next_floor(completed_depth)

	if encounter_config.post_dialogue_buffer_seconds > 0.0:
		await get_tree().create_timer(
			encounter_config.post_dialogue_buffer_seconds,
			true
		).timeout
	_restore_timing_window()


## Schedules another chamber only while an authored gift remains.
func _schedule_next_floor(current_depth: int) -> void:
	if _next_gift_index >= gift_encounters.size():
		_next_floor_depth = -1
		return
	_next_floor_depth = encounter_config.get_next_floor_depth(
		current_depth,
		mining_config.total_run_depth
	)


## Reports invalid encounter resources before the player reaches them.
func _validate_gift_encounters() -> void:
	if (
		encounter_config.maximum_floor_count
		!= gift_encounters.size()
	):
		push_error(
			"Encounter floor count (%d) must match authored gifts (%d)."
			% [
				encounter_config.maximum_floor_count,
				gift_encounters.size(),
			]
		)
	for gift_index in range(gift_encounters.size()):
		var gift := gift_encounters[gift_index]
		if gift == null:
			push_error(
				"Pickaxe gift encounter %d is empty."
				% (gift_index + 1)
			)
			continue
		var validation_errors := gift.validate()
		if validation_errors.is_empty():
			continue
		push_error(
			"Pickaxe gift encounter %d is invalid:\n- %s"
			% [
				gift_index + 1,
				"\n- ".join(validation_errors),
			]
		)


## Restores mining after an encounter cannot be presented.
func _finish_failed_encounter(message: String) -> void:
	push_error(message)
	var failed_floor_depth := _active_floor_depth
	_active_floor_depth = -1
	_active_gift = null
	encounter_npc.hide()
	_schedule_next_floor(failed_floor_depth)
	_restore_timing_window()


## Makes the timing bar visible and usable after an encounter.
func _restore_timing_window() -> void:
	mining_controller.set_swing_queue_paused(false)
	timing_window.process_mode = Node.PROCESS_MODE_INHERIT
	timing_window.show()
