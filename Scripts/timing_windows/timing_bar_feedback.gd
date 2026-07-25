class_name TimingBarFeedback
extends Control

## How it works:
## - Draws hit and miss feedback over Caspian's timing bar without editing it.
##   Everything here is read-only: it reads the active bar's global rect and its
##   slider position and never writes a property back, so his layout, target
##   placement, and reset flow behave exactly as they did.
## - One press produces a short-lived mark record: an expanding ring plus a few
##   ink chevrons on a hit, or a single struck slash on a miss.
## - The whole overlay sleeps between presses, so a paused bar costs nothing.
## The invariant is that marks never outnumber maximum_active_marks, and that
## this node never mutates the timing bar.

class HitMark:
	var bar_local_position: Vector2
	var total_lifetime: float
	var remaining_lifetime: float
	var radius_px: float
	var color: Color
	var is_miss: bool
	var chevron_rotation: float
	var chevron_count: int


@export_category("References")
@export var timing_window: TimingWindowTask

@export_category("Hit")
@export var hit_color: Color = Color("ffe9a8")
## Escalates toward this as the combo approaches combo_heat_ceiling.
@export var hot_combo_color: Color = Color("ff9c41")
## Combo at which a hit mark is drawn at full heat and full size.
@export_range(1, 60, 1) var combo_heat_ceiling: int = 12
@export_range(0.05, 1.0, 0.01) var hit_lifetime: float = 0.26
## Ring radius for a first hit and for a hit at the heat ceiling.
@export_range(4.0, 200.0, 1.0) var minimum_ring_radius_px: float = 26.0
@export_range(4.0, 240.0, 1.0) var maximum_ring_radius_px: float = 74.0
@export_range(1.0, 24.0, 0.5) var ring_thickness_px: float = 5.0
## Ink strokes thrown out of the hit point alongside the ring.
@export_range(0, 10, 1) var minimum_chevron_count: int = 3
@export_range(0, 12, 1) var maximum_chevron_count: int = 7
@export_range(4.0, 80.0, 1.0) var chevron_length_px: float = 20.0
@export_range(1.0, 16.0, 0.5) var chevron_width_px: float = 5.0

@export_category("Miss")
@export var miss_color: Color = Color("d1483f")
@export_range(0.05, 1.5, 0.01) var miss_lifetime: float = 0.34

@export_category("Frame")
## How far the bar's drawn recoil outline kicks outward on a hit, and inward on
## a miss. The bar itself never moves; only this outline does.
@export_range(0.0, 40.0, 0.5) var frame_kick_px: float = 7.0
@export_range(1.0, 12.0, 0.5) var frame_thickness_px: float = 3.0

@export_category("Performance")
## Bounded per-press accumulation: a press at capacity retires the oldest mark
## first, so a fast streak never grows this array.
@export_range(1, 16, 1) var maximum_active_marks: int = 6

var _marks: Array[HitMark] = []
var _random := RandomNumberGenerator.new()


## Sleeps until MiningSceneWiring routes the first timing result here.
func _ready() -> void:
	_random.randomize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	if timing_window == null:
		push_error("TimingBarFeedback requires a TimingWindowTask.")


## Records one mark at the slider position the press was resolved on.
func _on_timing_pressed(
	success: bool,
	combo: int,
	_hit_direction: int
) -> void:
	var active_bar := _get_active_bar()
	if active_bar == null or not active_bar.is_visible_in_tree():
		return
	var bar_rect := active_bar.get_global_rect()
	if not bar_rect.has_area():
		return

	while _marks.size() >= maxi(maximum_active_marks, 1):
		_marks.remove_at(0)

	# combo climbs past the ceiling on a long streak; the visual stops growing
	# there so a huge combo never throws a ring off the top of the screen.
	var heat := clampf(
		float(maxi(combo, 0)) / float(maxi(combo_heat_ceiling, 1)),
		0.0,
		1.0
	)
	var mark := HitMark.new()
	mark.is_miss = not success
	mark.bar_local_position = Vector2(
		bar_rect.position.x + active_bar.slider_position,
		bar_rect.get_center().y
	) - get_global_rect().position
	mark.total_lifetime = miss_lifetime if mark.is_miss else hit_lifetime
	mark.remaining_lifetime = mark.total_lifetime
	mark.radius_px = lerpf(
		minimum_ring_radius_px,
		maximum_ring_radius_px,
		heat
	)
	mark.color = (
		miss_color
		if mark.is_miss
		else hit_color.lerp(hot_combo_color, heat)
	)
	mark.chevron_count = roundi(
		lerpf(
			float(minimum_chevron_count),
			float(maximum_chevron_count),
			heat
		)
	)
	mark.chevron_rotation = _random.randf_range(0.0, TAU)
	_marks.append(mark)
	set_process(true)
	queue_redraw()


## Retires expired marks and sleeps once the bar is quiet again.
func _process(delta: float) -> void:
	for mark_index in range(_marks.size() - 1, -1, -1):
		var mark := _marks[mark_index]
		mark.remaining_lifetime -= delta
		if mark.remaining_lifetime <= 0.0:
			_marks.remove_at(mark_index)
	queue_redraw()
	if _marks.is_empty():
		set_process(false)


## Draws every live mark plus the recoil outline the newest mark owns.
func _draw() -> void:
	var active_bar := _get_active_bar()
	if active_bar == null or not active_bar.is_visible_in_tree():
		return
	var bar_rect := active_bar.get_global_rect()
	bar_rect.position -= get_global_rect().position

	for mark in _marks:
		var life_ratio := clampf(
			mark.remaining_lifetime / mark.total_lifetime,
			0.0,
			1.0
		)
		if mark.is_miss:
			_draw_miss_slash(mark, bar_rect, life_ratio)
		else:
			_draw_hit_burst(mark, life_ratio)
		_draw_recoil_frame(mark, bar_rect, life_ratio)


## Draws one expanding ring and its ink chevrons for a landed hit.
func _draw_hit_burst(mark: HitMark, life_ratio: float) -> void:
	# The ring grows outward as it dies, which is what makes a hit read as an
	# impact leaving the bar instead of a highlight settling onto it.
	var growth := 1.0 - life_ratio
	var ring_radius := mark.radius_px * growth
	var ring_color := mark.color
	ring_color.a = life_ratio
	if ring_radius > 1.0:
		draw_arc(
			mark.bar_local_position,
			ring_radius,
			0.0,
			TAU,
			24,
			ring_color,
			maxf(ring_thickness_px * life_ratio, 1.0),
			false
		)

	for chevron_index in range(maxi(mark.chevron_count, 0)):
		var angle := (
			mark.chevron_rotation
			+ TAU * float(chevron_index) / float(maxi(mark.chevron_count, 1))
		)
		var direction := Vector2.RIGHT.rotated(angle)
		var stroke_start := mark.bar_local_position + direction * (
			ring_radius * 0.6
		)
		var stroke_end := stroke_start + direction * (
			chevron_length_px * life_ratio
		)
		var across := direction.orthogonal() * (
			chevron_width_px * 0.5 * life_ratio
		)
		draw_colored_polygon(
			PackedVector2Array([
				stroke_end,
				stroke_start + across,
				stroke_start - across
			]),
			ring_color
		)


## Draws one struck slash across the bar when the press missed everything.
func _draw_miss_slash(
	mark: HitMark,
	bar_rect: Rect2,
	life_ratio: float
) -> void:
	var slash_color := mark.color
	slash_color.a = life_ratio
	var slash_half_height := bar_rect.size.y * 0.5 + frame_kick_px
	var lean := slash_half_height * 0.45
	draw_line(
		Vector2(
			mark.bar_local_position.x - lean,
			mark.bar_local_position.y - slash_half_height
		),
		Vector2(
			mark.bar_local_position.x + lean,
			mark.bar_local_position.y + slash_half_height
		),
		slash_color,
		maxf(frame_thickness_px * 1.5 * life_ratio, 1.0)
	)


## Draws the bar's recoil outline: outward on a hit, inward on a miss.
func _draw_recoil_frame(
	mark: HitMark,
	bar_rect: Rect2,
	life_ratio: float
) -> void:
	var kick := frame_kick_px * life_ratio
	if mark.is_miss:
		kick = -kick
	var frame_color := mark.color
	frame_color.a = life_ratio
	draw_rect(
		bar_rect.grow(kick),
		frame_color,
		false,
		maxf(frame_thickness_px * life_ratio, 1.0)
	)


## Returns whichever of Caspian's two bars is currently on screen. Recovery wins
## while it is up, because that is the bar the player is actually reading.
func _get_active_bar() -> SliderTimingWindow:
	if timing_window == null:
		return null
	if (
		timing_window.recovery_window != null
		and timing_window.recovery_window.visible
	):
		return timing_window.recovery_window
	return timing_window.mining_window
