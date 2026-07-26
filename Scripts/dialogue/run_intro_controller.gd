class_name RunIntroController
extends Node

## How it works:
## - Scene readiness gates mining and hides the timing bar before anything moves.
## - The scene boots into the title shot with the cinematic frame open: the
##   camera holds its wide framing, and the stop stands with the miner hidden.
##   That staged world is the menu's background, so nothing is loaded or
##   swapped when the player starts.
## - begin_run() is the menu's request. The bus drives in and the camera closes
##   the shot onto it, so the world shrinks into gameplay framing at the speed
##   the bus allows rather than on a timer of its own.
## - The authored arrival sequence places the miner at the dig spot, then pulls
##   the bus away to reveal him already in the mining stance.
## - The unattributed opening conversation plays before control is returned.
## - Only the letterbox and HUD change when control returns; the stop, its
##   attendant, and the dressed ground all stay standing behind the miner.
## - Every failure path still opens the frame and settles the camera, so a
##   letterboxed or half-zoomed shot is never final.
## The invariant is that mining stays unavailable for the entire intro.

const FLOW_OWNER: StringName = &"run_intro"

@export_category("Content")
@export var attendant_appearance: CharacterAppearance
@export var opening_conversation: DialogueConversation

@export_category("Animation")
## Held after the menu leaves, before the bus enters, so the player reads the
## empty stop first.
@export_range(0.0, 3.0, 0.05) var hold_after_reveal_seconds: float = 0.7
## The closing beat: how long the miner takes to plant into his dig stance.
## Long enough to read as a deliberate settle rather than a snap.
@export_range(0.0, 2.0, 0.05) var miner_restore_seconds: float = 0.2

@export_category("References")
@export var dialogue_director: DialogueDirector
@export var arrival_sequence: ArrivalIntroSequence
@export var attendant_presenter: CharacterPresenter
@export var miner_rig: MinerRig
@export var cinematic_flow: MiningCinematicFlow
@export var opening_camera: OpeningShotCamera

var _is_intro_active: bool = false
var _is_staged: bool = false
var _title_shot_applied: bool = false


## Stages the surface meeting before any mining input can be consumed. The
## staging stands for as long as the menu is up; nothing plays until it asks.
func _ready() -> void:
	if not _has_complete_references():
		push_error("Run intro references are incomplete.")
		_release_shot_safely()
		return
	attendant_presenter.apply_appearance(attendant_appearance)
	if not cinematic_flow.try_begin(FLOW_OWNER):
		push_error("Run intro could not acquire the cinematic flow.")
		_release_shot_safely()
		return
	if not arrival_sequence.begin():
		push_error("Run intro could not stage the arrival.")
		cinematic_flow.cancel(FLOW_OWNER)
		_release_shot_safely()
		return
	_is_staged = true
	# The camera framing is applied after every _ready() has run, so anything
	# that captures the authored rest zoom on readiness still reads 1.0.
	_apply_title_shot.call_deferred()


## Plays the canonical arrival once the menu hands the shot over.
func begin_run() -> void:
	if _is_intro_active:
		return
	if not _is_staged:
		# Staging failed at boot, so there is no shot to play. Let the player
		# into the game rather than stranding them behind a dead menu.
		_release_shot_safely()
		return
	# A menu that hands over on the same frame the scene is staged arrives
	# before the deferred pass, so the shot is applied on demand here instead.
	_apply_title_shot()
	# Keep the title background full-height. The cinematic bars begin only at
	# the Start handoff, while the interface fades and the arrival moves in.
	dialogue_director.open_cinematic_frame()
	_is_intro_active = true
	_play_intro()


## Holds the wide title framing behind the menu without covering live terrain.
## It runs once: a second pass would reset a transition already in progress.
func _apply_title_shot() -> void:
	if _title_shot_applied:
		return
	_title_shot_applied = true
	# The menu must not open the cinematic frame here: its lower bar used to
	# read as an unrendered grey strip beneath otherwise complete terrain.
	dialogue_director.close_cinematic_frame(true)
	opening_camera.apply_menu_framing()


## Drives the bus in while the camera closes the shot around it.
func _play_intro() -> void:
	# Own the wide framing before the establishing hold. A run reset restores
	# gameplay zoom during this gap; the active opening camera immediately
	# reasserts its monotonic title zoom until the bus is framed.
	opening_camera.start_zoom_in()
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
	if dialogue_director.start_conversation(
		opening_conversation,
		true
	):
		return
	push_error("Run intro could not start its opening conversation.")
	_finish_after_opening_dialogue()


## Continues the held opening shot after its authored conversation finishes.
func _on_conversation_finished(conversation_id: StringName) -> void:
	if (
		not _is_intro_active
		or opening_conversation == null
		or conversation_id != opening_conversation.conversation_id
	):
		return
	_finish_after_opening_dialogue()


## Plants the miner, clears the cinematic frame, and returns gameplay control.
func _finish_after_opening_dialogue() -> void:
	if not _is_intro_active:
		return
	# End the shot with the miner planting into his dig stance while the
	# letterbox is still on. Gameplay draw order goes back on that same beat, so
	# the foreground stratum closing over his legs reads as him settling in
	# rather than as a clip the instant the frame opens up.
	await arrival_sequence.finish(miner_restore_seconds)
	if not _is_intro_active:
		return
	# The frame never opens on a shot that is still moving: gameplay coordinates
	# are all authored against the settled framing.
	await opening_camera.wait_until_settled()
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


## Guarantees the player never inherits a closed frame or a half-closed shot.
func _release_shot_safely() -> void:
	if dialogue_director != null:
		dialogue_director.close_cinematic_frame()
	if opening_camera != null:
		opening_camera.release()


func _reset_speech_reactions() -> void:
	attendant_presenter.reset_speech_motion()
	miner_rig.reset_speech_motion()


func _has_complete_references() -> bool:
	return (
		attendant_appearance != null
		and opening_conversation != null
		and dialogue_director != null
		and arrival_sequence != null
		and attendant_presenter != null
		and miner_rig != null
		and cinematic_flow != null
		and opening_camera != null
	)
