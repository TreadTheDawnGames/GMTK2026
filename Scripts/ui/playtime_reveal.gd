class_name PlaytimeReveal
extends Label

## Reveals elapsed play time gradually during longer runs.

@export_category("Timing")
@export_range(0.0, 600.0, 1.0) var earliest_reveal_seconds: float = 240.0
@export_range(0.0, 600.0, 1.0) var latest_reveal_seconds: float = 300.0
@export_range(1.0, 1_800.0, 1.0) var fully_visible_seconds: float = 600.0

@export_category("Appearance")
@export var obscured_color: Color = Color("633c31")
@export var visible_color: Color = Color("f0f0f0")
@export_range(0.0, 1.0, 0.05) var starting_opacity: float = 0.15

var _reveal_start_seconds: float = 0.0
var _random := RandomNumberGenerator.new()


## Chooses the reveal time and waits for canonical run-time updates.
func _ready() -> void:
	_random.randomize()
	_choose_reveal_start()
	_reset_presentation()


## Reveals the shared controllable play time gradually by ten minutes.
func _on_run_time_changed(elapsed_seconds: int) -> void:
	var safe_elapsed_seconds := maxi(elapsed_seconds, 0)
	if safe_elapsed_seconds == 0:
		_choose_reveal_start()
		_reset_presentation()
		return
	if float(safe_elapsed_seconds) < _reveal_start_seconds:
		return

	if not visible:
		show()
	var elapsed_minutes := floori(
		float(safe_elapsed_seconds) / 60.0
	)
	var elapsed_remaining_seconds := safe_elapsed_seconds % 60
	text = "TIME  %02d:%02d" % [
		elapsed_minutes,
		elapsed_remaining_seconds,
	]

	var reveal_duration := maxf(
		fully_visible_seconds - _reveal_start_seconds,
		0.001
	)
	var reveal_weight := clampf(
		(float(safe_elapsed_seconds) - _reveal_start_seconds)
		/ reveal_duration,
		0.0,
		1.0
	)
	var reveal_color := obscured_color.lerp(
		visible_color,
		reveal_weight
	)
	reveal_color.a = lerpf(
		starting_opacity,
		visible_color.a,
		reveal_weight
	)
	self_modulate = reveal_color


func _choose_reveal_start() -> void:
	var safe_earliest := minf(
		earliest_reveal_seconds,
		latest_reveal_seconds
	)
	var safe_latest := maxf(
		earliest_reveal_seconds,
		latest_reveal_seconds
	)
	_reveal_start_seconds = _random.randf_range(
		safe_earliest,
		safe_latest
	)


func _reset_presentation() -> void:
	text = "TIME  00:00"
	self_modulate = Color(
		obscured_color.r,
		obscured_color.g,
		obscured_color.b,
		starting_opacity
	)
	hide()
