class_name CreditsOverlay
extends Node2D

## How it works:
## - CreditEntry resources place authored inscriptions from depth 15,000-15,400.
## - View updates keep the inscription layer registered with terrain cells.
## - Foreground dirt draws above the text, so mining naturally reveals it.
## - Deeper terrain draws below the text, preserving its carved-in-ground look.
## - A long approach ramp widens and centers the shaft before the first name.
## - The strike that reaches a credit's depth writes that name on where it hit.
## - Depth callbacks emit start/completion without pausing or owning input.
## - Reset restores the bounded, one-shot presentation for a new run.
## - One authored slot is cloned per entry at boot; no per-hit state grows.
## The invariant is that credits never gate mining: the band changes how wide a
## swing cuts, never whether the player may swing or how much depth one earns.

signal credits_started
signal credits_completed
## Carries the widened, straightened descent to the mining controller. A zero
## half-width with a negative span means ordinary mining resumes.
signal inscription_dig_band_changed(
	minimum_half_width_cells: int,
	maximum_snake_half_span_cells: int
)

## One inscription part-way through writing itself on. Bounded by the authored
## credit count, because each entry is earned exactly once per run.
class InscriptionWriteOn:
	var slot_index: int = -1
	var elapsed_seconds: float = 0.0


# Any span at or above this leaves the configured snake untouched, because the
# controller clamps the override against its own authored value. Ramping down
# from here avoids a sentinel and keeps the path's turn span continuous.
const UNCONSTRAINED_SNAKE_HALF_SPAN_CELLS: int = 64

@export_category("Trigger")
@export_range(0, 100_000, 100) var trigger_depth: int = 15_000
@export_range(0, 100_000, 100) var completion_depth: int = 15_400

@export_category("Terrain")
@export var mining_config: MiningConfig

@export_category("Inscription Dig Band")
## Half-width of the shaft while a name is passing. An inscription is only
## readable if the ground in front of it is gone, so this is what decides how
## large the lettering may be: the readable span is twice this in cells.
## Forty cells clears 648 px, which is what "A GMTK GAME JAM 2026 GAME" needs
## at the authored 34 px body size. Lowering it means lowering the font sizes
## in credits_overlay.tscn to match, or the ends of the longest lines stay
## buried in rock. The widest opening a stacked pickaxe already cuts is 89
## cells, so this stays inside terrain work the depth-combo profile covers.
@export_range(0, 64, 1) var inscription_half_width_cells: int = 40
## Turn span the snake is held to while the band is open. Zero sinks one
## straight shaft so a centered name is fully uncovered rather than clipped by
## whichever side the path happened to wander to.
@export_range(0, 24, 1) var inscription_snake_half_span_cells: int = 0
## Rows spent opening the shaft out on the approach to the first name. Long
## enough that the player arrives at the credits already swinging wide, having
## felt the ground give way, rather than meeting a seam where the tunnel
## suddenly triples. At 200 it begins at 14,800: roughly seventeen swings of
## widening, which is a build without being a stretch of empty shaft.
@export_range(1, 2_000, 1) var dig_band_ramp_in_rows: int = 200
## Rows spent closing the shaft after the last name. Short on purpose: the
## credits ending is meant to read as the ground shutting again.
@export_range(1, 2_000, 1) var dig_band_ramp_out_rows: int = 24

@export_category("Inscription Reveal")
## Seconds an inscription takes to write itself on after the strike that
## uncovers it. One swing clears a dozen rows and the miner falls through them,
## so a slow write finishes above a player who has already dropped past it.
@export_range(0.05, 2.0, 0.05) var inscription_write_on_seconds: float = 0.35

@export_category("Authored Credits")
@export var credit_entries: Array[CreditEntry] = []

@export_category("References")
## One authored inscription, hidden, cloned once per credit at boot. Styling it
## styles every credit; adding a credit costs a resource and nothing else.
@export var inscription_template: Node2D

var has_completed: bool = false
var _has_started: bool = false
var _emitted_half_width_cells: int = 0
var _emitted_snake_half_span_cells: int = -1
# Inscriptions still writing on. At most one per authored credit per run.
var _write_ons: Array[InscriptionWriteOn] = []
# Entries are drawn in authored order. This is the next one still waiting for
# a strike to reach its depth, so a name is written exactly once per run.
var _next_entry_index: int = 0
# One cloned inscription per authored credit, built once at boot.
var _slots: Array[Node2D] = []
# Depth reached by the run. A strike carries a screen point, not a depth, so
# the section test and the entry that a hit has earned both read this.
var _latest_depth: int = 0


func _ready() -> void:
	set_process(false)
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
	_latest_depth = depth
	_update_dig_band(depth)
	if depth >= trigger_depth:
		start_credits()
	if depth >= completion_depth:
		_complete_credits()


## Publishes the shaft this depth should be cut at. One earned swing clears
## many rows, so the band is resolved from the depth reached rather than
## stepped, and it is emitted only when a whole cell of it actually moved.
func _update_dig_band(depth: int) -> void:
	var band_fraction := _get_dig_band_fraction(depth)
	var half_width_cells := roundi(
		float(inscription_half_width_cells) * band_fraction
	)
	var snake_half_span_cells := -1
	if band_fraction > 0.0:
		snake_half_span_cells = roundi(
			lerpf(
				float(UNCONSTRAINED_SNAKE_HALF_SPAN_CELLS),
				float(inscription_snake_half_span_cells),
				band_fraction
			)
		)
	if (
		half_width_cells == _emitted_half_width_cells
		and snake_half_span_cells == _emitted_snake_half_span_cells
	):
		return
	_emitted_half_width_cells = half_width_cells
	_emitted_snake_half_span_cells = snake_half_span_cells
	inscription_dig_band_changed.emit(
		half_width_cells,
		snake_half_span_cells
	)


## Returns how far open the shaft is at one depth, from 0 in ordinary ground to
## 1 across the stretch the names occupy. The opening ramp finishes on
## trigger_depth because the first inscription sits exactly there.
func _get_dig_band_fraction(depth: int) -> float:
	if depth <= trigger_depth:
		var approach_rows := float(maxi(dig_band_ramp_in_rows, 1))
		return clampf(
			(
				(float(depth) - (float(trigger_depth) - approach_rows))
				/ approach_rows
			),
			0.0,
			1.0
		)
	if depth >= completion_depth:
		return 0.0
	var closing_rows := float(maxi(dig_band_ramp_out_rows, 1))
	return clampf(
		(float(completion_depth) - float(depth)) / closing_rows,
		0.0,
		1.0
	)


## Writes on the next authored credit when a strike inside the section reaches
## its depth, laying it on the row that strike opened. Shares the impact
## presentation signature so the wiring routes it like the spark and the dust.
## Outside the section, and on any strike that has not earned a name, this does
## nothing at all.
func play_at_impact(
	impact_screen_position: Vector2,
	cells_removed: int,
	_combo_strength: float = 1.0,
	_debris_multiplier: float = 1.0,
	_swing_side: int = 1
) -> void:
	if cells_removed <= 0 or mining_config == null:
		return
	if _get_dig_band_fraction(_latest_depth) <= 0.0:
		return
	var slot_index := _take_slot_due_at(
		_latest_depth,
		to_local(impact_screen_position)
	)
	if slot_index < 0:
		return
	var write_on := InscriptionWriteOn.new()
	write_on.slot_index = slot_index
	_write_ons.append(write_on)
	set_process(true)


## Returns the slot of the entry this depth has earned, already placed and
## cleared for writing, or -1 when no name is due. Authored depth still sets
## the order and the pacing; the strike only decides the moment.
func _take_slot_due_at(depth: int, origin: Vector2) -> int:
	if _next_entry_index >= credit_entries.size():
		return -1
	var entry := credit_entries[_next_entry_index]
	if entry == null:
		_next_entry_index += 1
		return -1
	if depth < trigger_depth + entry.depth_offset:
		return -1
	var slot_index := _next_entry_index
	_next_entry_index += 1
	if slot_index >= _slots.size():
		return -1
	var slot := _slots[slot_index]
	# The name is laid on the row the strike opened rather than its authored
	# row, so it always lands in ground the player has actually cleared.
	slot.position = Vector2(
		float(mining_config.terrain_width_cells)
		* float(mining_config.terrain_cell_world_size)
		* 0.5,
		origin.y
	)
	_set_slot_visible_ratio(slot, 0.0)
	slot.show()
	return slot_index


## Advances every inscription still writing itself on.
func _process(delta: float) -> void:
	for write_on_index in range(_write_ons.size() - 1, -1, -1):
		var write_on := _write_ons[write_on_index]
		write_on.elapsed_seconds += delta
		var write_ratio := clampf(
			(
				write_on.elapsed_seconds
				/ maxf(inscription_write_on_seconds, 0.01)
			),
			0.0,
			1.0
		)
		_set_slot_visible_ratio(_slots[write_on.slot_index], write_ratio)
		# A finished name is terrain from here: it stays on the row it was
		# written on and leaves by scrolling away with the ground.
		if write_ratio >= 1.0:
			_write_ons.remove_at(write_on_index)
	if _write_ons.is_empty():
		set_process(false)


## Writes a slot's two labels on together, so a heading and the names under it
## arrive as one inscription rather than racing each other.
func _set_slot_visible_ratio(slot: Node2D, ratio: float) -> void:
	var heading := slot.get_node_or_null("Heading") as Label
	var body := slot.get_node_or_null("Body") as Label
	if heading != null:
		heading.visible_ratio = ratio
	if body != null:
		body.visible_ratio = ratio


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
## The shaft is handed back unconditionally: a run reset from inside the band
## would otherwise leave the next run's surface digging at credits width.
func _on_run_reset() -> void:
	_has_started = false
	has_completed = false
	hide()
	_next_entry_index = 0
	_latest_depth = 0
	_write_ons.clear()
	set_process(false)
	for slot in _slots:
		slot.hide()
		_set_slot_visible_ratio(slot, 0.0)
	_emitted_half_width_cells = 0
	_emitted_snake_half_span_cells = -1
	inscription_dig_band_changed.emit(0, -1)


## Retains the former query contract for integration callers.
func is_scrolling() -> bool:
	return _has_started and not has_completed


## Completion is a story event, not a curtain. The last inscription is written
## by whichever strike reached it, which can be only a few rows above this
## depth, so hiding here would snuff "KEEP DIGGING." while it was still being
## read. The names are terrain: they leave by scrolling away, and the run reset
## is what clears them.
func _complete_credits() -> void:
	if not _has_started or has_completed:
		return
	has_completed = true
	credits_completed.emit()


## Clones the authored template once per credit. Adding somebody to the credits
## is adding a CreditEntry resource: there is no slot to add, no ceiling to
## raise, and no chance of one inscription being styled unlike its neighbours.
func _populate_inscriptions() -> void:
	_slots.clear()
	for entry: CreditEntry in credit_entries:
		if entry == null:
			continue
		var slot := inscription_template.duplicate() as Node2D
		var heading := slot.get_node_or_null("Heading") as Label
		var body := slot.get_node_or_null("Body") as Label
		if heading == null or body == null:
			push_error(
				"The credit inscription template needs Heading and Body labels."
			)
			slot.queue_free()
			return
		heading.text = entry.heading
		body.text = entry.body
		# Placement waits for the strike that earns this entry. An authored
		# depth still decides which strike that is, but the name is laid on
		# the row the player actually opened rather than on its authored row.
		slot.hide()
		_set_slot_visible_ratio(slot, 0.0)
		add_child(slot)
		_slots.append(slot)


## Measures how many terrain rows one inscription covers, from the top of its
## heading to the bottom of its names, so the spacing rule below is read off
## the scene rather than guessed at and left to rot when the type changes.
func _measure_entry_height_rows() -> int:
	var heading := inscription_template.get_node_or_null("Heading") as Control
	var body := inscription_template.get_node_or_null("Body") as Control
	if heading == null or body == null:
		return 0
	var height_px := body.offset_bottom - heading.offset_top
	return ceili(
		height_px / float(mining_config.terrain_cell_world_size)
	)


func _configuration_is_valid() -> bool:
	if mining_config == null:
		return false
	if completion_depth <= trigger_depth:
		push_error("Credits completion depth must be below its trigger depth.")
		return false
	if inscription_template == null:
		push_error("CreditsOverlay requires an inscription template node.")
		return false
	return _credit_layout_is_valid()


## Checks the authored credits actually fit the section, and says what to change
## when they do not.
##
## There is no entry ceiling any more, so the real limit is room: a section
## 200 rows deep holds only so many inscriptions before they sit on top of one
## another. Reporting the span the authored list needs turns "the credits are
## overlapping" into a number to widen the section by.
func _credit_layout_is_valid() -> bool:
	var credit_span := completion_depth - trigger_depth
	var minimum_spacing := _measure_entry_height_rows()
	var previous_offset := -minimum_spacing
	var previous_heading := ""
	for entry: CreditEntry in credit_entries:
		if entry == null:
			continue
		if entry.depth_offset < 0 or entry.depth_offset > credit_span:
			push_error(
				(
					"Credit \"%s\" sits at +%d, outside the %d-row credits "
					+ "section. Move it, or set completion_depth to at least "
					+ "%d."
				)
				% [
					entry.heading,
					entry.depth_offset,
					credit_span,
					trigger_depth + entry.depth_offset,
				]
			)
			return false
		if entry.depth_offset - previous_offset < minimum_spacing:
			push_error(
				(
					"Credit \"%s\" at +%d is only %d rows below \"%s\", and "
					+ "one inscription is %d rows tall, so they would overlap. "
					+ "Space the authored credits at least %d rows apart."
				)
				% [
					entry.heading,
					entry.depth_offset,
					entry.depth_offset - previous_offset,
					previous_heading,
					minimum_spacing,
					minimum_spacing,
				]
			)
			return false
		previous_offset = entry.depth_offset
		previous_heading = entry.heading
	return true
