extends Resource
class_name Intensity 

@export var tracks : Array[AudioStream] = []

func pick_random() -> AudioStream:
	return tracks.pick_random()

func first() -> AudioStream:
	return tracks[0] if tracks.size() > 0 else null
