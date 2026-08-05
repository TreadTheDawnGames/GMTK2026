# music_manager.gd
# Rewritten 2026-08-02
# Caspian Tyler

extends Node


@export var tracksets : Dictionary[StringName, Trackset] = {}
var _current_trackset : Trackset
#var bpm : float = 120
#var beats_per_measure : int = 4

@onready var track_1: AudioStreamPlayer = %Track1
@onready var track_2: AudioStreamPlayer = %Track2
@onready var track_3: AudioStreamPlayer = %Track3

var music_intensity : int = 0 : 
	set(value):
		music_intensity = clamp(value, 0, _current_trackset.get_size()-1)

var current_intensity : int = 0
var fill_playing : bool = false

var started:bool = false

func initialize():
	change_to_trackset(&"default")
	
	Conductor.set_song(_current_trackset.get_first_track(), _current_trackset.bpm, _current_trackset.beats_per_measure)
	Conductor.play()
	dim_music_for_dialog(false, 1.0, 0.8*2)
	
	Conductor.finished.connect(_transition_to)
	Conductor.beat.connect(_play_fill)
	started = true
	set_process(OS.has_feature("editor"))
	
func get_total_beats() -> float:
	var beat_count = Conductor.stream.get_length() / Conductor.sec_per_beat
	return beat_count

func get_beats_remaining() -> int:
	return floor(get_total_beats() - Conductor.current_beat)

func _transition_to():
	Conductor.last_reported_beat = -1
	Conductor.set_song(_current_trackset.get_track_for_intensity(music_intensity), _current_trackset.bpm, _current_trackset.beats_per_measure)
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


func _play_fill(_beat_number : int = 0):
	if get_beats_remaining() <= _current_trackset.fill_offset and not fill_playing:
		fill_playing = true
		if music_intensity >= current_intensity:
			track_1.stream = _current_trackset.get_positive_fill()
		#else:
			#track_1.stream = fail_riffs.pick_random() 
		
		play_song_from_beat(_current_trackset.fill_offset-get_beats_remaining(), Conductor.sec_per_beat)
		await track_1.finished
		fill_playing = false
		

func dim_music_for_dialog(do_dim : bool, tween_length_dimming : float = 1.0, tween_length_undimming : float = 1.5) -> Tween:
	var t : Tween = create_tween()
	t.tween_property(Conductor, "volume_db", -10.0 if do_dim else 0.0, tween_length_dimming if do_dim else tween_length_undimming)
	t.tween_property(track_1, "volume_db", -10.0 if do_dim else 0.0, tween_length_dimming if do_dim else tween_length_undimming)
	return t

func force_play_fill(stream : AudioStream = null):
	fill_playing = true
	track_1.stream = stream if stream else _current_trackset.get_positive_fill()
	
	play_song_from_beat(fill_overlap-get_beats_remaining(), Conductor.sec_per_beat)
	await track_1.finished
	fill_playing = false

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
	
	while int(Conductor.current_beat) % _current_trackset.beats_per_measure != 0:
		await Conductor.beat
	#force_play_fill(fail_riffs.pick_random() if fail_riffs.size() > 0 else null)
	
	Conductor.last_reported_beat = -1
	Conductor.set_song(_current_trackset.get_track_for_intensity(music_intensity), _current_trackset.bpm, _current_trackset.beats_per_measure)
	Conductor.play()
	current_intensity = music_intensity
	pass

func change_to_trackset(trackset_name : StringName):
	_current_trackset = tracksets[trackset_name]
