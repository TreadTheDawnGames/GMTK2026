@icon("res://addons/conductor/icons/AnimationPlayer.png")
class_name ConductedAnimationPlayer
extends AnimationPlayer

var start_beat:float 

func _ready() -> void:
	Conductor.update.connect(_update)

func _update(delta,_beat_pos,_measure_pos):
	if(is_playing()):
		seek((Conductor.current_beat-start_beat)*speed_scale,true)

func play_conducted(
	name: StringName = &"",
	custom_speed: float = speed_scale,
	custom_blend: float = -1.0,
	from_end: bool = false
) -> void:
	start_beat = Conductor.current_beat
	super.play(name, custom_blend, custom_speed, from_end)
