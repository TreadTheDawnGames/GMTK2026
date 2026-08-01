#File: animated_timing_window.gd
#Date: 2026-08-01
#Author: Caspian Tyler

extends TimingWindow
class_name AnimatedTimingWindow

@export var slider : Panel

## Plays a flashing animation on the slider that happens a number of times equal to [repetitions]. Should be in AnimatedTimingWindow.
func play_animation(color : Color, repetitions : int = 1,  duration : float = 0.1):
	var tween: Tween = create_tween()
	for _repeat_index in range(repetitions):
		tween.tween_property(slider, "modulate", color, duration)
		tween.tween_property(slider, "modulate", Color.WHITE, duration)
	await tween.finished

	pass

func pause(animate : bool):
	super.pause(animate)
	if not animate:
		return
	await play_animation(animation_color, animation_repeats, 0.1)
