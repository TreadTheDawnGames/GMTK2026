class_name FinaleApproachMusic
extends Node

## How it works:
## - Two depth thresholds on the way to the Thief, and nothing else: the run's
##   adaptive music dies at the first, and Toccata and Fugue starts at the
##   second, so the last stretch of the dig is silent and the last two minutes
##   are an organ the player has not been shown yet.
## - Depth drives both, not elapsed time, because depth is what everything else
##   in this game is scheduled on and a wall clock cannot be replayed. The
##   defaults were converted from Jared's "half an hour" and "two minutes" at the
##   late-game descent rate, and they are exports because that rate is the one
##   number here that only a playtest can settle.
## - The music does not fade back in. The adaptive score is gone from the moment
##   it dies, which is the point of killing it: the player should notice the
##   quiet long before they know why.
## - Toccata is 21MB and is loaded in the background when the music dies, half an
##   hour before it is needed, so nothing hitches when it starts.
## - The invariant is that each threshold fires exactly once per run, and a run
##   reset puts everything back.

## Remaining depth at which the adaptive score begins to die.
##
## 5,600 rows at roughly 190 rows a minute is about half an hour of digging. That
## rate is measured off the gap between the post-credits encounter at 15,200 and
## the Thief at 100,000 across Zephan's eight-hour figure, so it is an estimate
## from one estimate and is expected to move once somebody has actually played
## the last hour.
@export var silence_remaining_depth: int = 5_600
## Remaining depth at which the organ starts. About two minutes at the same rate.
##
## It has to be far enough out that the piece is genuinely playing before the
## ceiling breaks - the player should arrive into music that started without
## them, not trigger it.
@export var organ_remaining_depth: int = 400
## How long the adaptive score takes to die. Long and unhurried on purpose: a
## hard cut reads as a bug or a dropped stream, and a slow one reads as the game
## losing interest.
@export_range(0.5, 60.0, 0.5) var silence_fade_seconds: float = 12.0
@export var organ_volume_db: float = -4.0
## Whether the adaptive score is allowed back after the finale.
##
## Off, and that is a decision rather than an oversight. The player keeps digging
## after the Thief, forever, and what they dig to is the organ playing itself out
## and then nothing. Turning this on gives them the run's music back the moment
## the shot ends, which hands the game's own argument straight back to it.
@export var restores_music_after_finale: bool = false

const _ORGAN_STREAM_PATH: String = (
	"res://Assets/Audio/Music/Kevin MacLeod - J. S. Bach_ Toccata and Fugue in D Minor.mp3"
)
const _MUSIC_BUS: StringName = &"Music"
const _SILENCE_DB: float = -60.0

var _conductor: AudioStreamPlayer
var _organ_player: AudioStreamPlayer
var _fade_tween: Tween
var _has_silenced: bool = false
var _has_started_organ: bool = false
var _organ_load_requested: bool = false


## Takes the running score it is going to switch off, and builds its own player.
##
## The conductor is handed in rather than looked up, because this owns one
## decision - when the music changes - and should not also own finding it.
func configure(conductor: AudioStreamPlayer) -> void:
	_conductor = conductor
	if _organ_player == null:
		_organ_player = AudioStreamPlayer.new()
		_organ_player.name = "OrganPlayer"
		_organ_player.bus = _MUSIC_BUS
		_organ_player.volume_db = organ_volume_db
		# ALWAYS because the cutscene it plays under pauses the tree, and an
		# organ that stops the instant the dialogue box opens is worse than no
		# organ at all.
		_organ_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_organ_player)


## Checks both thresholds against how far is left to dig.
func notice_remaining_depth(remaining_depth: int) -> void:
	if not _has_silenced and remaining_depth <= silence_remaining_depth:
		_has_silenced = true
		_begin_silence()
		_request_organ_stream()
	if not _has_started_organ and remaining_depth <= organ_remaining_depth:
		_has_started_organ = true
		_start_organ()


## Hands the run's music back once the Thief has said his piece, if it is ever
## decided that he should not get the last word.
func notice_finale_finished() -> void:
	if not restores_music_after_finale or _conductor == null:
		return
	_cancel_fade()
	_conductor.volume_db = 0.0
	_conductor.play()


## Puts the score and the organ back for a fresh run.
func _on_run_reset() -> void:
	_has_silenced = false
	_has_started_organ = false
	_cancel_fade()
	if _organ_player != null:
		_organ_player.stop()
	if _conductor != null:
		_conductor.volume_db = 0.0


## Fades the adaptive score out and then stops it for good.
##
## Stopping matters as much as the fade. The conductor restarts itself from its
## own `finished` signal and lays fills on its own `beat`, and neither fires once
## it is stopped - so this is what makes the silence stay silent, where leaving a
## silent player running would have the score climb back in at the next track
## change with its volume already down and then tween itself audible again.
func _begin_silence() -> void:
	if _conductor == null:
		return
	_cancel_fade()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(
		_conductor,
		"volume_db",
		_SILENCE_DB,
		silence_fade_seconds
	)
	_fade_tween.tween_callback(_stop_adaptive_score)


## Silences the conductor and any fill still in the air behind it.
func _stop_adaptive_score() -> void:
	if _conductor != null:
		_conductor.stop()
	# The fill players live on the music manager, not here, and they are the one
	# thing that can still make noise after the conductor has gone quiet.
	var music_manager := get_node_or_null(^"/root/MusicManager")
	if music_manager == null:
		return
	for player_name in ["Track1", "Track2", "Track3"]:
		var player := music_manager.find_child(player_name, true, false)
		if player is AudioStreamPlayer:
			(player as AudioStreamPlayer).stop()


## Starts the background load, half an hour before the stream is wanted.
func _request_organ_stream() -> void:
	if _organ_load_requested:
		return
	_organ_load_requested = true
	ResourceLoader.load_threaded_request(_ORGAN_STREAM_PATH, "AudioStream")


## Plays Toccata and Fugue, taking the stream the silence began loading.
func _start_organ() -> void:
	if _organ_player == null:
		return
	if not _organ_load_requested:
		# Nothing asked for it, which means the silence threshold was skipped -
		# one enormous combo can cross both in a single hit. Ask now and accept
		# that this one blocks.
		_request_organ_stream()
	var stream := ResourceLoader.load_threaded_get(
		_ORGAN_STREAM_PATH
	) as AudioStream
	if stream == null:
		push_warning("The finale organ stream could not be loaded.")
		return
	_organ_player.stream = stream
	_organ_player.volume_db = organ_volume_db
	_organ_player.play()


## Drops any fade still running so two of them can never fight over the volume.
func _cancel_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
