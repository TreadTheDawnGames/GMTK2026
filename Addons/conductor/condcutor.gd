@icon("res://addons/conductor/icons/Conductor.png")
extends AudioStreamPlayer

## How it works:
## - The playing stream is the authoritative music clock.
## - Each physics tick converts its audible playback position into beats.
## - Every crossed beat and measure is emitted, including after a delayed frame.
## - Reported playback never moves backward because mixer samples can jitter.
## - The invariant is that consumers observe every beat once and in order.

## Mixer compensation is normally one small audio buffer. Capping it prevents a
## browser-resume spike from becoming permanent authoritative song time.
const MAX_MIX_COMPENSATION_SECONDS: float = 0.1
const INTENTIONAL_REWIND_TOLERANCE_SECONDS: float = 0.1

var bpm : float = 120
var beats_per_measure : int = 4
var first_beat_offset : float = 0

# Tracking the beat and song position
var song_position:float = 0.0
var current_beat:float = 0
var sec_per_beat:float #= 60.0 / bpm
var beat_per_sec:float
var last_reported_beat:int = -1
var last_reported_update:float = 0
var last_reported_measure:int = -1
var current_measure:int = 0
#var beats_before_start:int = 0

# Determining how close to the beat an event is
#var closest = 0
#var time_off_beat = 0.0

var is_playing_offset:bool = false

signal beat(position)
signal measure(position)
signal update(delta, beat_position, measure_position)

#func _ready() -> void:
	#set_song(load("res://Another Time Perhaps.mp3"),93*2,4)
	#play_song_from_beat(0)

func set_song(
	_stream: AudioStream,
	_bpm: float,
	_beats_per_measure: int,
	_first_beat_offset: float = 0.0
) -> void:
	if stream != _stream:
		stream=_stream
	bpm = _bpm
	beats_per_measure = maxi(_beats_per_measure, 1)
	first_beat_offset = _first_beat_offset
	sec_per_beat = 60.0 / bpm
	beat_per_sec = bpm / 60.0
	reset_timeline(0.0)


func play_song_from_beat(beat: float) -> void:
	play(sec_per_beat*beat)
	reset_timeline(beat)


func play_song_with_start_offset(offset: float) -> void:
	if offset <= 0.0:
		play_song_from_beat(-offset)
		return
	reset_timeline(-offset)
	is_playing_offset = true


## Resets every dependent counter together for a song change, restart, or seek.
func reset_timeline(beat_position: float) -> void:
	current_beat = beat_position
	song_position = sec_per_beat * beat_position
	last_reported_beat = floori(beat_position) - 1
	last_reported_update = beat_position
	current_measure = maxi(floori(beat_position) / beats_per_measure, 0)
	last_reported_measure = current_measure - 1
	is_playing_offset = false


func _physics_process(delta: float) -> void:
	if stream_paused:
		return
	if playing:
		var playback_position := get_playback_position()
		var mix_compensation := minf(
			AudioServer.get_time_since_last_mix(),
			MAX_MIX_COMPENSATION_SECONDS
		)
		var sampled_song_position := (
			playback_position
			+ mix_compensation
			- AudioServer.get_output_latency()
		)
		sampled_song_position = maxf(sampled_song_position, 0.0)
		if stream != null and stream.get_length() > 0.0:
			sampled_song_position = minf(
				sampled_song_position,
				stream.get_length()
			)
		# The mixer and game thread are sampled independently. A late mixer
		# update can briefly report an older value. A larger rewind is an
		# intentional restart or seek performed through AudioStreamPlayer.
		if (
			sampled_song_position
				< song_position - INTENTIONAL_REWIND_TOLERANCE_SECONDS
		):
			reset_timeline(sampled_song_position / sec_per_beat)
		else:
			song_position = maxf(song_position, sampled_song_position)
		current_beat = song_position / sec_per_beat
		_report_beat()
		_report_update()
	elif is_playing_offset:
		song_position += delta
		current_beat = beat_per_sec*song_position
		_report_beat()
		_report_update()
		if(current_beat>=0):
			play_song_from_beat(0)

func _report_beat() -> void:
	var current_whole_beat := floori(current_beat)
	if current_whole_beat < 0:
		return
	last_reported_beat = maxi(last_reported_beat, -1)
	# Beat catch-up is bounded to two measures. A larger gap is a seek, stale
	# mixer sample, or lost visibility event; resynchronizing without callbacks
	# protects one web frame from an unbounded coroutine/signal burst.
	var maximum_catch_up_beats := maxi(beats_per_measure * 2, 1)
	if current_whole_beat - last_reported_beat > maximum_catch_up_beats:
		last_reported_beat = current_whole_beat
		current_measure = current_whole_beat / beats_per_measure
		last_reported_measure = current_measure
		return
	while last_reported_beat < current_whole_beat:
		last_reported_beat += 1
		beat.emit(last_reported_beat)
		_report_measure(last_reported_beat)

func _report_measure(reported_beat: int) -> void:
	if reported_beat < 0:
		return
	if reported_beat % beats_per_measure == 0:
		current_measure = reported_beat / beats_per_measure
	
	if(last_reported_measure < current_measure):
		last_reported_measure = current_measure
		measure.emit(current_measure)
		#print("emitting measure: " + str(current_measure))

func _report_update() -> void:
	update.emit(current_beat-last_reported_update, current_beat, current_measure)
	#print("emitting update")
	last_reported_update = current_beat
