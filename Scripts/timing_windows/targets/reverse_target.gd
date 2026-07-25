extends TimingTarget

@onready var _audio_handler: PlayerAudioHandler = (
	PlayerAudioHandler.get_global(self)
)

func hit(_timing_window: SliderTimingWindow = null) -> void:
	super.hit(_timing_window)
	# Generic target callers may not own a timing window. The target is still
	# collected in that case, but there is no slider direction to reverse.
	if _timing_window == null:
		return
	_timing_window.direction *= -1
	_audio_handler.play_sound(AudioLibrary.BOUNCE)
