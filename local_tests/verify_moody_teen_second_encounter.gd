extends SceneTree

## How it works:
## - Loads every Encounter 7.5 resource through its production type.
## - Asserts the 10,500 insertion and reuse of the authorized Ayden dialogue.
## - Validates still staging, typed camera framing, and persistent closing.
## - Proves the 49-column throat opens into a distinct four-stratum bell.
## - The invariant is that the repeated gag returns mining with no reward.

const ENCOUNTER_PATH: String = (
	"res://resources/encounters/moody_teen_second_encounter.tres"
)
const DIALOGUE_PATH: String = (
	"res://resources/dialogue/moody_teen_first_conversation.tres"
)
const EXPECTED_SPEAKERS := [
	&"miner",
	&"moody_teen",
	&"miner",
	&"moody_teen",
	&"miner",
	&"moody_teen",
	&"miner",
]
const EXPECTED_TEXT := [
	"...",
	"...",
	"...",
	"...",
	"...",
	"Are you just gonna stand there and stare at me?",
	"...",
]

var _failures: Array[String] = []


func _initialize() -> void:
	var encounter := load(ENCOUNTER_PATH) as DepthCharacterEncounter
	if encounter == null:
		_failures.append("Encounter resource did not load.")
	else:
		_verify_encounter(encounter)
	_finish()


func _verify_encounter(encounter: DepthCharacterEncounter) -> void:
	_expect(encounter.encounter_id == &"moody_teen_second", "Wrong encounter ID.")
	_expect(encounter.actor_id == &"moody_teen", "Wrong actor ID.")
	_expect(encounter.depth_from_surface == 10500, "Depth must be 10,500.")
	_expect(
		encounter.chamber_height_rows_override == 88,
		"Entry throat must reserve an 88-row chamber."
	)
	_expect(encounter.plays_authored_timeline, "Timeline opt-in is missing.")
	_expect(encounter.prestage_before_landing, "Fall discovery opt-in is missing.")
	_expect(encounter.dresses_trodden_floor, "Trodden-floor opt-in is missing.")
	_expect(encounter.pickaxe_reward == null, "The encounter must grant no reward.")
	_expect(not encounter.occurs_at_run_bottom, "The encounter must be depth-pinned.")
	_expect(encounter.conversation != null, "Conversation is missing.")
	_expect(encounter.sequence != null, "Timeline is missing.")
	_expect(encounter.stage_scene != null, "Stage is missing.")
	_expect(encounter.terrain_sculpt != null, "Terrain sculpt is missing.")

	if encounter.conversation != null:
		_verify_dialogue(encounter.conversation)
	if encounter.sequence != null:
		_verify_sequence(encounter.sequence, encounter.conversation)
	if encounter.stage_scene != null:
		_verify_stage(encounter.stage_scene)
	if encounter.terrain_sculpt != null:
		_verify_sculpt(encounter.terrain_sculpt)


func _verify_dialogue(conversation: DialogueConversation) -> void:
	_expect(
		conversation.resource_path == DIALOGUE_PATH,
		"Encounter 7.5 must reuse the approved Encounter 4.5 conversation."
	)
	_expect(conversation.lines.size() == 7, "Conversation must have seven lines.")
	for index in range(mini(conversation.lines.size(), EXPECTED_TEXT.size())):
		var line := conversation.lines[index]
		_expect(line != null, "Dialogue line %d is empty." % (index + 1))
		if line == null:
			continue
		_expect(
			line.speaker_slot == EXPECTED_SPEAKERS[index],
			"Dialogue line %d has the wrong speaker." % (index + 1)
		)
		_expect(
			line.text == EXPECTED_TEXT[index],
			"Dialogue line %d has the wrong text." % (index + 1)
		)


func _verify_sequence(
	sequence: CutsceneSequence,
	conversation: DialogueConversation
) -> void:
	var errors := sequence.validate(PackedStringArray(["moody_teen"]))
	_expect(errors.is_empty(), "Timeline validation failed: %s" % "; ".join(errors))
	_expect(sequence.beats.size() == 6, "Timeline must have exactly six beats.")
	var expected_kinds := [
		CutsceneBeat.Kind.SHOW,
		CutsceneBeat.Kind.FACE,
		CutsceneBeat.Kind.WAIT,
		CutsceneBeat.Kind.CAMERA,
		CutsceneBeat.Kind.DIALOGUE,
		CutsceneBeat.Kind.CAMERA,
	]
	for index in range(mini(sequence.beats.size(), expected_kinds.size())):
		_expect(
			sequence.beats[index].kind == expected_kinds[index],
			"Timeline beat %d has the wrong kind." % (index + 1)
		)
	if sequence.beats.size() != 6:
		return

	var frame_beat := sequence.beats[3]
	var dialogue_beat := sequence.beats[4]
	var reset_beat := sequence.beats[5]
	_expect(
		frame_beat.camera_action == CutsceneBeat.CameraAction.FRAME,
		"Conversation camera beat must frame the cast."
	)
	_expect(
		frame_beat.camera_offset.is_equal_approx(Vector2(66.4, -24.0)),
		"Conversation camera must retain the entry throat above the two-shot."
	)
	_expect(
		frame_beat.camera_zoom.is_equal_approx(Vector2(1.25, 1.25)),
		"Conversation camera must preserve the wider bell composition."
	)
	_expect(
		dialogue_beat.start_seconds >= frame_beat.get_end_seconds(),
		"Dialogue must wait for the camera frame."
	)
	_expect(dialogue_beat.conversation == conversation, "Timeline dialogue drifted.")
	_expect(dialogue_beat.blocks, "Dialogue must block for reading.")
	_expect(
		dialogue_beat.line_range == Vector2i(-1, -1),
		"Dialogue must play the complete exchange."
	)
	_expect(
		reset_beat.camera_action == CutsceneBeat.CameraAction.RESET,
		"Final camera beat must restore neutral framing."
	)
	_expect(
		reset_beat.start_seconds >= dialogue_beat.get_end_seconds(),
		"Camera reset must follow the nominal dialogue end."
	)


func _verify_stage(stage_scene: PackedScene) -> void:
	var stage := stage_scene.instantiate() as CharacterEncounterStage
	_expect(stage != null, "Stage is not a CharacterEncounterStage.")
	if stage == null:
		return
	_expect(stage.validate_stage().is_empty(), "Stage marker validation failed.")
	_expect(stage.conversation_tracks_miner, "Ayden must track the landing column.")
	_expect(
		is_equal_approx(stage.conversation_root_offset_from_miner_x, 132.8),
		"Ayden spacing must remain the measured 132.8px."
	)
	_expect(not stage.hide_actor_after_closing, "Ayden must remain after closing.")
	_expect(stage.opening_step_height == 0.0, "Ayden must not hop or walk.")
	_expect(stage.opening_pose == &"idle", "Opening pose must remain idle.")
	_expect(stage.closing_pose == &"idle", "Closing pose must remain idle.")
	var expected_position := stage.conversation_marker.position
	for marker in [
		stage.entrance_marker,
		stage.work_marker,
		stage.rest_marker,
		stage.exit_marker,
	]:
		_expect(marker.position == expected_position, "Every actor marker must match.")
	stage.free()


func _verify_sculpt(sculpt: CutsceneTerrainSculpt) -> void:
	_expect(sculpt.get_sculpt_error().is_empty(), "Sculpt is invalid.")
	_expect(sculpt.grid_size == Vector2i(384, 120), "Sculpt grid drifted.")
	_expect(
		sculpt.anchor_offset_cells == Vector2i(-192, -110),
		"Sculpt anchor drifted."
	)
	_expect(sculpt.layer_solid_bits.size() == 4, "Sculpt needs four strata.")
	var landing_rows := sculpt.get_landing_local_rows(24)
	_expect(landing_rows.size() == 49, "Sculpt must cover 49 landing columns.")
	var floor_row := sculpt.get_floor_local_row()
	for landing_row in landing_rows:
		_expect(landing_row == floor_row, "Every landing must reach the floor.")
	for local_x in range(168, 217):
		_expect(
			not sculpt.is_solid_local(Vector2i(local_x, 12)),
			"Entry throat must remain open at column %d." % local_x
		)

	_expect(
		sculpt.is_solid_local(Vector2i(120, 20)),
		"Upper left shoulder must stay closed beside the throat."
	)
	_expect(
		not sculpt.is_solid_local(Vector2i(120, floor_row - 14)),
		"Lower left shoulder must flare into the bell."
	)
	_expect(
		not sculpt.is_solid_local(Vector2i(260, floor_row - 14)),
		"Lower right alcove must open wider than the throat."
	)
	var lower_centre := Vector2i(192, floor_row - 18)
	_expect(not sculpt.is_solid_local(lower_centre), "Lower bell must be open.")
	_expect(
		sculpt.is_layer_solid_local(3, lower_centre),
		"Deep stratum must close the cavern backdrop."
	)


func _expect(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)


func _finish() -> void:
	if _failures.is_empty():
		print("MOODY_TEEN_SECOND_ENCOUNTER_VERIFY_PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("MOODY_TEEN_SECOND_ENCOUNTER_VERIFY_FAIL: %s" % failure)
	quit(1)
