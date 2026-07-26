class_name QuibbleEncounterStage
extends CharacterEncounterStage

## How it works:
## - prepare() starts Quibble's presentation-only vibration and coffee clock.
## - The sprite snaps through a tiny fixed jitter pattern at a bounded rate.
## - Every few seconds he raises the mug, chugs it, lowers it, and returns to idle.
## - The Miner's dialogue line forces a repeating chug until the line advances.
## - Dialogue may still request poses; the next coffee phase resumes the loop.
## - Closing or cancellation restores the exact authored sprite position.
## - The invariant is that Quibble moves neither the actor root nor draw order.

## How long between one chug and the next.
##
## He used to sip every 1.25s for a fifth of a second each time, which at
## playtest read as a twitch rather than as drinking: the pose changed too often
## to register and never lasted long enough to be an action. Drinking less often
## and committing to it when he does is what makes it read. The two numbers move
## together - stretching the chug without spacing them out just makes him drink
## continuously.
const DRINK_INTERVAL_SECONDS: float = 3.0
## The raise before the chug and the lower after it. Long enough to see the mug
## travel, short enough that the chug is still the part you notice.
const HOLD_CUP_SECONDS: float = 0.18
## The chug itself: head back, mug upended, held. This is the beat that has to be
## long enough to be an action rather than a frame that flickered past.
const DRINK_SECONDS: float = 1.0
const JITTER_STEP_SECONDS: float = 0.02
const JITTER_OFFSETS := [
	Vector2(-3.0, 0.0),
	Vector2(3.0, -2.0),
	Vector2(-2.0, 2.0),
	Vector2(2.0, 0.0),
	Vector2(0.0, -2.0),
	Vector2(3.0, 2.0),
	Vector2(-3.0, -2.0),
	Vector2.ZERO,
]

enum CoffeePhase {
	WAITING,
	HOLDING,
	DRINKING,
	RECOVERING,
}

## Which dialogue slot is Quibble's own. Exported rather than hard-coded so this
## stays in step with the encounter resource if the slot is ever renamed.
@export var speaking_slot: StringName = &"coffee_cat"
## The dialogue slot whose silence Quibble fills with continuous chugging.
@export var chugging_slot: StringName = &"miner"
var _motion_presenter: CharacterPresenter
var _sprite_rest_position: Vector2
var _jitter_elapsed_seconds: float = 0.0
var _drink_elapsed_seconds: float = 0.0
var _phase_elapsed_seconds: float = 0.0
var _jitter_index: int = 0
var _coffee_phase: CoffeePhase = CoffeePhase.WAITING
var _is_speaking: bool = false
var _is_forced_chugging: bool = false


## Takes stage ownership and starts the bounded actor-specific routine.
func prepare(
	presenter: CharacterPresenter,
	floor_sampler: Callable
) -> bool:
	if not super.prepare(presenter, floor_sampler):
		return false
	_motion_presenter = presenter
	_sprite_rest_position = presenter.character_sprite.position
	_jitter_elapsed_seconds = 0.0
	_drink_elapsed_seconds = 0.0
	_phase_elapsed_seconds = 0.0
	_jitter_index = 0
	_coffee_phase = CoffeePhase.WAITING
	_is_speaking = false
	_is_forced_chugging = false
	set_process(true)
	return true


## Stops the coffee while Quibble talks and chugs through the Miner's silence.
##
## He cannot deliver a line with his face in a mug. The chug is a full second of
## every three, so left alone it lands on top of a line often enough to be a
## coin toss, and the line it ruins most is the one where he holds the coffee out
## to give it away.
##
## Suppressed for the whole Quibble line rather than only while it types. The
## Miner's line starts on the drink pose immediately, then alternates a committed
## chug with the brief cup-held recovery for as long as the player leaves "..."
## displayed. Advancing the line returns to cup-out before Quibble speaks again.
##
## The clock is reset rather than paused, so he never resumes into the middle of
## a swig he began before the line went up.
func on_dialogue_line_presented(
	speaker_slot: StringName,
	_line_index: int
) -> void:
	var is_his_line := speaker_slot == speaking_slot
	_is_speaking = is_his_line
	_is_forced_chugging = speaker_slot == chugging_slot
	_drink_elapsed_seconds = 0.0
	_phase_elapsed_seconds = 0.0
	if _is_forced_chugging:
		_coffee_phase = CoffeePhase.DRINKING
		if is_instance_valid(_motion_presenter):
			_motion_presenter.play_pose(&"drink")
		return
	_coffee_phase = CoffeePhase.WAITING
	# Straight back to cup-out when the line advances, including when it leaves
	# the forced chug. The controller applies Quibble's line pose immediately
	# afterwards, so both owners agree on the authored reset.
	if is_instance_valid(_motion_presenter):
		_motion_presenter.play_pose(&"idle")


## Advances only fixed timers and reuses authored poses without allocations.
func _process(delta: float) -> void:
	if not _is_active or not is_instance_valid(_motion_presenter):
		_stop_quibble_motion()
		return

	_jitter_elapsed_seconds += delta
	if _jitter_elapsed_seconds >= JITTER_STEP_SECONDS:
		_jitter_elapsed_seconds = fmod(
			_jitter_elapsed_seconds,
			JITTER_STEP_SECONDS
		)
		_jitter_index = (_jitter_index + 1) % JITTER_OFFSETS.size()
		_motion_presenter.character_sprite.position = (
			_sprite_rest_position + JITTER_OFFSETS[_jitter_index]
		)

	# The jitter above keeps running while he talks. That is the half of the
	# caffeine that belongs under a line - he is vibrating the whole time, and
	# only the drinking has to wait its turn.
	if _is_speaking:
		return

	_phase_elapsed_seconds += delta
	if _is_forced_chugging:
		if (
			_coffee_phase == CoffeePhase.DRINKING
			and _phase_elapsed_seconds >= DRINK_SECONDS
		):
			_phase_elapsed_seconds = 0.0
			_coffee_phase = CoffeePhase.RECOVERING
			_motion_presenter.play_pose(&"hold_cup")
		elif (
			_coffee_phase == CoffeePhase.RECOVERING
			and _phase_elapsed_seconds >= HOLD_CUP_SECONDS
		):
			_phase_elapsed_seconds = 0.0
			_coffee_phase = CoffeePhase.DRINKING
			_motion_presenter.play_pose(&"drink")
		return

	_drink_elapsed_seconds += delta
	if (
		_coffee_phase == CoffeePhase.WAITING
		and _drink_elapsed_seconds >= DRINK_INTERVAL_SECONDS
	):
		_drink_elapsed_seconds -= DRINK_INTERVAL_SECONDS
		_phase_elapsed_seconds = 0.0
		_coffee_phase = CoffeePhase.HOLDING
		_motion_presenter.play_pose(&"hold_cup")
	elif (
		_coffee_phase == CoffeePhase.HOLDING
		and _phase_elapsed_seconds >= HOLD_CUP_SECONDS
	):
		_phase_elapsed_seconds = 0.0
		_coffee_phase = CoffeePhase.DRINKING
		_motion_presenter.play_pose(&"drink")
	elif (
		_coffee_phase == CoffeePhase.DRINKING
		and _phase_elapsed_seconds >= DRINK_SECONDS
	):
		_phase_elapsed_seconds = 0.0
		_coffee_phase = CoffeePhase.RECOVERING
		_motion_presenter.play_pose(&"hold_cup")
	elif (
		_coffee_phase == CoffeePhase.RECOVERING
		and _phase_elapsed_seconds >= HOLD_CUP_SECONDS
	):
		_phase_elapsed_seconds = 0.0
		_coffee_phase = CoffeePhase.WAITING
		_motion_presenter.play_pose(&"idle")


## Stops the routine after the shared closing choreography completes.
func play_closing() -> void:
	await super.play_closing()
	_stop_quibble_motion()


## Restores Quibble before the shared stage restores its actor snapshot.
func cancel_and_restore() -> void:
	_stop_quibble_motion()
	super.cancel_and_restore()


func _exit_tree() -> void:
	_stop_quibble_motion()


## Releases the one retained presenter and restores its visual-only offset.
func _stop_quibble_motion() -> void:
	set_process(false)
	_is_speaking = false
	_is_forced_chugging = false
	_drink_elapsed_seconds = 0.0
	_phase_elapsed_seconds = 0.0
	_coffee_phase = CoffeePhase.WAITING
	if is_instance_valid(_motion_presenter):
		_motion_presenter.character_sprite.position = _sprite_rest_position
		_motion_presenter.play_pose(&"idle")
	_motion_presenter = null
