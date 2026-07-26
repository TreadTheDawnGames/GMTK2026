extends SceneTree

## How it works:
## - Proves the one encounter whose text is not finished until it is played.
## - Decrypts the finale conversation and checks that every {token} in it is one
##   the resolver knows, because an unknown token reaches the player as literal
##   braces in the middle of the game's last line.
## - Drives the resolver from a built record rather than the live autoload, so
##   the expected output is a fixed string rather than whatever this machine has
##   played, and reproduces the numbers Jared's script was written against.
## - Round-trips the lifetime record through a file to prove a total survives a
##   restart, which is the whole reason it is not kept in savegame.tres.
## - Checks the encounter wiring the shot depends on: the authored timeline
##   switch, the room being an external file, and the organ art.
## - Exits nonzero on any failure so this can gate a merge.

const ENCRYPTED_DIALOGUE: EncryptedDialogueConversation = preload(
	"res://resources/dialogue/thief_encrypted_dialogue.tres"
)
const FINALE_ENCOUNTER: DepthCharacterEncounter = preload(
	"res://resources/encounters/thief_final_encounter.tres"
)
const FINALE_SEQUENCE: CutsceneSequence = preload(
	"res://resources/cinematics/sequences/thief_finale_sequence.tres"
)
const _HISTORY_TEST_PATH: String = "user://player_history_verify.cfg"
# 8h 47m 28s, the run the script reads out.
const _SCRIPTED_PLAY_SECONDS: float = 31_648.0
const _SCRIPTED_PRESSES: int = 124_735

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var conversation := _verify_dialogue_decrypts()
	var history := _verify_history_round_trip()
	_verify_tokens_resolve(conversation, history)
	_verify_encounter_wiring()
	_verify_approach_music()
	if history != null:
		history.free()
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(_HISTORY_TEST_PATH)
	)
	if _failures.is_empty():
		print("THIEF_FINALE_VERIFY_PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("THIEF_FINALE_VERIFY_FAIL: %s" % failure)
	quit(1)


## Decrypts the finale and returns it, or null when it cannot be read.
func _verify_dialogue_decrypts() -> DialogueConversation:
	_expect(
		ENCRYPTED_DIALOGUE.has_payload(),
		"The finale conversation must carry encrypted story data."
	)
	var conversation := ENCRYPTED_DIALOGUE.decrypt_conversation()
	_expect(
		conversation != null,
		"The finale conversation must decrypt."
	)
	if conversation == null:
		return null
	_expect(
		conversation.conversation_id == &"thief_finale",
		"The finale conversation id must be thief_finale."
	)
	_expect(
		not conversation.lines.is_empty(),
		"The finale conversation must have lines."
	)
	# The reveal is that the Thief is the player, so the box must not name a
	# speaker before the line that says so. It carries the same "..." the
	# unattributed voice uses at depth 0, and that bookend is the point.
	_expect(
		conversation.get_participant_display_name(&"thief") == "...",
		"The finale speaker must stay unattributed."
	)
	return conversation


## Proves a lifetime total survives being written and read back.
func _verify_history_round_trip() -> PlayerHistoryRecord:
	var history := PlayerHistoryRecord.new()
	history.use_storage_path(_HISTORY_TEST_PATH)
	history.reset_history()
	history.total_play_seconds = _SCRIPTED_PLAY_SECONDS
	history.primary_action_presses = _SCRIPTED_PRESSES
	history.hour_completion_unix_times = PackedInt64Array()
	# One stamp per completed hour, an hour apart, ending at a known moment so
	# the recalled-hour lines have something real to read.
	var first_hour_end := (
		Time.get_unix_time_from_system() as int
	) - 8 * PlayerHistoryRecord.SECONDS_PER_HOUR
	for hour_index in range(8):
		history.hour_completion_unix_times.append(
			first_hour_end + hour_index * PlayerHistoryRecord.SECONDS_PER_HOUR
		)
	history.flush(true)
	history.free()

	var reloaded := PlayerHistoryRecord.new()
	reloaded.use_storage_path(_HISTORY_TEST_PATH)
	_expect(
		is_equal_approx(reloaded.total_play_seconds, _SCRIPTED_PLAY_SECONDS),
		"Play time must survive a reload; got %f." % reloaded.total_play_seconds
	)
	_expect(
		reloaded.primary_action_presses == _SCRIPTED_PRESSES,
		"Presses must survive a reload; got %d." % reloaded.primary_action_presses
	)
	_expect(
		reloaded.hour_completion_unix_times.size() == 8,
		"Hour stamps must survive a reload; got %d."
		% reloaded.hour_completion_unix_times.size()
	)
	_expect(
		reloaded.get_play_time_parts() == Vector3i(8, 47, 28),
		"Play time must read as 8:47:28; got %s."
		% str(reloaded.get_play_time_parts())
	)
	_expect(
		reloaded.get_completed_hours() == 8,
		"Eight hours of play must read as eight completed hours."
	)
	return reloaded


## Proves every token in the finale resolves, and that the numbers read right.
func _verify_tokens_resolve(
	conversation: DialogueConversation,
	history: PlayerHistoryRecord
) -> void:
	if conversation == null or history == null:
		return
	for line_index in range(conversation.lines.size()):
		var line: DialogueLine = conversation.lines[line_index]
		var resolved := DialogueTokens.resolve(line.text, history)
		_expect(
			resolved.find("{") < 0,
			"Finale line %d still holds an unresolved token: %s"
			% [line_index, resolved]
		)
		_expect(
			not resolved.strip_edges().is_empty(),
			"Finale line %d resolved to nothing." % line_index
		)
	_expect(
		DialogueTokens.resolve("{hours}", history) == "8",
		"The hours token must read 8."
	)
	_expect(
		DialogueTokens.resolve("{minutes}", history) == "47",
		"The minutes token must read 47."
	)
	_expect(
		DialogueTokens.resolve("{seconds}", history) == "28",
		"The seconds token must read 28."
	)
	_expect(
		DialogueTokens.resolve("{presses}", history) == "124,735",
		"The presses token must group thousands; got %s."
		% DialogueTokens.resolve("{presses}", history)
	)
	# Eight completed hours must reach back to hour 6 and name hour 5 before it,
	# which is the pair the script was written against.
	_expect(
		DialogueTokens.get_recalled_hour(history) == 6,
		"Eight hours of play must recall hour 6; got %d."
		% DialogueTokens.get_recalled_hour(history)
	)
	_expect(
		DialogueTokens.resolve("{early_hour}", history) == "5",
		"Eight hours of play must name hour 5 as the earlier hour."
	)
	_expect(
		DialogueTokens.group_thousands(0) == "0",
		"Zero must group as 0."
	)
	_expect(
		DialogueTokens.group_thousands(1_000) == "1,000",
		"One thousand must group as 1,000."
	)
	_expect(
		DialogueTokens.group_thousands(999) == "999",
		"Under a thousand must not gain a separator."
	)
	# A record with nothing in it is the state a player reaching the finale can
	# never actually be in, but a resolver that breaks on it would break every
	# line at once, so it has to stay grammatical.
	var empty_history := PlayerHistoryRecord.new()
	for line: DialogueLine in conversation.lines:
		_expect(
			DialogueTokens.resolve(line.text, empty_history).find("{") < 0,
			"An empty record must still resolve every token."
		)
	empty_history.free()


## Checks the wiring the shot cannot play without.
func _verify_encounter_wiring() -> void:
	_expect(
		FINALE_ENCOUNTER.occurs_at_run_bottom,
		"The finale must stay pinned to the configured run bottom."
	)
	_expect(
		FINALE_ENCOUNTER.plays_authored_timeline,
		"The finale must play its authored timeline."
	)
	_expect(
		FINALE_ENCOUNTER.sequence == FINALE_SEQUENCE,
		"The finale must reference its own sequence."
	)
	_expect(
		FINALE_ENCOUNTER.encrypted_conversation != null,
		"The finale must carry its encrypted conversation."
	)
	_expect(
		FINALE_ENCOUNTER.terrain_sculpt != null
		and not FINALE_ENCOUNTER.terrain_sculpt.resource_path.is_empty(),
		"The finale room must be an external file, not an embedded copy."
	)
	_expect(
		FINALE_ENCOUNTER.appearance != null
		and FINALE_ENCOUNTER.appearance.texture != null,
		"The figure at the organ must have art."
	)
	var sequence_errors := FINALE_SEQUENCE.validate(
		PackedStringArray([str(FINALE_ENCOUNTER.actor_id)])
	)
	_expect(
		sequence_errors.is_empty(),
		"The finale timeline must validate: %s" % ", ".join(sequence_errors)
	)


## Checks the two music cues on the approach.
##
## It drives them with no conductor attached, which is the state a headless run
## is in anyway, and is exactly what proves the thresholds are ordered and
## one-shot without needing anything to actually make a sound.
func _verify_approach_music() -> void:
	var approach := FinaleApproachMusic.new()
	root.add_child(approach)
	_expect(
		approach.silence_remaining_depth > approach.organ_remaining_depth,
		"The music must die before the organ starts, not after."
	)
	_expect(
		ResourceLoader.exists(
			"res://Assets/Audio/Music/Kevin MacLeod - J. S. Bach_ Toccata and Fugue in D Minor.mp3"
		),
		"The finale organ stream must resolve."
	)
	approach.configure(null)
	# Well clear of both cues: nothing has happened yet.
	approach.notice_remaining_depth(approach.silence_remaining_depth + 1)
	_expect(
		approach.get_node_or_null(^"OrganPlayer") != null,
		"The approach must own its own organ player."
	)
	var organ_player := approach.get_node_or_null(^"OrganPlayer")
	_expect(
		organ_player is AudioStreamPlayer
		and not (organ_player as AudioStreamPlayer).playing,
		"The organ must not be playing before its own threshold."
	)
	# One enormous combo can cross both thresholds in a single hit, and that has
	# to still land the organ rather than skipping it with the silence.
	approach.notice_remaining_depth(0)
	_expect(
		organ_player is AudioStreamPlayer
		and (organ_player as AudioStreamPlayer).stream != null,
		"Crossing both cues in one hit must still start the organ."
	)
	approach._on_run_reset()
	_expect(
		organ_player is AudioStreamPlayer
		and not (organ_player as AudioStreamPlayer).playing,
		"A run reset must stop the organ."
	)
	approach.queue_free()


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)
