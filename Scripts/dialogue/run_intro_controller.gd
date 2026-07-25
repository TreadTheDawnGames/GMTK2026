class_name RunIntroController
extends Node

## How it works:
## - Scene readiness immediately gates mining and hides the timing bar.
## - A stand-in guide slides onto the surface before dialogue begins.
## - Existing dialogue signals drive guide speech motion and completion.
## - The guide exits before timing input and swing queuing resume.
## The invariant is that mining stays unavailable for the entire intro.

@export_category("Content")
@export var conversation: DialogueConversation
@export var guide_appearance: CharacterAppearance
@export var guide_speaker_slot: StringName = &"lookout"

@export_category("Animation")
@export_range(0.05, 3.0, 0.05) var entrance_seconds: float = 0.35
@export_range(0.0, 600.0, 1.0) var entrance_distance_px: float = 220.0
@export_range(0.05, 3.0, 0.05) var departure_seconds: float = 0.35
@export_range(0.0, 600.0, 1.0) var departure_distance_px: float = 260.0

@export_category("References")
@export var dialogue_director: DialogueDirector
@export var guide_presenter: CharacterPresenter
@export var timing_window: TimingWindowTask
@export var mining_controller: MiningController

var _is_intro_active: bool = false
var _guide_rest_position: Vector2


## Prepares the surface meeting before any mining input can be consumed.
func _ready() -> void:
	if (
		conversation == null
		or guide_appearance == null
		or dialogue_director == null
		or guide_presenter == null
		or timing_window == null
		or mining_controller == null
	):
		push_error("Run intro references are incomplete.")
		return
	_is_intro_active = true
	_set_mining_available(false)
	_guide_rest_position = guide_presenter.position
	guide_presenter.apply_appearance(guide_appearance)
	guide_presenter.position = (
		_guide_rest_position + Vector2.RIGHT * entrance_distance_px
	)
	guide_presenter.modulate.a = 0.0
	guide_presenter.show()
	_play_intro.call_deferred()


## Slides the guide into the authored meeting position, then opens dialogue.
func _play_intro() -> void:
	var entrance_tween := create_tween()
	entrance_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	entrance_tween.set_parallel(true)
	entrance_tween.tween_property(
		guide_presenter,
		"position",
		_guide_rest_position,
		entrance_seconds
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	entrance_tween.tween_property(
		guide_presenter,
		"modulate:a",
		1.0,
		entrance_seconds
	)
	await entrance_tween.finished
	if (
		_is_intro_active
		and dialogue_director.start_conversation(conversation)
	):
		return
	push_error("The run intro conversation could not start.")
	_finish_intro()


## Animates only the guide's authored lines during this conversation.
func _on_dialogue_line_presented(
	conversation_id: StringName,
	_line_index: int,
	speaker_slot: StringName
) -> void:
	if (
		not _is_intro_active
		or conversation_id != conversation.conversation_id
	):
		return
	guide_presenter.reset_speech_motion()
	if speaker_slot == guide_speaker_slot:
		guide_presenter.react_to_presented_line()


## Sends the guide away after the miner accepts the objective.
func _on_conversation_finished(conversation_id: StringName) -> void:
	if (
		not _is_intro_active
		or conversation_id != conversation.conversation_id
	):
		return
	guide_presenter.reset_speech_motion()
	guide_presenter.depart_right(
		departure_distance_px,
		departure_seconds
	)
	await get_tree().create_timer(departure_seconds, true).timeout
	_finish_intro()


## Releases the timing and swing gates after every intro exit path.
func _finish_intro() -> void:
	if not _is_intro_active:
		return
	_is_intro_active = false
	guide_presenter.hide()
	_set_mining_available(true)


## Applies the shared input gate without changing timing-bar state.
func _set_mining_available(is_available: bool) -> void:
	mining_controller.set_swing_queue_paused(not is_available)
	timing_window.process_mode = (
		Node.PROCESS_MODE_INHERIT
		if is_available
		else Node.PROCESS_MODE_DISABLED
	)
	if is_available:
		timing_window.show()
	else:
		timing_window.hide()
