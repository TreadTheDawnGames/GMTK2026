class_name CreditsOverlay
extends Node2D

## How it works:
## - CreditEntry resources place authored inscriptions from depth 15,000-15,200.
## - View updates keep the inscription layer registered with terrain cells.
## - Foreground dirt draws above the text, so mining naturally reveals it.
## - Deeper terrain draws below the text, preserving its carved-in-ground look.
## - Depth callbacks emit start/completion without pausing or owning input.
## - Reset restores the bounded, one-shot presentation for a new run.
## - At most MAX_CREDIT_ENTRIES fixed scene slots exist; no per-hit state grows.
## - The invariant is that credits never gate or alter mining.

signal credits_started
signal credits_completed

const MAX_CREDIT_ENTRIES: int = 6

@export_category("Trigger")
@export_range(0, 100_000, 100) var trigger_depth: int = 15_000
@export_range(0, 100_000, 100) var completion_depth: int = 15_200

@export_category("Terrain")
@export var mining_config: MiningConfig

@export_category("Authored Credits")
@export var credit_entries: Array[CreditEntry] = []

@export_category("References")
@export var inscription_slots: Array[Node2D] = []

var has_completed: bool = false
var _has_started: bool = false


func _ready() -> void:
	if not _configuration_is_valid():
		push_error("CreditsOverlay configuration is incomplete.")
		hide()
		return
	_populate_inscriptions()
	_on_view_position_changed(Vector2(
		float(mining_config.terrain_width_cells) * 0.5,
		float(mining_config.initial_surface_row)
	))
	_on_run_reset()


## Starts and completes across skipped depths without requiring an exact hit.
func _on_depth_changed(depth: int) -> void:
	if depth >= trigger_depth:
		start_credits()
	if depth >= completion_depth:
		_complete_credits()


## Aligns authored terrain-cell positions with the manually streamed view.
func _on_view_position_changed(view_cell_position: Vector2) -> void:
	if mining_config == null:
		return
	var cell_size := float(mining_config.terrain_cell_world_size)
	position = Vector2(
		mining_config.terrain_screen_center_x
			- view_cell_position.x * cell_size,
		mining_config.mining_face_screen_y
			- view_cell_position.y * cell_size
	)


## Begins the passive one-shot presentation.
func start_credits() -> bool:
	if _has_started or has_completed or not _configuration_is_valid():
		return false
	_has_started = true
	show()
	credits_started.emit()
	return true


## Clears completion and presentation so a new run may earn credits again.
func _on_run_reset() -> void:
	_has_started = false
	has_completed = false
	hide()


## Retains the former query contract for integration callers.
func is_scrolling() -> bool:
	return _has_started and not has_completed


func _complete_credits() -> void:
	if not _has_started or has_completed:
		return
	has_completed = true
	hide()
	credits_completed.emit()


func _populate_inscriptions() -> void:
	for slot_index: int in range(inscription_slots.size()):
		var slot := inscription_slots[slot_index]
		slot.hide()
		if slot_index >= credit_entries.size():
			continue
		var entry := credit_entries[slot_index]
		if entry == null:
			continue
		var heading := slot.get_node_or_null("Heading") as Label
		var body := slot.get_node_or_null("Body") as Label
		if heading == null or body == null:
			push_error("Credit inscription slots require Heading and Body labels.")
			continue
		heading.text = entry.heading
		body.text = entry.body
		var cell_size := float(mining_config.terrain_cell_world_size)
		slot.position = Vector2(
			float(mining_config.terrain_width_cells) * cell_size * 0.5,
			float(
				mining_config.initial_surface_row
				+ trigger_depth
				+ entry.depth_offset
			) * cell_size
		)
		slot.show()


func _configuration_is_valid() -> bool:
	if mining_config == null:
		return false
	if completion_depth <= trigger_depth:
		push_error("Credits completion depth must be below its trigger depth.")
		return false
	if inscription_slots.size() != MAX_CREDIT_ENTRIES:
		push_error("CreditsOverlay requires exactly %d fixed slots." % MAX_CREDIT_ENTRIES)
		return false
	if credit_entries.size() > MAX_CREDIT_ENTRIES:
		push_error("CreditsOverlay supports at most %d entries." % MAX_CREDIT_ENTRIES)
		return false
	var credit_span := completion_depth - trigger_depth
	for entry: CreditEntry in credit_entries:
		if (
			entry != null
			and (
				entry.depth_offset < 0
				or entry.depth_offset > credit_span
			)
		):
			push_error("Credit entries must remain inside the credits depth span.")
			return false
	return true
