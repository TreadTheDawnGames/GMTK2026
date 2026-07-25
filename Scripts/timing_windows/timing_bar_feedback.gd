class_name TimingBarFeedback
extends Control

## How it works:
## - One timing result in, one Mark out, every Mark drawn until it expires.
##   MiningSceneWiring routes TimingWindowTask.pressed to _on_timing_pressed.
## - A Mark is only: where on the bar it landed, how much life is left (1 -> 0),
##   what colour it is, and how far its shapes reach. Every visual below is a
##   pure function of those four, so adding one is a single _draw_* helper plus
##   a single call in _draw.
## - Strictly read-only against the timing bar: it reads the active bar's rect
##   and slider position and never writes a property back, because
##   Scenes/slider_timing_window.gd is adapt-only.
## The invariant is that _marks never exceeds maximum_active_marks.

## One resolved press, fading out.
class Mark:
	## Where the press landed, in this control's local pixels.
	var position: Vector2
	## 1.0 the frame it was made, 0.0 when it expires. Every shape reads this.
	var life: float = 1.0
	## Seconds the mark takes to run that 1.0 down to 0.0.
	var lifetime: float
	var color: Color
	## Ring radius at full expansion. Spokes are sized from it.
	var reach_px: float
	var spoke_count: int
	## Random turn of the spoke ring, so repeat hits do not stamp identically.
	var spoke_offset: float
	var is_miss: bool


const RING_SEGMENTS: int = 24

@export_category("References")
@export var timing_window: TimingWindowTask

@export_category("Palette")
@export var hit_color: Color = Color("ffe9a8")
## A hit blends toward this as the combo climbs to combo_heat_ceiling.
@export var hot_combo_color: Color = Color("ff9c41")
@export var miss_color: Color = Color("d1483f")

@export_category("Response")
## Combo at which a mark is drawn at full heat: biggest, hottest, most spokes.
## Nothing grows past it, so a long streak cannot throw a ring off screen.
@export_range(1, 60, 1) var combo_heat_ceiling: int = 12
@export_range(0.05, 1.0, 0.01) var hit_seconds: float = 0.26
@export_range(0.05, 1.5, 0.01) var miss_seconds: float = 0.34

@export_category("Shape")
## Ring radius at zero heat and at the heat ceiling.
@export_range(4.0, 200.0, 1.0) var cold_ring_radius_px: float = 26.0
@export_range(4.0, 240.0, 1.0) var hot_ring_radius_px: float = 74.0
## Spoke length as a share of the ring radius, so spokes grow with heat too.
@export_range(0.05, 2.0, 0.05) var spoke_length_ratio: float = 0.28
@export_range(0, 12, 1) var cold_spoke_count: int = 3
@export_range(0, 12, 1) var hot_spoke_count: int = 7
## One stroke weight for the ring, the spokes, and the recoil outline. Sharing
## it is what makes the three read as one drawn mark instead of three effects.
@export_range(1.0, 16.0, 0.5) var stroke_width_px: float = 5.0
## How far the recoil outline kicks off the bar's edge: outward on a hit,
## inward on a miss. The bar itself never moves; only this outline does.
@export_range(0.0, 40.0, 0.5) var frame_kick_px: float = 7.0

@export_category("Performance")
## Bounded per-press accumulation: a press at capacity retires the oldest mark
## first, so a fast streak never grows this array.
@export_range(1, 16, 1) var maximum_active_marks: int = 6

var _marks: Array[Mark] = []
var _random := RandomNumberGenerator.new()


## Sleeps until MiningSceneWiring routes the first timing result here.
func _ready() -> void:
	_random.randomize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	if timing_window == null:
		push_error("TimingBarFeedback requires a TimingWindowTask.")


## Turns one timing result into one Mark at the slider's resolved position.
func _on_timing_pressed(
	success: bool,
	combo: int,
	_hit_direction: int
) -> void:
	var bar := _get_active_bar()
	if bar == null or not bar.is_visible_in_tree():
		return
	var bar_rect := _to_local_rect(bar.get_global_rect())
	if not bar_rect.has_area():
		return
	while _marks.size() >= maxi(maximum_active_marks, 1):
		_marks.remove_at(0)

	var heat := clampf(
		float(maxi(combo, 0)) / float(maxi(combo_heat_ceiling, 1)),
		0.0,
		1.0
	)
	var mark := Mark.new()
	mark.is_miss = not success
	mark.position = Vector2(
		bar_rect.position.x + bar.slider_position,
		bar_rect.get_center().y
	)
	mark.lifetime = miss_seconds if mark.is_miss else hit_seconds
	mark.color = (
		miss_color
		if mark.is_miss
		else hit_color.lerp(hot_combo_color, heat)
	)
	mark.reach_px = lerpf(cold_ring_radius_px, hot_ring_radius_px, heat)
	mark.spoke_count = roundi(
		lerpf(float(cold_spoke_count), float(hot_spoke_count), heat)
	)
	mark.spoke_offset = _random.randf_range(0.0, TAU)
	_marks.append(mark)
	set_process(true)
	queue_redraw()


## Ages every mark and sleeps once the bar is quiet again.
func _process(delta: float) -> void:
	for mark_index in range(_marks.size() - 1, -1, -1):
		var mark := _marks[mark_index]
		mark.life -= delta / maxf(mark.lifetime, 0.01)
		if mark.life <= 0.0:
			_marks.remove_at(mark_index)
	queue_redraw()
	if _marks.is_empty():
		set_process(false)


## Draws every live mark, oldest first so the newest press reads on top.
## To add a visual: write one _draw_* helper and call it from here.
func _draw() -> void:
	var bar := _get_active_bar()
	if bar == null or not bar.is_visible_in_tree():
		return
	var bar_rect := _to_local_rect(bar.get_global_rect())

	for mark in _marks:
		var mark_color := mark.color
		mark_color.a = mark.life
		if mark.is_miss:
			_draw_slash(mark, bar_rect, mark_color)
		else:
			_draw_ring(mark, mark_color)
			_draw_spokes(mark, mark_color)

	# The recoil outline belongs to the newest press alone. One per mark stacks
	# outlines during a streak and reads as a flicker rather than as a kick.
	if not _marks.is_empty():
		_draw_recoil(_marks.back(), bar_rect)


## Ring that grows as it dies, so a hit reads as an impact leaving the bar
## rather than as a highlight settling onto it.
func _draw_ring(mark: Mark, mark_color: Color) -> void:
	var radius := mark.reach_px * (1.0 - mark.life)
	if radius < 1.0:
		return
	draw_arc(
		mark.position,
		radius,
		0.0,
		TAU,
		RING_SEGMENTS,
		mark_color,
		_stroke_width(mark),
		false
	)


## Tapered ink strokes riding that ring outward, evenly spaced around it.
func _draw_spokes(mark: Mark, mark_color: Color) -> void:
	if mark.spoke_count <= 0:
		return
	var radius := mark.reach_px * (1.0 - mark.life)
	var spoke_length := mark.reach_px * spoke_length_ratio * mark.life
	for spoke_index in range(mark.spoke_count):
		var direction := Vector2.RIGHT.rotated(
			mark.spoke_offset
			+ TAU * float(spoke_index) / float(mark.spoke_count)
		)
		var spoke_base := mark.position + direction * radius
		var across := direction.orthogonal() * _stroke_width(mark) * 0.5
		draw_colored_polygon(
			PackedVector2Array([
				spoke_base + direction * spoke_length,
				spoke_base + across,
				spoke_base - across
			]),
			mark_color
		)


## Single struck slash across the bar for a press that hit nothing.
func _draw_slash(mark: Mark, bar_rect: Rect2, mark_color: Color) -> void:
	var half_height := bar_rect.size.y * 0.5 + frame_kick_px
	var lean := half_height * 0.45
	draw_line(
		mark.position + Vector2(-lean, -half_height),
		mark.position + Vector2(lean, half_height),
		mark_color,
		_stroke_width(mark) * 1.5
	)


## Outline kicked off the bar's edge, outward on a hit and inward on a miss, so
## the bar reads as having recoiled without this node ever moving it.
func _draw_recoil(mark: Mark, bar_rect: Rect2) -> void:
	var mark_color := mark.color
	mark_color.a = mark.life
	var kick := frame_kick_px * mark.life
	draw_rect(
		bar_rect.grow(-kick if mark.is_miss else kick),
		mark_color,
		false,
		_stroke_width(mark)
	)


## Stroke weight for one mark, thinning as it fades. Never below one pixel, or
## a nearly-dead mark vanishes into a gap instead of fading out.
func _stroke_width(mark: Mark) -> float:
	return maxf(stroke_width_px * mark.life, 1.0)


## Converts a global rect into this control's local drawing space.
func _to_local_rect(global_rect: Rect2) -> Rect2:
	return Rect2(global_rect.position - global_position, global_rect.size)


## Returns whichever of the two bars is on screen. Recovery wins while it is up,
## because that is the bar the player is actually reading.
func _get_active_bar() -> SliderTimingWindow:
	if timing_window == null:
		return null
	if (
		timing_window.recovery_window != null
		and timing_window.recovery_window.visible
	):
		return timing_window.recovery_window
	return timing_window.mining_window
