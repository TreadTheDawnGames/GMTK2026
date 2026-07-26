extends SceneTree

## How it works:
## - Loads Encounter 1's shipped sequence and inspects its typed camera beats.
## - Verifies dialogue begins after the close frame and exit after the reset.
## - Uses authored beat data only, so the check is deterministic and headless.
## - The invariant is that dialogue is close-framed and mining gets neutral zoom.

const _SEQUENCE_PATH := (
	"res://resources/cinematics/sequences/cheese_girl_first_sequence.tres"
)
const _EXPECTED_OFFSET := Vector2(48.0, 0.0)
const _EXPECTED_ZOOM := Vector2(1.4, 1.4)

var _failures: PackedStringArray = []


func _initialize() -> void:
	var sequence := load(_SEQUENCE_PATH) as CutsceneSequence
	_expect(sequence != null, "Encounter 1 sequence must load.")
	if sequence != null:
		_verify_framing(sequence)
	if _failures.is_empty():
		print("CHEESE_GIRL_CAMERA_FRAMING_PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _verify_framing(sequence: CutsceneSequence) -> void:
	var frame: CutsceneBeat
	var reset: CutsceneBeat
	var dialogue: CutsceneBeat
	var exit_move: CutsceneBeat
	for beat in sequence.beats:
		if beat == null:
			continue
		if beat.kind == CutsceneBeat.Kind.CAMERA:
			if beat.camera_action == CutsceneBeat.CameraAction.FRAME:
				frame = beat
			elif beat.camera_action == CutsceneBeat.CameraAction.RESET:
				reset = beat
		elif beat.kind == CutsceneBeat.Kind.DIALOGUE:
			dialogue = beat
		elif (
			beat.kind == CutsceneBeat.Kind.MOVE
			and beat.actor == &"cheese_girl"
			and beat.target_marker == &"Exit"
		):
			exit_move = beat

	_expect(frame != null, "Encounter 1 needs a CAMERA/FRAME beat.")
	_expect(reset != null, "Encounter 1 needs a CAMERA/RESET beat.")
	_expect(dialogue != null, "Encounter 1 needs its dialogue beat.")
	_expect(exit_move != null, "Encounter 1 needs Cheese Girl's exit move.")
	if frame == null or reset == null or dialogue == null or exit_move == null:
		return
	_expect(
		frame.camera_offset.is_equal_approx(_EXPECTED_OFFSET),
		"Frame must centre the 96px two-person span."
	)
	_expect(
		frame.camera_zoom.is_equal_approx(_EXPECTED_ZOOM),
		"Frame must use Encounter 9's 1.40 conversational zoom."
	)
	_expect(
		dialogue.start_seconds >= frame.get_end_seconds(),
		"Dialogue must wait until the close frame settles."
	)
	_expect(
		reset.start_seconds >= dialogue.get_end_seconds(),
		"Camera reset must wait until dialogue finishes."
	)
	_expect(
		exit_move.start_seconds >= reset.get_end_seconds(),
		"Cheese Girl must exit only after neutral framing returns."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
