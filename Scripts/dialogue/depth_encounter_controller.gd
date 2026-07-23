class_name DepthEncounterController
extends Node

## Starts NPC dialogue at recurring depth floors.

@export var encounter_config: DepthEncounterConfig
@export var conversation: DialogueConversation
@export var dialogue_director: DialogueDirector
@export var timing_window: TimingWindowTask
@export var encounter_npc: Node2D

var _next_floor_depth_px: int
var _pending_floor_depth_px: int = -1
var _active_floor_depth_px: int = -1
var _completed_floor_depth_px: int = -1
var _is_initialized: bool = false


## Hides the NPC and prepares the first encounter depth.
func _ready() -> void:
	encounter_npc.hide()
	_next_floor_depth_px = encounter_config.first_floor_depth_px
	_is_initialized = true


## Starts an encounter when the player reaches the next configured floor.
func _on_depth_changed(depth_px: int) -> void:
	# Ignore the initial depth signal sent before this node is ready.
	if not _is_initialized:
		return
	if _active_floor_depth_px >= 0 or _pending_floor_depth_px >= 0:
		return
	if (
		_completed_floor_depth_px >= 0
		and depth_px > _completed_floor_depth_px
	):
		encounter_npc.hide()
	if depth_px < _next_floor_depth_px:
		return

	_pending_floor_depth_px = _next_floor_depth_px
	_next_floor_depth_px = encounter_config.get_next_floor_depth(
		_pending_floor_depth_px
	)
	# Prevent another mining input while the floor moves up to the miner.
	timing_window.process_mode = Node.PROCESS_MODE_DISABLED


## Starts the armed encounter after the rendered floor reaches the miner's feet.
func _on_landing_reached(_mining_y: int) -> void:
	if _pending_floor_depth_px < 0 or _active_floor_depth_px >= 0:
		return
	_active_floor_depth_px = _pending_floor_depth_px
	_pending_floor_depth_px = -1
	_begin_encounter.call_deferred()


## Shows the NPC, hides the timing bar, and starts dialogue.
func _begin_encounter() -> void:
	encounter_npc.show()
	timing_window.hide()
	if dialogue_director.start_conversation(conversation):
		return
	_restore_timing_window()
	encounter_npc.hide()
	_active_floor_depth_px = -1


## Restores the timing bar after the encounter dialogue ends.
func _on_conversation_finished(conversation_id: StringName) -> void:
	if (
		_active_floor_depth_px < 0
		or conversation_id != conversation.conversation_id
	):
		return
	_restore_timing_window()
	_completed_floor_depth_px = _active_floor_depth_px
	_active_floor_depth_px = -1


## Makes the timing bar visible and usable after an encounter.
func _restore_timing_window() -> void:
	timing_window.process_mode = Node.PROCESS_MODE_INHERIT
	timing_window.show()
