class_name RunIntroController
extends Node

## How it works:
## - Scene readiness gates mining and hides the timing bar before anything moves.
## - The scene starts under the menu's black; the letterbox splits it apart from
##   the middle, and only then does the bus drive into frame.
## - The authored arrival sequence steps the miner off the bus, then pulls the
##   bus away while he walks over and settles into the mining stance.
## - Only the letterbox and HUD change when control returns; the stop, its
##   attendant, and the dressed ground all stay standing behind the miner.
## - Every failure path still reveals the shot, so a black screen is never final.
## The invariant is that mining stays unavailable for the entire intro.

const FLOW_OWNER: StringName = &"run_intro"
const MINER_SPEAKER_SLOT: StringName = &"miner"

@export_category("Content")
@export var attendant_appearance: CharacterAppearance

@export_category("Animation")
## Held after the blackout splits open, before the bus enters, so the player
## reads the empty stop first.
@export_range(0.0, 3.0, 0.05) var hold_after_reveal_seconds: float = 0.0
## The closing beat: how long the miner takes to plant into his dig stance.
## Long enough to read as a deliberate settle rather than a snap.
@export_range(0.0, 2.0, 0.05) var miner_restore_seconds: float = 0.2

@export_category("References")
@export var dialogue_director: DialogueDirector
@export var arrival_sequence: ArrivalIntroSequence
@export var attendant_presenter: CharacterPresenter
@export var miner_rig: MinerRig
@export var cinematic_flow: MiningCinematicFlow

var _is_intro_active: bool = false


## Stages the surface meeting before any mining input can be consumed.
func _ready() -> void:
	if not _has_complete_references():
		push_error("Run intro references are incomplete.")
		_reveal_frame_safely()
		return
	attendant_presenter.apply_appearance(attendant_appearance)
	if not cinematic_flow.try_begin(FLOW_OWNER):
		push_error("Run intro could not acquire the cinematic flow.")
		_reveal_frame_safely()
		return
	if not arrival_sequence.begin():
		push_error("Run intro could not stage the arrival.")
		cinematic_flow.cancel(FLOW_OWNER)
		_reveal_frame_safely()
		return
	_is_intro_active = true
	_play_intro.call_deferred()


## Opens the inherited blackout and plays the canonical bus-only arrival.
func _play_intro() -> void:
	dialogue_director.reveal_cinematic_frame_from_blackout()
	await dialogue_director.wait_until_blackout_revealed()
	if not _is_intro_active:
		return
	if hold_after_reveal_seconds > 0.0:
		await get_tree().create_timer(
			hold_after_reveal_seconds,
			true
		).timeout
	if not _is_intro_active:
		return
	await arrival_sequence.play_arrival()
	if not _is_intro_active:
		return
	# End the shot with the miner planting into his dig stance while the
	# letterbox is still on. Gameplay draw order goes back on that same beat, so
	# the foreground stratum closing over his legs reads as him settling in
	# rather than as a clip the instant the frame opens up.
	await arrival_sequence.finish(miner_restore_seconds)
	if not _is_intro_active:
		return
	dialogue_director.close_cinematic_frame()
	await dialogue_director.wait_until_frame_closed()
	if not _is_intro_active:
		return
	_finish_intro()


## Releases the timing and swing gates after every intro exit path.
func _finish_intro() -> void:
	if not _is_intro_active:
		return
	_is_intro_active = false
	_reset_speech_reactions()
	await arrival_sequence.finish(miner_restore_seconds)
	# Hand the miner's grounding back to the mining side explicitly, so the
	# cinematic's captured rest can never survive as a stale vertical offset.
	miner_rig.show_intact_floor_grounding()
	cinematic_flow.finish(FLOW_OWNER)


## Guarantees the player never inherits an unopened blackout from the menu.
func _reveal_frame_safely() -> void:
	if dialogue_director != null:
		dialogue_director.reveal_cinematic_frame_from_blackout(true)
		dialogue_director.close_cinematic_frame()


func _reset_speech_reactions() -> void:
	attendant_presenter.reset_speech_motion()
	miner_rig.reset_speech_motion()


func _has_complete_references() -> bool:
	return (
		attendant_appearance != null
		and dialogue_director != null
		and arrival_sequence != null
		and attendant_presenter != null
		and miner_rig != null
		and cinematic_flow != null
	)
