class_name CreditsOverlay
extends CanvasLayer

## How it works:
## - Depth updates start one passive credits scroll at or beyond the trigger.
## - The overlay ignores input and never pauses or gates mining.
## - Authored text scrolls through the clipped region at a tunable speed.
## - Completion is recorded and emitted once for a coordinator to consume.
## - Run reset hides the overlay and restores its one-shot state.
## - The invariant is that credits can never take gameplay or input ownership.

signal credits_started
signal credits_completed

@export_category("Trigger")
@export_range(0, 100_000, 100) var trigger_depth: int = 15_000

@export_category("Scroll")
@export_range(1.0, 500.0, 1.0) var scroll_speed_pixels_per_second: float = 48.0
@export_range(0.0, 300.0, 1.0) var start_padding_pixels: float = 36.0
@export_range(-300.0, 300.0, 1.0) var completion_y: float = 12.0

@export_category("References")
@export var overlay_root: Control
@export var scroll_region: Control
@export var credits_label: RichTextLabel

var has_completed: bool = false
var _is_scrolling: bool = false


## Starts hidden without subscribing to any external gameplay authority.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _references_are_valid():
		push_error("CreditsOverlay references are incomplete.")
		set_process(false)
		return
	_reset_presentation()


## Advances only authored presentation; gameplay remains independently active.
func _process(delta: float) -> void:
	if not _is_scrolling:
		return
	credits_label.position.y -= (
		maxf(scroll_speed_pixels_per_second, 1.0)
		* maxf(delta, 0.0)
	)
	if (
		credits_label.position.y + _get_credits_height()
		<= completion_y
	):
		_complete_credits()


## Starts credits after any depth update that reaches or skips past the trigger.
func _on_depth_changed(depth: int) -> void:
	if depth >= trigger_depth:
		start_credits()


## Begins the one-shot scroll and returns whether this call started it.
func start_credits() -> bool:
	if (
		_is_scrolling
		or has_completed
		or not _references_are_valid()
	):
		return false
	_reset_label_position()
	_is_scrolling = true
	overlay_root.show()
	set_process(true)
	credits_started.emit()
	return true


## Clears completion and presentation so a new run may earn credits again.
func _on_run_reset() -> void:
	_reset_presentation()


## Reports whether the authored credits are currently moving.
func is_scrolling() -> bool:
	return _is_scrolling


func _complete_credits() -> void:
	if not _is_scrolling:
		return
	_is_scrolling = false
	has_completed = true
	set_process(false)
	overlay_root.hide()
	credits_completed.emit()


func _reset_presentation() -> void:
	_is_scrolling = false
	has_completed = false
	set_process(false)
	overlay_root.hide()
	_reset_label_position()


func _reset_label_position() -> void:
	var region_height := scroll_region.size.y
	if region_height <= 0.0:
		region_height = get_viewport().get_visible_rect().size.y
	credits_label.position.y = region_height + start_padding_pixels


func _get_credits_height() -> float:
	return maxf(
		credits_label.size.y,
		credits_label.get_content_height()
	)


func _references_are_valid() -> bool:
	return (
		is_instance_valid(overlay_root)
		and is_instance_valid(scroll_region)
		and is_instance_valid(credits_label)
	)
