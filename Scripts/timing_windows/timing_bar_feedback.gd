class_name TimingBarFeedback
extends Control

## How it works:
## - Two jobs, in this order. The gauge draws the standing state of the streak
##   every frame it changes. The marks draw one short burst per press and expire.
## - The gauge is the combo readout, so the bar carries no number. One segment
##   lights per hit toward MiningConfig.maximum_effect_combo, which is where the
##   controller stops paying for a longer streak, and a heavier notch sits at
##   recovery_combo_threshold, which is where a miss earns a quick-save. Both
##   facts are invisible in a bare "Combo: 9".
## - A Mark is only: where on the bar it landed, how much life is left (1 -> 0),
##   what colour it is, and how far its shapes reach. Every mark visual is a pure
##   function of those four, so adding one is a single _draw_* helper plus a
##   single call in _draw.
## - Flashes and frames redraw the bar's own StyleBox rather than outlining it,
##   so they inherit the drawn rounded corners and nine-slice margins for free,
##   and the bare quick-save strip can borrow the main bar's frame art. A
##   rectangle matched neither shape nor footprint and read as a box on the art.
## - This node draws additively, so every mark and fill lights the art up instead
##   of painting over it. Additive cannot darken, which is why the quick-save
##   moment reads through cyan and brightness rather than by dimming the bar
##   behind it.
## - Strictly read-only against the timing bar: it reads rects, slider position,
##   combo, config, and StyleBoxes, and never writes a property back, because
##   Scenes/slider_timing_window.gd and Scenes/TimingWindow.tscn are adapt-only.
##   StyleBoxes are tinted on cached duplicates, never on the bar's resources.
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
	var is_miss: bool

#@export_category("References")
# This is a circular reference.
#@export var timing_window: TimingWindowTask
var timing_window: WeakRef
@onready var mining_window: TimingWindow = %MiningWindow
@onready var recovery_window: TimingWindow = %RecoveryWindow
@onready var recovery_window2: TimingWindow = %RecoveryWindow2

@export_category("Palette")
@export var hit_color: Color = Color("ffe9a8")
## Charge and hits blend toward this as the streak fills the gauge.
@export var hot_combo_color: Color = Color("ff9c41")
@export var miss_color: Color = Color("d1483f")
## Owns the whole quick-save moment. Matches TimingWindowTask.combo_saved_color
## and the recovery bar's own authored flash, so one colour means "savable".
@export var recovery_color: Color = Color("26b4ff")
@export var pulse_stylebox : StyleBoxFlat

@export_category("Charge Gauge")
@export_range(2.0, 40.0, 1.0) var charge_height_px: float = 7.0
## Inset from the bar's own ends. Large enough to clear the frame art's drawn
## corners, so the strip never runs into the rounded ends.
@export_range(0.0, 80.0, 1.0) var charge_side_inset_px: float = 26.0
## Clearance between the bottom of the drawn frame art and the gauge. The gauge
## sits outside the box, so it never competes with the slider, the targets, or
## the depth number for the same pixels.
@export_range(0.0, 60.0, 1.0) var charge_gap_px: float = 7.0
## Extra height carried by lit segments only. The fill boundary then reads as a
## change in shape rather than only as a change in brightness.
@export_range(0.0, 16.0, 0.5) var charge_lit_extra_px: float = 3.0
@export_range(0.0, 12.0, 0.5) var charge_segment_gap_px: float = 3.0
## Unlit segments still show, faintly, or the gauge has no readable length.
@export_range(0.0, 1.0, 0.01) var charge_track_alpha: float = 0.09
@export_range(0.0, 1.0, 0.01) var charge_lit_alpha: float = 1.0
## How far the quick-save notch stands proud of the strip, top and bottom.
@export_range(0.0, 20.0, 0.5) var threshold_notch_px: float = 4.0

@export_category("Response")
## Combo at which a mark is drawn at full heat: widest and hottest.
## Nothing grows past it, so a long streak cannot throw a ring off screen.
@export_range(1, 60, 1) var combo_heat_ceiling: int = 12
@export_range(0.05, 1.0, 0.01) var hit_seconds: float = 0.26
@export_range(0.05, 1.5, 0.01) var miss_seconds: float = 0.34
## Lost combo segments turn off at this interval. The counter is bounded by the
## combo bar's configured maximum and owns no per-loss allocations.
@export_range(0.01, 0.25, 0.01) var combo_loss_step_seconds: float = 0.05

@export_category("Shape")
## Stroke weight shared by the miss slash and any future line work.
@export_range(1.0, 16.0, 0.5) var stroke_width_px: float = 5.0
## How far the flashed frame swells past the bar's own art: outward on a hit,
## inward on a miss. The bar itself never moves; only this redraw does.
@export_range(0.0, 40.0, 0.5) var frame_kick_px: float = 7.0
## Peak brightness of the frame flash. It is drawn additively over the bar's own
## art, so this is how hard the drawn texture lights up rather than a colour.
@export_range(0.0, 2.0, 0.05) var shine_strength: float = 0.85
## Brightness of the frame borrowed by the quick-save strip while it is up.
@export_range(0.0, 2.0, 0.05) var recovery_frame_strength: float = 0.55
## Expand margin used when the quick-save strip borrows that frame. The art's
## own 20 px would spill a third of the frame's height past a 17 px strip and
## collide with the main bar's art below it; the strip is far too thin to wear
## the margins the main bar was drawn for.
@export_range(0.0, 40.0, 1.0) var recovery_frame_expand_px: float = 8.0

@export_category("Performance")
## Bounded per-press accumulation: a press at capacity retires the oldest mark
## first, so a fast streak never grows this array.
@export_range(1, 16, 1) var maximum_active_marks: int = 6

var _marks: Array[Mark] = []
var _random := RandomNumberGenerator.new()
# Both caches are keyed by nodes and resources the timing scene already owns, so
# each holds at most one entry per bar: two for the mining and recovery bars.
var _shine_surfaces: Dictionary[TimingWindow, Control] = {}
var _tinted_styles: Dictionary[StyleBox, StyleBox] = {}
# Last drawn gauge state. The gauge is standing UI, so it has to redraw when the
# streak changes rather than only when a press happens, but redrawing every
# frame for a strip that usually holds still is waste. Comparing is cheaper.
var _drawn_combo: int = -1
var _drawn_is_recovering: bool = false
var _reduce_motion_enabled: bool = false
var _combo_loss_elapsed_seconds: float = 0.0
var _is_combo_loss_animating: bool = false

@onready var combo_bar: NotchedProgressBar = %ComboBar

## Prepares the additive canvas and starts the idle state watch.
func _ready() -> void:
	timing_window = weakref(get_parent())
	combo_bar.value = 0.0
	combo_bar.set_maximum(_combo_ceiling())
	#combo_bar.add_tick(_recovery_threshold())
	recovery_window.pressed.connect(_on_timing_pressed)
	recovery_window2.pressed.connect(_on_timing_pressed)
	combo_bar.add_ticks(_tier_thresholds())
	#print("tiers: ", _tier_thresholds())
	
	
	_random.randomize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Additive, so every mark and fill lights the bar's art up rather than
	# painting over it. Alpha stays the strength dial.
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = glow_material
	#if timing_window == null:
		#push_error("TimingBarFeedback requires a TimingWindowTask.")


## Keeps color confirmation while removing the frame's spatial expansion.
func set_reduce_motion_enabled(enabled: bool) -> void:
	_reduce_motion_enabled = enabled
	queue_redraw()


## Turns one timing result into one Mark at the slider's resolved position.
func _on_timing_pressed(
	success: bool,
	combo: int,
	_hit_direction: int
) -> void:
	if success:
		_is_combo_loss_animating = false
		_combo_loss_elapsed_seconds = 0.0
		combo_bar.value = float(_current_combo())

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
	_marks.append(mark)
	queue_redraw()


## Starts the stepped presentation reset only after recovery is exhausted.
func _on_streak_ended(_previous_combo: int) -> void:
	if combo_bar.value <= 0.0:
		return
	_is_combo_loss_animating = true
	_combo_loss_elapsed_seconds = 0.0


## Ages the marks, and redraws whenever anything visible actually changed.
func _process(delta: float) -> void:
	if _is_combo_loss_animating:
		_combo_loss_elapsed_seconds += delta
		var step_seconds := maxf(combo_loss_step_seconds, 0.01)
		while (
			_combo_loss_elapsed_seconds >= step_seconds
			and combo_bar.value > 0.0
		):
			_combo_loss_elapsed_seconds -= step_seconds
			combo_bar.value = maxf(combo_bar.value - 1.0, 0.0)
		if combo_bar.value <= 0.0:
			_is_combo_loss_animating = false
			_combo_loss_elapsed_seconds = 0.0

	for mark_index in range(_marks.size() - 1, -1, -1):
		var mark := _marks[mark_index]
		mark.life -= delta / maxf(mark.lifetime, 0.01)
		if mark.life <= 0.0:
			_marks.remove_at(mark_index)

	var combo := _current_combo()
	var is_recovering := _is_recovering()
	# A full gauge pulses, so it earns a redraw every frame on its own.
	if (
		not _marks.is_empty()
		or combo != _drawn_combo
		or is_recovering != _drawn_is_recovering
		or combo >= _combo_ceiling()
	):
		queue_redraw()

	#if combo_bar.value == combo_bar.max_value:
		#combo_bar.


## Draws the standing gauge first, then every live mark over it.
## To add a visual: write one _draw_* helper and call it from here.
func _draw() -> void:
	var bar := _get_active_bar()
	if bar == null or not bar.is_visible_in_tree():
		return
	var main_bar := mining_window
	if main_bar == null:
		return
	_drawn_combo = _current_combo()
	_drawn_is_recovering = _is_recovering()

	# The gauge belongs to the main bar even while the quick-save line is up:
	# it is the streak being fought for, not the bar you are currently hitting.
	# It is placed against the drawn art rather than the Control rect, so it
	# clears the frame's expand margins and stays outside the box.
	#_draw_charge(_drawn_frame_rect(main_bar))
	#_draw_recovery_frame(main_bar)

	# Only a miss marks the track itself. A success used to strike a bright
	# column at the slider, which sat exactly where the slider was and cost you
	# the one thing you need after a hit: knowing where the slider now is. A
	# success is reported entirely outside the track instead, by the frame
	# flashing, the gauge gaining a segment, and the spark at the pickaxe.
	for mark in _marks:
		if not mark.is_miss:
			continue
		var mark_color := mark.color
		mark_color.a = mark.life
		_draw_slash(mark, _to_local_rect(bar.get_global_rect()), mark_color)

	# The frame flash belongs to the newest press alone. One per mark stacks
	# redraws during a streak and reads as a flicker rather than as a kick.
	if not _marks.is_empty():
		_draw_frame_flash(_marks.back(), bar)


## One lit segment per hit along the bar's lower edge, plus a standing notch at
## the combo that earns a quick-save. Reading the streak becomes looking at how
## much of the bar is lit and whether the notch is behind you.
func _draw_charge(bar_rect: Rect2) -> void:
	var ceiling := _combo_ceiling()
	if ceiling <= 0 or not bar_rect.has_area():
		return
	var track := Rect2(
		bar_rect.position.x + charge_side_inset_px,
		bar_rect.end.y + charge_gap_px,
		bar_rect.size.x - charge_side_inset_px * 2.0,
		charge_height_px
	)
	if track.size.x <= 0.0:
		return

	var lit_count := clampi(_current_combo(), 0, ceiling)
	var fill_ratio := float(lit_count) / float(ceiling)
	var lit_color := (
		recovery_color
		if _is_recovering()
		else hit_color.lerp(hot_combo_color, fill_ratio)
	)
	lit_color.a = charge_lit_alpha * _full_gauge_pulse(lit_count, ceiling)
	var track_color := lit_color
	track_color.a = charge_track_alpha

	var segment_width := track.size.x / float(ceiling)
	for segment_index in range(ceiling):
		var is_lit := segment_index < lit_count
		# Lit segments stand taller and grow downward from a shared top edge, so
		# the filled run reads as one solid block against the thin empty track.
		var extra_height := charge_lit_extra_px if is_lit else 0.0
		draw_rect(
			Rect2(
				track.position.x + segment_width * float(segment_index),
				track.position.y,
				maxf(segment_width - charge_segment_gap_px, 1.0),
				track.size.y + extra_height
			),
			lit_color if is_lit else track_color
		)

	# Dividers first, quick-save notch second: where the two land on the same
	# combo the notch is the more urgent read and should sit on top.
	_draw_tier_dividers(track, segment_width, ceiling)
	_draw_threshold_notch(track, segment_width, ceiling, lit_color)


## The divisions at MiningConfig.combo_tier_thresholds. Crossing one is what
## adds a music layer and punches the camera, so the gauge shows where those
## steps are rather than leaving the escalation as something only heard.
func _draw_tier_dividers(
	track: Rect2,
	segment_width: float,
	ceiling: int
) -> void:
	var reached_combo := _current_combo()
	for threshold: int in _tier_thresholds():
		if threshold <= 0 or threshold > ceiling:
			continue
		var divider_color := hot_combo_color
		divider_color.a = (
			charge_lit_alpha * 0.5
			if reached_combo >= threshold
			else charge_track_alpha * 1.5
		)
		draw_rect(
			Rect2(
				track.position.x
					+ segment_width * float(threshold)
					- charge_segment_gap_px,
				track.position.y,
				maxf(charge_segment_gap_px, 1.0),
				track.size.y
			),
			divider_color
		)


## The standing mark at recovery_combo_threshold. Past it a miss buys a
## quick-save instead of ending the streak, which nothing else on screen says.
func _draw_threshold_notch(
	track: Rect2,
	segment_width: float,
	ceiling: int,
	lit_color: Color
) -> void:
	var threshold := _recovery_threshold()
	if threshold <= 0 or threshold > ceiling:
		return
	var notch_color := recovery_color
	notch_color.a = (
		charge_lit_alpha
		if _current_combo() >= threshold
		else charge_track_alpha * 2.0
	)
	draw_rect(
		Rect2(
			track.position.x
				+ segment_width * float(threshold)
				- charge_segment_gap_px,
			track.position.y - threshold_notch_px,
			maxf(charge_segment_gap_px, 1.0),
			track.size.y + threshold_notch_px * 2.0
		),
		notch_color
	)


## Lends the main bar's drawn frame to the quick-save strip while it is up. The
## strip ships as a bare rounded box, and it is both the fastest and the tightest
## input in the run, so it should not also be the least legible thing on screen.
func _draw_recovery_frame(main_bar: TimingWindow) -> void:
	if not _is_recovering():
		return
	var recovery_bar := recovery_window
	var frame_style := _frame_style_of(recovery_window)
	if frame_style == null:
		return
	var tint := recovery_color
	tint.a = recovery_frame_strength
	_tinted_style(frame_style, tint, recovery_frame_expand_px).draw(
		get_canvas_item(),
		_to_local_rect(recovery_bar.get_global_rect())
	)


## Single struck slash across the bar for a press that hit nothing.
func _draw_slash(mark: Mark, bar_rect: Rect2, mark_color: Color) -> void:
	var reversed : float = (1.0 if randi() % 2 == 0 else -1.0) + (randf() * 0.5)
	var half_height := bar_rect.size.y * 0.5 + frame_kick_px * reversed
	var lean := half_height * 0.45 * reversed
	draw_line(
		mark.position + Vector2(-lean, -half_height),
		mark.position + Vector2(lean, half_height),
		mark_color,
		_stroke_width(mark) * 1.5
	)


## Redraws the bar's own frame over itself, tinted and swelling with the kick,
## so the drawn texture lights up and a later art change carries through here.
func _draw_frame_flash(mark: Mark, bar: TimingWindow) -> void:
	var frame_style := pulse_stylebox#_frame_style_of(bar)
	if frame_style == null:
		return
	var tint := mark.color
	tint.a = mark.life * shine_strength
	var kick := (
		0.0
		if _reduce_motion_enabled
		else frame_kick_px * mark.life
	)
	var surface := _get_shine_surface(bar)
	# -1 keeps the art's authored margins, so the flash lands exactly on the
	# frame it is flashing.
	_tinted_style(frame_style, tint, -1.0).draw(
		get_canvas_item(),
		_to_local_rect(surface.get_global_rect()).grow(
			-kick if mark.is_miss else kick
		)
	)


## The rectangle the frame art actually covers: the Control rect grown by the
## StyleBox's expand margins. Placing against this rather than the bare rect is
## what keeps the gauge outside the drawn box even if the art's margins change.
func _drawn_frame_rect(bar: TimingWindow) -> Rect2:
	var rect := _to_local_rect(_get_shine_surface(bar).get_global_rect())
	var textured_style := _frame_style_of(bar) as StyleBoxTexture
	if textured_style == null:
		return rect
	return Rect2(
		rect.position - Vector2(
			textured_style.expand_margin_left,
			textured_style.expand_margin_top
		),
		rect.size + Vector2(
			textured_style.expand_margin_left
				+ textured_style.expand_margin_right,
			textured_style.expand_margin_top
				+ textured_style.expand_margin_bottom
		)
	)


## The StyleBox carrying one bar's drawn frame, or null if it has none.
func _frame_style_of(bar: TimingWindow) -> StyleBox:
	var surface := _get_shine_surface(bar)
	if surface == null:
		return null
	return surface.get_theme_stylebox(&"panel")


## The control whose StyleBox carries the bar's drawn frame. Found by searching
## for a textured box rather than by a hard-coded path, so renaming a node
## inside the adapt-only timing scene cannot silently drop the flash. Bars with
## no drawn frame, like the quick-save strip, fall back to their own plain box.
func _get_shine_surface(bar: TimingWindow) -> Control:
	if _shine_surfaces.has(bar):
		return _shine_surfaces[bar]
	var surface: Control = bar
	for candidate: Panel in bar.find_children("*", "Panel", true, false):
		if candidate.get_theme_stylebox(&"panel") is StyleBoxTexture:
			surface = candidate
			break
	_shine_surfaces[bar] = surface
	return surface


## Returns a tinted copy of one of the bar's styleboxes, duplicated once and
## reused, so a press never allocates and the bar's own resource is never
## written to. StyleBox has no shared tint property, so each kind sets its own.
## expand_px overrides the art's nine-slice expand margins; pass -1 to keep
## them. Callers must draw immediately after asking, because one source box maps
## to one shared copy.
func _tinted_style(
	source_style: StyleBox,
	tint: Color,
	expand_px: float
) -> StyleBox:
	var tinted: StyleBox = _tinted_styles.get(source_style)
	if tinted == null:
		tinted = source_style.duplicate()
		_tinted_styles[source_style] = tinted
	if tinted is StyleBoxTexture:
		var textured := tinted as StyleBoxTexture
		textured.modulate_color = tint
		var source_textured := source_style as StyleBoxTexture
		textured.expand_margin_left = (
			source_textured.expand_margin_left if expand_px < 0.0 else expand_px
		)
		textured.expand_margin_top = (
			source_textured.expand_margin_top if expand_px < 0.0 else expand_px
		)
		textured.expand_margin_right = (
			source_textured.expand_margin_right if expand_px < 0.0 else expand_px
		)
		textured.expand_margin_bottom = (
			source_textured.expand_margin_bottom
			if expand_px < 0.0
			else expand_px
		)
	elif tinted is StyleBoxFlat:
		var flat_style := tinted as StyleBoxFlat
		flat_style.bg_color = Color(tint, tint.a * 0.3)
		flat_style.border_color = tint
	return tinted


## Breathes the gauge once it is full, which is the only signal that a longer
## streak has stopped buying anything.
func _full_gauge_pulse(lit_count: int, ceiling: int) -> float:
	if lit_count < ceiling:
		return 1.0
	return 0.78 + 0.22 * sin(float(Time.get_ticks_msec()) * 0.008)


## Stroke weight for one mark, thinning as it fades. Never below one pixel, or
## a nearly-dead mark vanishes into a gap instead of fading out.
func _stroke_width(mark: Mark) -> float:
	return maxf(stroke_width_px * mark.life, 1.0)


## Converts a global rect into this control's local drawing space.
func _to_local_rect(global_rect: Rect2) -> Rect2:
	return Rect2(global_rect.position - global_position, global_rect.size)


## The streak the gauge is showing. It survives a savable miss, because the
## quick-save is fought for with the streak still standing.
func _current_combo() -> int:
	return 0 if timing_window.get_ref() == null else maxi(timing_window.get_ref().combo, 0)


## Segments in the gauge: the combo past which the controller stops paying.
func _combo_ceiling() -> int:
	if timing_window.get_ref() == null or timing_window.get_ref().mining_config == null:
		return 0
	return maxi(timing_window.get_ref().mining_config.maximum_effect_combo, 1)


## Combos that promote the run into its next escalation step. Shared with
## ComboDirector through the config, so the gauge and the music agree.
func _tier_thresholds() -> Array[int]:
	if timing_window.get_ref() == null or timing_window.get_ref().mining_config == null:
		return [] as Array[int]
	return timing_window.get_ref().mining_config.combo_tier_thresholds


## Combo at which a miss earns a quick-save instead of ending the streak.
func _recovery_threshold() -> int:
	if timing_window.get_ref() == null or timing_window.get_ref().mining_config == null:
		return 0
	return timing_window.get_ref().mining_config.recovery_combo_threshold


## Whether the quick-save strip currently owns the moment.
func _is_recovering() -> bool:
	return (
		#timing_window != null
		#and 
		recovery_window != null
		and recovery_window.visible
	)

func _is_second_recovering() -> bool:
	return (
		#timing_window != null
		#and 
		recovery_window != null
		and recovery_window2.visible
	)
## Returns whichever of the two bars is on screen. Recovery wins while it is up,
## because that is the bar the player is actually reading.
func _get_active_bar() -> TimingWindow:
	#if timing_window == null:
		#return null
	if _is_second_recovering():
		return recovery_window2
	if _is_recovering():
		return recovery_window
	return mining_window
