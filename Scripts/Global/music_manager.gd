extends Node

@export var tracks : Array[AudioStream] = []
@export var fills : Array[AudioStream] = []

@onready var track_1: AudioStreamPlayer = %Track1
@onready var track_2: AudioStreamPlayer = %Track2
@onready var track_3: AudioStreamPlayer = %Track3

func _ready():
	Conductor.set_song(tracks[0], 120, 4)
	Conductor.play()
	Conductor.beat.connect(func(a): print(get_beats_remaining()))
	print(get_total_beats())
	
func get_total_beats() -> float:
	var beat_count = Conductor.stream.get_length() / Conductor.sec_per_beat
	return beat_count

func get_beats_remaining() -> float:
	return get_total_beats() - Conductor.current_beat

func _process(delta:float)->void:
	pass
