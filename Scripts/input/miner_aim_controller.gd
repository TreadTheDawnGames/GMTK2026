class_name MinerAimController
extends Node

## Converts mouse or A/D input into the side affected by the next mining hit.

@export_category("References")
@export var miner_rig: MinerRig
@export var mining_controller: MiningController
@export var timing_window: TimingWindowTask

@export_category("Mouse Aim")
@export_range(0.0, 200.0, 1.0) var center_dead_zone_px: float = 40.0

var _keyboard_aim_enabled: bool = false
var _choice_made: bool = false
var _mouse_aim_direction: int = 0
var _active_aim_direction: int = 0


## Keeps held keyboard aim current before a timing result is resolved.
func _process(_delta: float) -> void:
	if not _can_accept_aim():
		return
	_apply_active_aim()


## Updates A/D aim immediately when either key changes.
func _input(event: InputEvent) -> void:
	if (
		not _keyboard_aim_enabled
		or not event is InputEventKey
	):
		return
	var key_event := event as InputEventKey
	if (
		key_event.physical_keycode != KEY_A
		and key_event.physical_keycode != KEY_D
	):
		return
	_apply_active_aim()


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
	_mouse_aim_direction = (
		0
		if absf(horizontal_offset) <= center_dead_zone_px
		else signi(roundi(horizontal_offset))
	)
	_apply_active_aim()
	get_viewport().set_input_as_handled()


## Applies the aiming choice made at startup.
func set_keyboard_aim_enabled(keyboard_aim_enabled: bool) -> void:
	_keyboard_aim_enabled = keyboard_aim_enabled
	_choice_made = true
	_apply_active_aim()


## Sends current aim to mining and mirrors the visible rig when needed.
func _apply_active_aim() -> void:
	var keyboard_direction := 0
	if _keyboard_aim_enabled:
		keyboard_direction = roundi(Input.get_axis(
			&"aim_left",
			&"aim_right"
		))
	var next_direction := (
		keyboard_direction
		if keyboard_direction != 0
		else _mouse_aim_direction
	)
	if next_direction == _active_aim_direction:
		return
	_active_aim_direction = next_direction
	mining_controller.set_aim_direction(_active_aim_direction)
	if _active_aim_direction != 0:
		miner_rig.set_facing_direction(_active_aim_direction)


## Returns whether gameplay currently accepts aiming input.
func _can_accept_aim() -> bool:
	return (
		_choice_made
		and timing_window.process_mode != Node.PROCESS_MODE_DISABLED
	)
