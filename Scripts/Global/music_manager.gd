extends Node

## How it works:
## - Conductor owns the authoritative song and beat position.
## - Transition fills use separate players but share Conductor's beat phase.
## - Intensity changes choose the next track; fills anticipate its final beats.
## - WebAudioFocusGuard pauses these players with every other active sound.
## - The invariant is that fills and track transitions use Conductor's beat.

@export var tracks : Array[Intensity] = []
@export var fills : Array[AudioStream] = []
@export var fail_riffs : Array[AudioStream] = []

var bpm : float = 120
var beats_per_measure : int = 4

@onready var track_1: AudioStreamPlayer = %Track1
@onready var track_2: AudioStreamPlayer = %Track2
@onready var track_3: AudioStreamPlayer = %Track3

var music_intensity : int = 0 : 
	set(value):
		music_intensity = clamp(value, 0, tracks.size()-1)

var current_intensity : int = 0
var fill_playing : bool = false

func _ready() -> void:
	Conductor.set_song(tracks[0].first(), bpm, beats_per_measure)
	#Conductor.play()
	Conductor.finished.connect(_transition_to)
	Conductor.beat.connect(_play_fill)
	
	set_process(OS.has_feature("editor"))
	
func get_total_beats() -> int:
	if Conductor.stream == null or Conductor.sec_per_beat <= 0.0:
		return 0
	return maxi(
		roundi(Conductor.stream.get_length() / Conductor.sec_per_beat),
		0
	)


func get_beats_remaining(song_beat: float = -1.0) -> float:
	var sampled_beat: float = (
		float(Conductor.current_beat)
		if song_beat < 0.0
		else song_beat
	)
	return maxf(float(get_total_beats()) - sampled_beat, 0.0)

func _transition_to():
	Conductor.set_song(tracks[music_intensity].pick_random(), bpm, beats_per_measure)
	Conductor.play()
	current_intensity = music_intensity

#func _process(delta: float) -> void:
	#if Input.is_action_just_pressed("aim_right"):
		#music_intensity += 1
		#set_intensity_on_beat(music_intensity)
		#print("music intensity: ", music_intensity)
	#if Input.is_action_just_pressed("aim_left"):
		#music_intensity -= 1
		#print("music intensity: ", music_intensity)
		#set_intensity_on_beat(music_intensity)
	#if Input.is_action_just_pressed("Space"):
		#set_intensity_on_beat(music_intensity)
		#print("music intensity: ", music_intensity)

## Number of beats from the song boundary at which its aligned fill becomes
## audible. The fill itself remains a full phrase and is sought to its tail.
var fill_overlap: int = 3

func _play_fill(beat_number: int = -1) -> void:
	var beats_remaining := get_beats_remaining(float(beat_number))
	if (
		beats_remaining > float(fill_overlap)
		or fill_playing
		or fills.is_empty()
	):
		return
	var fill_stream: AudioStream = fills.pick_random()
	if fill_stream == null:
		return
	fill_playing = true
	_play_aligned_fill(fill_stream, beats_remaining)
	await track_1.finished
	fill_playing = false

func force_play_fill(stream: AudioStream = null) -> void:
	var fill_stream: AudioStream = stream
	if fill_stream == null:
		if fills.is_empty():
			return
		fill_stream = fills.pick_random()
	fill_playing = true
	_play_aligned_fill(fill_stream, get_beats_remaining())
	await track_1.finished
	fill_playing = false


## Seeks a full-length fill so its final sample shares the song's final sample.
func _play_aligned_fill(
	fill_stream: AudioStream,
	beats_remaining: float
) -> void:
	track_1.stream = fill_stream
	var seconds_remaining: float = (
		beats_remaining * float(Conductor.sec_per_beat)
	)
	var start_seconds: float = maxf(
		fill_stream.get_length() - seconds_remaining,
		0.0
	)
	track_1.play(start_seconds)

func set_current_intensity(intensity : int):
	music_intensity = intensity
	
func _on_intensity_changed(intensity : int, previous_intensity):
	if intensity != previous_intensity:
		set_current_intensity(intensity)

func _on_combo_tier_changed(tier: int, previous_tier: int):
	pass

func _on_streak_lost(previous_combo : int, previous_tier : int):
	if previous_combo > 0:
		set_current_intensity(0)
	pass

func _on_run_reset():
	set_current_intensity(0)
	pass

func play_song_from_beat(beat:float, sec_per_beat : float):
	track_1.play(sec_per_beat*beat)

## sets the intensity after a number of beats equal to [beats] and plays the new intenisty from the asked for beat. 
# If 0 it waits until the end of the measure.
func set_intensity_after_measure(intensity : int):
	music_intensity = intensity
	
	while int(Conductor.current_beat) % beats_per_measure != 0:
		await Conductor.beat
	#force_play_fill(fail_riffs.pick_random() if fail_riffs.size() > 0 else null)
	
	Conductor.set_song(tracks[music_intensity].pick_random(), bpm, beats_per_measure)
	Conductor.play()
	current_intensity = music_intensity
	pass
