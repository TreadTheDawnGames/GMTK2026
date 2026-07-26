extends SceneTree

## How it works:
## - Loads Encounter 5's registered resources and real stage.
## - Protects its canonical dialogue, typed camera beats, and joint fade.
## - Checks the cavern's landing span, headroom, walls, and visual strata.
## - Reports every contract failure together instead of stopping at the first.
## - The invariant is that presentation edits cannot change Encounter 5's story.

const ENCOUNTER_PATH: String = (
	"res://resources/encounters/cloak_lantern_warning_encounter.tres"
)
const EXPECTED_LINES: Array[String] = [
	"You kept digging.",
	"...",
	(
		"Everyone thinks the Thief is waiting below. "
		+ "They never notice what goes missing on the way."
	),
]

var _failures: Array[String] = []


func _initialize() -> void:
	var encounter := load(ENCOUNTER_PATH) as DepthCharacterEncounter
	if encounter == null:
		_failures.append("Encounter 5 could not be loaded.")
	else:
		_verify_dialogue(encounter)
		_verify_sequence(encounter.sequence)
		_verify_stage(encounter.stage_scene)
		_verify_sculpt(encounter.terrain_sculpt)

	if _failures.is_empty():
		print("ENCOUNTER_5_VERIFY_PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("ENCOUNTER_5_VERIFY_FAIL: %s" % failure)
	quit(1)


func _verify_dialogue(encounter: DepthCharacterEncounter) -> void:
	var conversation := encounter.conversation
	if conversation == null or conversation.lines.size() != EXPECTED_LINES.size():
		_failures.append("The canonical three-line conversation changed.")
		return
	for line_index in range(EXPECTED_LINES.size()):
		var line := conversation.lines[line_index]
		if line == null or line.text != EXPECTED_LINES[line_index]:
			_failures.append("Canonical dialogue line %d changed." % (line_index + 1))


func _verify_sequence(sequence: CutsceneSequence) -> void:
	if sequence == null:
		_failures.append("The authored sequence is missing.")
		return
	for sequence_error: String in sequence.validate(PackedStringArray(["cloak_lantern"])):
		_failures.append("Sequence validation: %s" % sequence_error)
	var frame_beat: CutsceneBeat
	var reset_beat: CutsceneBeat
	for beat: CutsceneBeat in sequence.beats:
		if beat.kind != CutsceneBeat.Kind.CAMERA:
			continue
		if beat.camera_action == CutsceneBeat.CameraAction.FRAME:
			frame_beat = beat
		elif beat.camera_action == CutsceneBeat.CameraAction.RESET:
			reset_beat = beat
	if frame_beat == null:
		_failures.append("The dialogue camera push-in is missing.")
	elif (
		not frame_beat.camera_zoom.is_equal_approx(Vector2(1.4, 1.4))
		or not frame_beat.camera_offset.is_equal_approx(Vector2(80.2, -8.0))
	):
		_failures.append("The dialogue camera no longer frames the measured two-shot.")
	if reset_beat == null or reset_beat.get_end_seconds() > 7.5:
		_failures.append("The camera does not reset before the closing fade.")


func _verify_stage(stage_scene: PackedScene) -> void:
	if stage_scene == null:
		_failures.append("The stage scene is missing.")
		return
	var stage := stage_scene.instantiate() as CharacterEncounterStage
	if stage == null:
		_failures.append("The stage no longer instantiates as the shared stage type.")
		return
	if not is_equal_approx(stage.closing_fade_seconds, 0.75):
		_failures.append("The requested quicker 0.75s Keeper fade changed.")
	if stage.get_node_or_null("PropMarkers/Bench") == null:
		_failures.append("The Keeper's jointly fading bench is missing.")
	var animation_player := stage.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if (
		animation_player == null
		or not animation_player.has_animation(&"closing")
		or not is_equal_approx(
			animation_player.get_animation(&"closing").length,
			0.75
		)
	):
		_failures.append("The bench fade no longer matches the Keeper fade.")
	stage.free()


func _verify_sculpt(sculpt: CutsceneTerrainSculpt) -> void:
	if sculpt == null or not sculpt.get_sculpt_error().is_empty():
		_failures.append("The authored cavern is missing or invalid.")
		return
	var mining_config := load(
		"res://resources/mining/mining_config.tres"
	) as MiningConfig
	var landing_rows := sculpt.get_landing_local_rows(
		mining_config.snake_half_span_cells
	)
	var floor_row := sculpt.get_floor_local_row()
	for landing_row: int in landing_rows:
		if (
			landing_row < 0
			or floor_row - landing_row
				> DepthEncounterController.LANDING_FLOOR_TOLERANCE_ROWS
		):
			_failures.append("The cavern no longer has a safe full landing span.")
			break
	if sculpt.layer_solid_bits.size() != 4:
		_failures.append("The cavern no longer carries four visual strata.")
	if not sculpt.is_solid_local(Vector2i(90, 96)):
		_failures.append("The cavern's left end is no longer closed.")
	if not sculpt.is_solid_local(Vector2i(294, 96)):
		_failures.append("The cavern's right end is no longer closed.")
