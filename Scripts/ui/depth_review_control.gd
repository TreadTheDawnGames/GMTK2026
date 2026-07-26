class_name DepthReviewControl
extends Control

## Pauses mining while the player reviews previously visited terrain.

signal review_scroll_requested(scroll_steps: float)
signal return_requested

@export_category("References")
@export var return_button: Button
@export var timing_window: TimingWindowTask
@export var mining_controller: MiningController

const RETURN_BUTTON_SLIDE_PIXELS: float = 12.0
const RETURN_BUTTON_FADE_SECONDS: float = 0.18

var _is_review_active: bool = false
var _return_button_base_position: Vector2 = Vector2.ZERO
var _has_return_button_base_position: bool = false
var _return_button_tween: Tween = null


## Connects the return button while leaving wheel input available.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	return_button.hide()
	return_button.modulate.a = 0.0
	if not return_button.pressed.is_connected(
		_on_return_button_pressed
	):
		return_button.pressed.connect(_on_return_button_pressed)


## Converts mouse-wheel movement into fractional camera review steps.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	var direction := 0.0
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		direction = -1.0
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		direction = 1.0
	else:
		return

	if (
		not _is_review_active
		and (
			direction > 0
			or not mining_controller.can_start_view_review()
			or not timing_window.visible
			or timing_window.process_mode
				== Node.PROCESS_MODE_DISABLED
		)
	):
		return
	var scroll_factor := absf(mouse_event.factor)
	if is_zero_approx(scroll_factor):
		scroll_factor = 1.0
	review_scroll_requested.emit(direction * scroll_factor)
	get_viewport().set_input_as_handled()


## Hides and pauses mining as soon as the camera detaches.
func _on_review_started() -> void:
	_is_review_active = true
	mining_controller.set_swing_queue_paused(true)
	timing_window.process_mode = Node.PROCESS_MODE_DISABLED
	timing_window.hide()
	return_button.disabled = false
	_fade_return_button_in()


## Restores mining after the returning camera reaches the player.
func _on_miner_view_reached() -> void:
	_is_review_active = false
	_fade_return_button_out()
	return_button.disabled = false
	mining_controller.set_swing_queue_paused(false)
	timing_window.process_mode = Node.PROCESS_MODE_INHERIT
	timing_window.show()


## Requests the accelerated return and prevents repeated clicks.
func _on_return_button_pressed() -> void:
	if not _is_review_active or return_button.disabled:
		return
	return_button.disabled = true
	return_requested.emit()


## Slides and fades the button in so it reads as part of the HUD.
func _fade_return_button_in() -> void:
	_cache_return_button_base_position()
	_restart_return_button_tween()
	return_button.show()
	return_button.position = _return_button_base_position + Vector2(
		0.0, RETURN_BUTTON_SLIDE_PIXELS
	)
	_return_button_tween.set_parallel(true)
	_return_button_tween.tween_property(
		return_button, "modulate:a", 1.0, RETURN_BUTTON_FADE_SECONDS
	)
	_return_button_tween.tween_property(
		return_button,
		"position",
		_return_button_base_position,
		RETURN_BUTTON_FADE_SECONDS
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Fades the button back out and hides it once it is invisible.
func _fade_return_button_out() -> void:
	if not return_button.visible:
		return
	_restart_return_button_tween()
	_return_button_tween.tween_property(
		return_button, "modulate:a", 0.0, RETURN_BUTTON_FADE_SECONDS
	)
	_return_button_tween.tween_callback(return_button.hide)


## Records the authored layout position before any animation offset.
func _cache_return_button_base_position() -> void:
	if _has_return_button_base_position:
		return
	_return_button_base_position = return_button.position
	_has_return_button_base_position = true


## Replaces any in-flight animation so states never fight each other.
func _restart_return_button_tween() -> void:
	if _return_button_tween != null and _return_button_tween.is_valid():
		_return_button_tween.kill()
	_return_button_tween = create_tween()
