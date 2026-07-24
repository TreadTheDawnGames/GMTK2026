extends TimingTarget


func hit(_timing_window : SliderTimingWindow = null):
	super.hit(_timing_window)
	_timing_window.direction *= -1
	_timing_window.bounce_sound.play()
