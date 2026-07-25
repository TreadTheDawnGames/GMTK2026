class_name LayerBreakthroughController
extends Node

## How it works:
## - Combo eight at run depth 400 prepares that exact impact immediately.
## - The visual-only breakthrough waits for the miner's physical landing.
## - The authored sequence requests rat and miner dialogue beats by stable IDs.
## - Dialogue data stays in resources while the stage owns movement and timing.
## - The shared frame covers the direct stage swap and reversible restoration.
## - Every completion or failure restores presentation and its named flow gate.
## The invariant is that one prepared hit is committed or rolled back exactly.

## Warns presentation that the very next successful hit would spend the
## one-time breakthrough, so the timing bar can mark that swing as special.
signal arming_changed(is_armed: bool)

const FLOW_OWNER: StringName = &"layer_breakthrough"
const DISCOVERY_REACTION_SLOT: StringName = &"reaction"

@export_category("Trigger")
@export_range(1, 100, 1) var minimum_combo: int = 8
@export_range(1, 10000, 1) var minimum_run_depth: int = 400

@export_category("Content")
@export var discovery_conversation: DialogueConversation
@export var rat_warning_conversation: DialogueConversation
@export var miner_response_conversation: DialogueConversation

@export_category("References")
@export var sequence: LayerBreakthroughSequence
@export var dialogue_director: DialogueDirector
@export var cinematic_flow: MiningCinematicFlow
@export var encounter_controller: DepthEncounterController
@export var miner_rig: MinerRig
@export var lead_rat: CinematicRatMiner

var _is_pending_landing: bool = false
var _is_sequence_active: bool = false
var _is_finishing_sequence: bool = false
var _has_completed_sequence: bool = false
var _is_disabled_after_failure: bool = false
var _current_run_depth: int = 0
var _is_armed_for_next_hit: bool = false
var _active_beat_id: StringName
var _active_conversation_id: StringName
@onready var _game_state: RunState = RunState.get_global(self)


## Connects only signals owned by the authored breakthrough subsystem.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _game_state != null:
		_current_run_depth = _game_state.depth
	if not _validate_references():
		return
	_connect_once(
		sequence.dialogue_beat_requested,
		_on_dialogue_beat_requested
	)
	_connect_once(
		sequence.tunnel_stage_ready,
		_on_tunnel_stage_ready
	)
	_connect_once(
		sequence.sequence_restored,
		_on_sequence_restored
	)
	_connect_once(sequence.sequence_failed, _on_sequence_failed)


## Confirms that the provisionally prepared hit removed terrain.
func _on_mine_resolved(
	_depth_gained: int,
	cells_removed: int,
	combo: int,
	_combo_strength: float
) -> void:
	# Deferred so the warning is recomputed once this hit's whole cascade — run
	# state, depth, and any gate this handler itself claims — has settled.
	_refresh_arming.call_deferred()
	var is_qualifying_impact := (
		cells_removed > 0
		and combo >= minimum_combo
		and _current_run_depth >= minimum_run_depth
		and not _is_disabled_after_failure
	)
	if _is_pending_landing:
		if not is_qualifying_impact:
			_cancel_pending_landing()
		return
	if (
		not is_qualifying_impact
		or _has_completed_sequence
		or _is_sequence_active
	):
		return
	_try_arm_for_landing()


## Prepares the exact real hit before another depth consumer can claim the flow.
func _on_depth_changed(depth: int) -> void:
	_current_run_depth = depth
	_refresh_arming.call_deferred()
	if (
		_game_state == null
		or _game_state.combo < minimum_combo
		or depth < minimum_run_depth
		or _has_completed_sequence
		or _is_disabled_after_failure
		or _is_pending_landing
		or _is_sequence_active
	):
		return
	_try_arm_for_landing()


## Claims the shared gate only after the exact impact transaction is prepared.
func _try_arm_for_landing() -> bool:
	if (
		_has_completed_sequence
		or _is_disabled_after_failure
		or _is_pending_landing
		or _is_sequence_active
		or encounter_controller.has_pending_or_active_interaction()
	):
		return false
	if not sequence.prepare_entrance_impact():
		return false
	if not cinematic_flow.try_begin(FLOW_OWNER):
		sequence.release_entrance_impact()
		return false
	_is_pending_landing = true
	return true


## Starts presentation only after the physical miner reaches solid footing.
func _on_landing_reached(_mining_y: int) -> void:
	if (
		not _is_pending_landing
		or not cinematic_flow.is_owned_by(FLOW_OWNER)
	):
		return
	if encounter_controller.has_pending_or_active_interaction():
		_cancel_pending_landing()
		return
	cinematic_flow.focus(FLOW_OWNER)
	dialogue_director.open_cinematic_frame()
	await dialogue_director.wait_until_frame_open()
	if (
		not _is_pending_landing
		or not cinematic_flow.is_owned_by(FLOW_OWNER)
	):
		return
	_is_pending_landing = false
	if not sequence.play_breakthrough():
		_reset_cinematic_frame()
		cinematic_flow.cancel(FLOW_OWNER)
		return
	_is_sequence_active = true


## Opens the viewport onto layer five before admitting the lead rat.
func _on_tunnel_stage_ready() -> void:
	if not _is_sequence_active:
		return
	dialogue_director.cinematic_frame.open_iris()
	await dialogue_director.cinematic_frame.wait_until_iris_open()
	if (
		not _is_sequence_active
		or not cinematic_flow.is_owned_by(FLOW_OWNER)
	):
		return
	if not sequence.complete_tunnel_reveal():
		_fail_sequence("The layer-five tunnel could not finish revealing.")


## Runs the requested editable dialogue resource at the supplied stage anchor.
func _on_dialogue_beat_requested(
	beat_id: StringName
) -> void:
	if not _is_sequence_active or dialogue_director.is_conversation_active():
		_fail_sequence("Dialogue was unavailable for '%s'." % beat_id)
		return
	var conversation: DialogueConversation
	match beat_id:
		LayerBreakthroughSequence.DISCOVERY_BEAT:
			conversation = discovery_conversation
		LayerBreakthroughSequence.RAT_WARNING_BEAT:
			conversation = rat_warning_conversation
		LayerBreakthroughSequence.MINER_RESPONSE_BEAT:
			conversation = miner_response_conversation
		_:
			_fail_sequence("Unknown breakthrough dialogue beat '%s'." % beat_id)
			return
	if conversation == null:
		_fail_sequence("Breakthrough dialogue beat '%s' is incomplete." % beat_id)
		return
	dialogue_director.open_cinematic_frame()
	await dialogue_director.wait_until_frame_open()
	if not _is_sequence_active:
		return
	_active_beat_id = beat_id
	_active_conversation_id = conversation.conversation_id
	if not dialogue_director.start_conversation(conversation, true):
		_fail_sequence(
			"Breakthrough conversation '%s' could not start."
			% conversation.conversation_id
		)


## Bounces only the visible actor speaking in the active authored beat.
func _on_dialogue_line_presented(
	conversation_id: StringName,
	_line_index: int,
	speaker_slot: StringName,
	speaker_pose: StringName
) -> void:
	if (
		not _is_sequence_active
		or _active_beat_id.is_empty()
		or conversation_id != _active_conversation_id
	):
		return
	_reset_speech_reactions()
	if (
		_active_beat_id == LayerBreakthroughSequence.DISCOVERY_BEAT
		and speaker_slot == DISCOVERY_REACTION_SLOT
	):
		miner_rig.react_to_presented_line()
	elif (
		_active_beat_id == LayerBreakthroughSequence.RAT_WARNING_BEAT
		and speaker_slot == &"rat"
	):
		if (
			not speaker_pose.is_empty()
			and lead_rat.has_pose(speaker_pose)
		):
			lead_rat.play_pose(speaker_pose)
		lead_rat.react_to_presented_line()
	elif (
		_active_beat_id == LayerBreakthroughSequence.MINER_RESPONSE_BEAT
		and speaker_slot == &"miner"
	):
		miner_rig.react_to_presented_line()


## Advances the authored stage after its matching dialogue resource finishes.
func _on_conversation_finished(conversation_id: StringName) -> void:
	if (
		not _is_sequence_active
		or _active_beat_id.is_empty()
		or conversation_id != _active_conversation_id
	):
		return
	_reset_speech_reactions()
	var finished_beat := _active_beat_id
	_active_beat_id = &""
	_active_conversation_id = &""
	if finished_beat == LayerBreakthroughSequence.DISCOVERY_BEAT:
		if not _focus_iris_on_miner():
			_fail_sequence("The exit iris could not focus on the miner.")
			return
		await dialogue_director.cinematic_frame.wait_until_iris_focused()
		if (
			not _is_sequence_active
			or not cinematic_flow.is_owned_by(FLOW_OWNER)
		):
			return
		if not sequence.complete_dialogue_beat(finished_beat):
			_fail_sequence(
				"Breakthrough beat '%s' could not complete." % finished_beat
			)
		return
	if finished_beat == LayerBreakthroughSequence.MINER_RESPONSE_BEAT:
		# Stop the recurring spawn timer synchronously with the last line.
		# The tracked iris may close while already-live rats mine themselves out.
		if not sequence.complete_dialogue_beat(finished_beat):
			_fail_sequence(
				"Breakthrough beat '%s' could not complete." % finished_beat
			)
			return
		if not _focus_iris_on_miner():
			_fail_sequence("The exit iris could not focus on the miner.")
			return
		return
	if not sequence.complete_dialogue_beat(finished_beat):
		_fail_sequence(
			"Breakthrough beat '%s' could not complete." % finished_beat
		)


## Releases the flow only after every authored visual has been restored.
func _on_sequence_restored(completed: bool) -> void:
	if not _is_sequence_active or _is_finishing_sequence:
		return
	_active_beat_id = &""
	_active_conversation_id = &""
	_reset_speech_reactions()
	if not completed:
		_is_sequence_active = false
		_reset_cinematic_frame()
		cinematic_flow.cancel(FLOW_OWNER)
		_refresh_arming.call_deferred()
		return

	_is_finishing_sequence = true
	dialogue_director.cinematic_frame.open_iris()
	await dialogue_director.cinematic_frame.wait_until_iris_open()
	if (
		not _is_finishing_sequence
		or not _is_sequence_active
		or not cinematic_flow.is_owned_by(FLOW_OWNER)
	):
		return
	dialogue_director.close_cinematic_frame()
	await dialogue_director.wait_until_frame_closed()
	if (
		not _is_finishing_sequence
		or not _is_sequence_active
		or not cinematic_flow.is_owned_by(FLOW_OWNER)
	):
		return
	_is_finishing_sequence = false
	_is_sequence_active = false
	_has_completed_sequence = true
	cinematic_flow.finish(FLOW_OWNER)
	_refresh_arming.call_deferred()


## Restores gate ownership after a sequence-owned validation failure.
func _on_sequence_failed(reason: String) -> void:
	push_error("Layer breakthrough failed: %s" % reason)
	_is_disabled_after_failure = true
	if (
		_is_pending_landing
		or _is_sequence_active
		or cinematic_flow.is_owned_by(FLOW_OWNER)
	):
		_restore_after_failure()


## Cancels the presentation without consuming its one-time successful trigger.
func abort_and_restore() -> void:
	if _is_pending_landing:
		_cancel_pending_landing()
		return
	if _is_finishing_sequence:
		_is_finishing_sequence = false
		_is_sequence_active = false
		_reset_speech_reactions()
		_reset_cinematic_frame()
		cinematic_flow.cancel(FLOW_OWNER)
		return
	if _is_sequence_active:
		sequence.abort_and_restore()


## Reports whether this flow is pending or visibly active.
func is_pending_or_active() -> bool:
	return _is_pending_landing or _is_sequence_active


## Reports whether the next successful hit would open the breakthrough.
func is_armed_for_next_hit() -> bool:
	return _is_armed_for_next_hit


## Emits only on a change so presentation can latch instead of polling.
func _refresh_arming() -> void:
	var is_armed := (
		_game_state != null
		and not _has_completed_sequence
		and not _is_disabled_after_failure
		and not _is_pending_landing
		and not _is_sequence_active
		and _current_run_depth >= minimum_run_depth
		# The trigger reads the combo the hit resolves to, so the swing worth
		# warning about is the one taken at exactly one short of the minimum.
		and _game_state.combo + 1 >= minimum_combo
	)
	if is_armed == _is_armed_for_next_hit:
		return
	_is_armed_for_next_hit = is_armed
	arming_changed.emit(is_armed)


## Reports whether the one-time encounter has completed successfully.
func has_completed_sequence() -> bool:
	return _has_completed_sequence


## Validates scene composition without embedding authored content in code.
func _validate_references() -> bool:
	if (
		sequence == null
		or dialogue_director == null
		or cinematic_flow == null
		or encounter_controller == null
		or miner_rig == null
		or lead_rat == null
		or discovery_conversation == null
		or rat_warning_conversation == null
		or miner_response_conversation == null
	):
		push_error("Layer breakthrough references are incomplete.")
		return false
	return true


## Uses the same idempotent cleanup for every controller-owned failure.
func _fail_sequence(reason: String) -> void:
	push_error(reason)
	_is_disabled_after_failure = true
	if _is_sequence_active:
		sequence.abort_and_restore()
	else:
		_restore_after_failure()


## Clears presentation state after failures that did not enter restoration.
func _restore_after_failure() -> void:
	_is_pending_landing = false
	_is_sequence_active = false
	_is_finishing_sequence = false
	_active_beat_id = &""
	_active_conversation_id = &""
	_reset_speech_reactions()
	_reset_cinematic_frame()
	sequence.release_entrance_impact()
	cinematic_flow.cancel(FLOW_OWNER)
	_refresh_arming.call_deferred()


## Rolls back one prepared entrance before any visual owner takes control.
func _cancel_pending_landing() -> void:
	_is_pending_landing = false
	sequence.release_entrance_impact()
	_reset_speech_reactions()
	_reset_cinematic_frame()
	cinematic_flow.cancel(FLOW_OWNER)
	_refresh_arming.call_deferred()


## Connects one internal sequence signal without duplicating it.
func _connect_once(source_signal: Signal, target: Callable) -> void:
	if not source_signal.is_connected(target):
		source_signal.connect(target)


func _reset_speech_reactions() -> void:
	lead_rat.reset_speech_motion()
	miner_rig.reset_speech_motion()


## Starts one tracked aperture around the miner's authored body-center motion.
func _focus_iris_on_miner() -> bool:
	return (
		dialogue_director.cinematic_frame != null
		and dialogue_director.cinematic_frame.focus_iris_on(
			sequence.miner_iris_anchor
		)
	)


## Removes both breakthrough framing layers after cancellation or failure.
func _reset_cinematic_frame() -> void:
	if dialogue_director.cinematic_frame != null:
		dialogue_director.cinematic_frame.reset_iris()
	dialogue_director.close_cinematic_frame()
