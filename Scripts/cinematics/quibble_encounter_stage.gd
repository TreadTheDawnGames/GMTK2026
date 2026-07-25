class_name QuibbleEncounterStage
extends CharacterEncounterStage

## How it works:
## - prepare() starts Quibble's presentation-only vibration and coffee clock.
## - The sprite snaps through a tiny fixed jitter pattern at a bounded rate.
## - Every seven seconds it plays hold, drink, hold, then returns to idle.
## - Dialogue may still request poses; the next coffee phase resumes the loop.
## - Closing or cancellation restores the exact authored sprite position.
## - The invariant is that Quibble never moves the authoritative actor root.

const DRINK_INTERVAL_SECONDS: float = 7.0
const HOLD_CUP_SECONDS: float = 0.18
const DRINK_SECONDS: float = 0.72
const JITTER_STEP_SECONDS: float = 0.035
const JITTER_OFFSETS := [
	Vector2(-2.0, 0.0),
	Vector2(2.0, -1.0),
	Vector2(-1.0, 1.0),
	Vector2(1.0, 0.0),
	Vector2(0.0, -1.0),
	Vector2(2.0, 1.0),
	Vector2(-2.0, -1.0),
	Vector2.ZERO,
]

enum CoffeePhase {
	WAITING,
	HOLDING,
	DRINKING,
	RECOVERING,
}

var _motion_presenter: CharacterPresenter
var _sprite_rest_position: Vector2
var _jitter_elapsed_seconds: float = 0.0
var _drink_elapsed_seconds: float = 0.0
var _phase_elapsed_seconds: float = 0.0
var _jitter_index: int = 0
var _coffee_phase: CoffeePhase = CoffeePhase.WAITING


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
	set_process(true)
	return true


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

	_drink_elapsed_seconds += delta
	_phase_elapsed_seconds += delta
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
	if is_instance_valid(_motion_presenter):
		_motion_presenter.character_sprite.position = _sprite_rest_position
	_motion_presenter = null
