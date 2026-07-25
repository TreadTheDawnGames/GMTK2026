extends Node

@export var tracks : Array[AudioStream] = []
@export var fills : Array[AudioStream] = []

@onready var track_1: AudioStreamPlayer = %Track1
@onready var track_2: AudioStreamPlayer = %Track2
@onready var track_3: AudioStreamPlayer = %Track3

var music_intensity : int = 0 : 
	set(value):
		music_intensity = clamp(value, 0, tracks.size()-1)

var current_intensity : int = 0
var fill_playing : bool = false

func _ready():
	Conductor.set_song(tracks[0], 120, 4)
	Conductor.play()
	Conductor.finished.connect(_transition_to)
	Conductor.beat.connect(_play_fill)
	
func get_total_beats() -> float:
	var beat_count = Conductor.stream.get_length() / Conductor.sec_per_beat
	return beat_count

func get_beats_remaining() -> int:
	return floor(get_total_beats() - Conductor.current_beat)

func _transition_to():
	Conductor.last_reported_beat = -1
	Conductor.set_song(tracks[music_intensity], 120, 4)
	Conductor.play()
	current_intensity = music_intensity
	

func _play_fill(_beat_number):
	if get_beats_remaining() <= 2 and current_intensity != music_intensity and not fill_playing:
		fill_playing = true
		track_1.stream = fills.pick_random()
		track_1.play()
		await track_1.finished
		fill_playing = false

func set_current_intensity(intensity : int):
	music_intensity = intensity
	pass
func _on_intensity_changed(intensity : int, previous_intensity):
	set_current_intensity(intensity)
	pass

func _on_combo_tier_changed(tier: int, previous_tier: int):
	pass

func _on_streak_lost(previous_combo : int, previous_tier : int):
	set_current_intensity(0)
	pass

func _on_run_reset():
	set_current_intensity(0)
	pass
