class_name DepthReviewControl
extends Control

## Pauses mining while the player reviews previously visited terrain.

signal review_scroll_requested(direction: int)
signal return_requested

@export_category("References")
@export var return_button: Button
@export var timing_window: TimingWindowTask
@export var mining_controller: MiningController

var _is_review_active: bool = false


## Connects the return button while leaving wheel input available.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	return_button.hide()
	if not return_button.pressed.is_connected(
		_on_return_button_pressed
	):
		return_button.pressed.connect(_on_return_button_pressed)


## Converts mouse-wheel movement into camera review requests.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	var direction := 0
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		direction = -1
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		direction = 1
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
	review_scroll_requested.emit(direction)
	get_viewport().set_input_as_handled()


## Hides and pauses mining as soon as the camera detaches.
func _on_review_started() -> void:
	_is_review_active = true
	mining_controller.set_swing_queue_paused(true)
	timing_window.process_mode = Node.PROCESS_MODE_DISABLED
	timing_window.hide()
	return_button.disabled = false
	return_button.show()


## Restores mining after the returning camera reaches the player.
func _on_miner_view_reached() -> void:
	_is_review_active = false
	return_button.hide()
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
