#Trackset.gd
#2026-08-05
#Caspian Tyler

extends Resource
class_name Trackset

## The sections of songs split into intensities. Each trackset should have the same number of intensities, though it's not required.
@export var tracks : Array[Intensity]
## Samples to play to overlap the transition from one track to the next when the intenisty is the same or raising.
@export var fills : Array[AudioStream]
## Samples to play to overlap the transition from one track to the next when the intensity is lowering.
@export var fail_fills : Array[AudioStream]
## Self explanitory
@export var bpm : int = 120
## Self explanitory
@export var beats_per_measure : int = 4
## How many beats should remain in the current track when playing a fill.
@export var fill_offset : int = 3

## Returns an AudioStream at the provided [intensity]
func get_track_for_intensity(intensity : int) -> AudioStream:
	return tracks[intensity].pick_random()

## Returns an AudioStream positive fill
func get_positive_fill() -> AudioStream:
	return fills.pick_random()

## Returns an AudioStream negative fill
func get_negative_fill() -> AudioStream:
	return fail_fills.pick_random()

## Returns the first AudioStream of the first intensity
func get_first_track() -> AudioStream:
	return tracks[0].first()

## Returns tracks.size()
func get_size() -> int:
	return tracks.size()
