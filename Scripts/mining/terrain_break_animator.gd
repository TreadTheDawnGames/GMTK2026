class_name TerrainBreakAnimator
extends Node

## Reveals mined cells from the impact point downward over several frames.

## Reports cells that finished fading and now count as physical air.
signal cells_revealed(cells: Array[Vector2i])
## Reports that every break reserved by the current hit has finished.
signal all_breaks_finished

class BreakSequence:
	## Tracks the ordered pixels waiting to begin their fade.
	var cells: Array[Vector2i]
	var next_cell_index: int = 0
	var cell_budget: float = 0.0
	var cells_per_second: float = 0.0


class FadingCell:
	## Tracks one translucent pixel until it becomes physical air.
	var cell: Vector2i
	var elapsed_seconds: float = 0.0


@export_category("References")
@export var terrain_manager: TerrainManager

@export_category("Cadence")
## Sets the slowest rate at which new pixel fades may begin.
@export_range(30.0, 2_000.0, 10.0) var minimum_cells_per_second: float = 300.0
## Raises the start rate toward this duration while frame budgets remain in force.
@export_range(0.1, 2.0, 0.05) var target_sequence_duration_seconds: float = 0.75
## Limits new fades started in one desktop frame.
@export_range(1, 128, 1) var maximum_fades_started_per_frame: int = 24
## Applies a lower fade-start limit in browser exports.
@export_range(1, 64, 1) var web_maximum_fades_started_per_frame: int = 12
## Keeps each pixel translucent this long before it becomes physical air.
@export_range(20, 500, 5) var pixel_fade_milliseconds: int = 80

var _active_sequences: Array[BreakSequence] = []
var _fading_cells: Array[FadingCell] = []


## Sleeps until the first terrain break sequence arrives.
func _ready() -> void:
	set_process(false)


## Orders one hit from its contact row downward and begins revealing it.
func play_break_sequence(
	cells: Array[Vector2i],
	impact_cell: Vector2i
) -> void:
	if cells.is_empty():
		return
	var sequence := BreakSequence.new()
	sequence.cells = cells.duplicate()
	# Sweep each row outward from the pickaxe tip before moving downward.
	sequence.cells.sort_custom(
		func(first: Vector2i, second: Vector2i) -> bool:
			if first.y != second.y:
				return first.y < second.y
			return (
				absi(first.x - impact_cell.x)
				< absi(second.x - impact_cell.x)
			)
	)
	sequence.cells_per_second = maxf(
		minimum_cells_per_second,
		float(sequence.cells.size()) / target_sequence_duration_seconds
	)
	_active_sequences.append(sequence)
	set_process(true)


## Reveals one ordered hit at a time with one terrain refresh per frame.
func _process(delta: float) -> void:
	if _active_sequences.is_empty():
		set_process(false)
		return
	var sequence := _active_sequences[0]
	sequence.cell_budget += sequence.cells_per_second * delta
	var frame_budget := maximum_fades_started_per_frame
	if OS.has_feature("web"):
		frame_budget = mini(
			frame_budget,
			web_maximum_fades_started_per_frame
		)
	var reveal_batch: Array[Vector2i] = []
	var cells_to_start := mini(
		mini(floori(sequence.cell_budget), frame_budget),
		sequence.cells.size() - sequence.next_cell_index
	)
	for _cell_index in range(cells_to_start):
		var fading_cell := FadingCell.new()
		fading_cell.cell = sequence.cells[sequence.next_cell_index]
		_fading_cells.append(fading_cell)
		sequence.next_cell_index += 1
		sequence.cell_budget -= 1.0

	var fade_duration := float(pixel_fade_milliseconds) / 1_000.0
	var cell_alphas: Dictionary = {}
	for fade_index in range(_fading_cells.size() - 1, -1, -1):
		var fading_cell := _fading_cells[fade_index]
		fading_cell.elapsed_seconds += delta
		var alpha := clampf(
			1.0 - fading_cell.elapsed_seconds / fade_duration,
			0.0,
			1.0
		)
		cell_alphas[fading_cell.cell] = alpha
		if alpha <= 0.0:
			reveal_batch.append(fading_cell.cell)
			_fading_cells.remove_at(fade_index)
	if not cell_alphas.is_empty():
		terrain_manager.apply_destroyed_cell_fades(cell_alphas)
	if not reveal_batch.is_empty():
		cells_revealed.emit(reveal_batch)
	if (
		sequence.next_cell_index >= sequence.cells.size()
		and _fading_cells.is_empty()
	):
		_active_sequences.pop_front()
	if _active_sequences.is_empty():
		set_process(false)
		all_breaks_finished.emit()
