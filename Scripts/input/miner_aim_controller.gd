class_name MinerAimController
extends Node

## Uses a right click to select the side affected by the next mining hit.

@export_category("References")
@export var miner_rig: MinerRig
@export var mining_controller: MiningController
@export var timing_window: TimingWindowTask

@export_category("Mouse Aim")
@export_range(0.0, 200.0, 1.0) var center_dead_zone_px: float = 40.0

var _active_aim_direction: int = 0


## Uses right click to choose left, right, or straight-down mining.
func _unhandled_input(event: InputEvent) -> void:
	if (
		not _can_accept_aim()
		or not event is InputEventMouseButton
	):
		return
	var mouse_event := event as InputEventMouseButton
	if (
		mouse_event.button_index != MOUSE_BUTTON_RIGHT
		or not mouse_event.pressed
	):
		return
	var horizontal_offset := (
		mouse_event.position.x - miner_rig.global_position.x
	)
	var next_direction := (
		0
		if absf(horizontal_offset) <= center_dead_zone_px
		else signi(roundi(horizontal_offset))
	)
	if next_direction == _active_aim_direction:
		get_viewport().set_input_as_handled()
		return
	_active_aim_direction = next_direction
	mining_controller.set_aim_direction(_active_aim_direction)
	if _active_aim_direction != 0:
		miner_rig.set_facing_direction(_active_aim_direction)
	get_viewport().set_input_as_handled()


## Returns whether gameplay currently accepts aiming input.
func _can_accept_aim() -> bool:
	return timing_window.process_mode != Node.PROCESS_MODE_DISABLED
