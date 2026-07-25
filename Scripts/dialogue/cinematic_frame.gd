class_name CinematicFrame
extends Control

## How it works:
## - Letterbox bars and the fullscreen iris are independent presentation layers.
## - Bars slide using their own normalized progress and pause-safe tween.
## - Bar height is a separate ratio, so the same two bars can meet in the middle
##   for a full blackout and then split apart into the authored letterbox.
## - The iris tracks a weak CanvasItem anchor in viewport coordinates.
## - Focus clamps its soft aperture inside the visible letterboxed safe area.
## - Open expands the aperture beyond every viewport edge, then hides it.
## - Reset cancels iris motion immediately without changing the bars.
## - Completion signals and wait methods support deterministic sequences.

signal frame_opened
signal frame_closed
signal blackout_revealed
signal iris_focused
signal iris_opened
signal iris_reset

enum IrisState {
	OPEN,
	FOCUSING,
	FOCUSED,
	OPENING,
}

@export_category("References")
@export var iris_overlay: ColorRect
@export var top_bar: ColorRect
@export var bottom_bar: ColorRect

@export_category("Letterbox Bars")
@export_range(0.05, 0.4, 0.01) var bar_height_ratio: float = 0.14
@export_range(0.0, 1.5, 0.05) var transition_seconds: float = 0.25

@export_category("Blackout Reveal")
## Starts the scene fully covered so a fade-to-black scene change can hand over
## without a lit frame in between. The owning sequence must call
## reveal_from_blackout(), or the shot never opens. The opening no longer needs
## it: the title shot is the lit world with the bars already closed, so the
## production overlay leaves this off and RunIntroController opens the frame
## instantly instead.
@export var starts_blacked_out: bool = false
## Half the viewport each, so the two bars meet exactly in the middle.
@export_range(0.25, 0.5, 0.01) var blackout_bar_height_ratio: float = 0.5
@export_range(0.0, 3.0, 0.05) var blackout_reveal_seconds: float = 0.35

@export_category("Iris Focus")
@export var iris_focus_radius: Vector2 = Vector2(170.0, 120.0)
@export_range(0.0, 96.0, 1.0) var iris_edge_softness: float = 28.0
@export_range(0.0, 64.0, 1.0) var iris_safe_margin: float = 12.0
@export_range(0.0, 2.0, 0.05) var iris_focus_duration: float = 0.35
@export_range(0.0, 2.0, 0.05) var iris_open_duration: float = 0.45
@export var iris_blackout_color: Color = Color.BLACK

var _frame_progress: float = 0.0:
	set(value):
		_frame_progress = clampf(value, 0.0, 1.0)
		_layout_bars()
## Current bar height as a share of the viewport. Ordinary framing holds this at
## bar_height_ratio; the blackout reveal animates it down from half the screen.
var _bar_cover_ratio: float = 0.14:
	set(value):
		_bar_cover_ratio = clampf(value, 0.0, 0.5)
		_layout_bars()
var _iris_radius_pixels: Vector2:
	set(value):
		_iris_radius_pixels = Vector2(
			maxf(value.x, 0.01),
			maxf(value.y, 0.01)
		)
		_update_iris_material()
var _iris_center_pixels: Vector2
var _iris_anchor_reference: WeakRef
var _iris_material: ShaderMaterial
var _iris_state: IrisState = IrisState.OPEN
var _bar_transition: Tween
var _iris_transition: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if iris_overlay == null:
		push_error("CinematicFrame requires its authored iris overlay.")
		return
	_iris_material = iris_overlay.material as ShaderMaterial
	if _iris_material == null:
		push_error("CinematicFrame iris requires its authored ShaderMaterial.")
		return
	# This node owns its own opening state so a scene that hands over from a
	# faded-to-black menu never shows one lit frame first.
	if starts_blacked_out:
		apply_blackout(true)
	else:
		_bar_cover_ratio = bar_height_ratio
		_frame_progress = 0.0
	_reset_iris(false)


func _process(_delta: float) -> void:
	if _iris_state == IrisState.OPEN:
		return
	var anchor := _get_iris_anchor()
	if anchor == null:
		reset_iris()
		return
	_iris_center_pixels = _resolve_safe_iris_center(anchor)
	_update_iris_material()


func _notification(what: int) -> void:
	if what != NOTIFICATION_RESIZED or not is_node_ready():
		return
	_layout_bars()
	_update_iris_material()


## Slides both letterbox bars into the viewport.
func open_frame(instant: bool = false) -> void:
	_start_bar_transition(1.0, instant, frame_opened)


## Slides both letterbox bars out of the viewport.
func close_frame(instant: bool = false) -> void:
	_start_bar_transition(0.0, instant, frame_closed)


## Covers the entire viewport by growing both bars until they meet in the middle.
func apply_blackout(instant: bool = false) -> void:
	if _bar_transition != null and _bar_transition.is_valid():
		_bar_transition.kill()
	_bar_transition = null
	_frame_progress = 1.0
	if instant or blackout_reveal_seconds <= 0.0:
		_bar_cover_ratio = blackout_bar_height_ratio
		return
	_bar_transition = create_tween()
	_bar_transition.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_bar_transition.tween_property(
		self,
		"_bar_cover_ratio",
		blackout_bar_height_ratio,
		blackout_reveal_seconds
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


## Splits the blackout apart from the middle down to the authored letterbox.
func reveal_from_blackout(instant: bool = false) -> void:
	if _bar_transition != null and _bar_transition.is_valid():
		_bar_transition.kill()
	_bar_transition = null
	_frame_progress = 1.0
	if instant or blackout_reveal_seconds <= 0.0:
		_bar_cover_ratio = bar_height_ratio
		_finish_blackout_reveal()
		return
	_bar_transition = create_tween()
	_bar_transition.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_bar_transition.tween_property(
		self,
		"_bar_cover_ratio",
		bar_height_ratio,
		blackout_reveal_seconds
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_bar_transition.tween_callback(_finish_blackout_reveal)


## Returns whether the bars still cover more than the authored letterbox.
func is_blacked_out() -> bool:
	return _bar_cover_ratio > bar_height_ratio + 0.001


## Suspends until the blackout has finished splitting open.
func wait_until_blackout_revealed() -> void:
	if not is_blacked_out():
		return
	await blackout_revealed


## Returns whether the bars are fully in place.
func is_open() -> bool:
	return is_equal_approx(_frame_progress, 1.0)


## Returns whether the bars are fully outside the viewport.
func is_closed() -> bool:
	return is_zero_approx(_frame_progress)


## Contracts a black mask around a tracked character or miner anchor.
func focus_iris_on(anchor: CanvasItem, instant: bool = false) -> bool:
	if anchor == null or _iris_material == null:
		return false
	_cancel_iris_transition()
	_iris_anchor_reference = weakref(anchor)
	_iris_center_pixels = _resolve_safe_iris_center(anchor)
	if _iris_state == IrisState.OPEN or not iris_overlay.visible:
		_iris_radius_pixels = _get_open_iris_radius()
	iris_overlay.show()
	_iris_state = IrisState.FOCUSING
	var target_radius := Vector2(
		maxf(iris_focus_radius.x, 1.0),
		maxf(iris_focus_radius.y, 1.0)
	)
	if instant or iris_focus_duration <= 0.0:
		_iris_radius_pixels = target_radius
		_finish_iris_focus()
		return true
	_iris_transition = create_tween()
	_iris_transition.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_iris_transition.tween_property(
		self,
		"_iris_radius_pixels",
		target_radius,
		iris_focus_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_iris_transition.tween_callback(_finish_iris_focus)
	return true


## Expands the active aperture until the entire cave is visible.
func open_iris(instant: bool = false) -> void:
	_cancel_iris_transition()
	if _iris_state == IrisState.OPEN or not iris_overlay.visible:
		_reset_iris(false)
		iris_opened.emit()
		return
	_iris_state = IrisState.OPENING
	var target_radius := _get_open_iris_radius()
	if instant or iris_open_duration <= 0.0:
		_iris_radius_pixels = target_radius
		_finish_iris_open()
		return
	_iris_transition = create_tween()
	_iris_transition.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_iris_transition.tween_property(
		self,
		"_iris_radius_pixels",
		target_radius,
		iris_open_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_iris_transition.tween_callback(_finish_iris_open)


## Immediately removes the mask and cancels any active focus transition.
func reset_iris() -> void:
	_reset_iris(true)


## Returns whether the iris is holding its authored focus radius.
func is_iris_focused() -> bool:
	return _iris_state == IrisState.FOCUSED


## Returns whether no iris mask remains over gameplay.
func is_iris_open() -> bool:
	return _iris_state == IrisState.OPEN


## Waits for a focus transition unless focus is already complete.
func wait_until_iris_focused() -> void:
	if is_iris_focused():
		return
	await iris_focused


## Waits for an opening transition unless the mask is already gone.
func wait_until_iris_open() -> void:
	if is_iris_open():
		return
	await iris_opened


func _start_bar_transition(
	target_progress: float,
	instant: bool,
	finished_signal: Signal
) -> void:
	if _bar_transition != null and _bar_transition.is_valid():
		_bar_transition.kill()
	_bar_transition = null
	# Ordinary framing always works from the authored letterbox height, so a
	# blackout can never leak into a later conversation.
	_bar_cover_ratio = bar_height_ratio

	if instant or is_equal_approx(_frame_progress, target_progress):
		_frame_progress = target_progress
		finished_signal.emit()
		return

	var duration := transition_seconds * absf(
		target_progress - _frame_progress
	)
	_bar_transition = create_tween()
	_bar_transition.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_bar_transition.tween_property(
		self,
		"_frame_progress",
		target_progress,
		maxf(duration, 0.01)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_bar_transition.tween_callback(finished_signal.emit)


func _finish_blackout_reveal() -> void:
	_bar_transition = null
	blackout_revealed.emit()
	frame_opened.emit()


func _finish_iris_focus() -> void:
	_iris_transition = null
	_iris_state = IrisState.FOCUSED
	iris_focused.emit()


func _finish_iris_open() -> void:
	_iris_radius_pixels = _get_open_iris_radius()
	_iris_transition = null
	_iris_anchor_reference = null
	_iris_state = IrisState.OPEN
	iris_overlay.hide()
	iris_opened.emit()


func _reset_iris(emit_signal: bool) -> void:
	_cancel_iris_transition()
	_iris_anchor_reference = null
	_iris_state = IrisState.OPEN
	_iris_center_pixels = size * 0.5
	_iris_radius_pixels = _get_open_iris_radius()
	iris_overlay.hide()
	if emit_signal:
		iris_reset.emit()
		iris_opened.emit()


func _cancel_iris_transition() -> void:
	if _iris_transition != null and _iris_transition.is_valid():
		_iris_transition.kill()
	_iris_transition = null


func _get_iris_anchor() -> CanvasItem:
	if _iris_anchor_reference == null:
		return null
	return _iris_anchor_reference.get_ref() as CanvasItem


## Keeps the final focused ellipse clear of both letterbox bars and side edges.
func _resolve_safe_iris_center(anchor: CanvasItem) -> Vector2:
	var anchor_center := (
		anchor.get_global_transform_with_canvas().origin
		- global_position
	)
	var safe_radius := Vector2(
		maxf(iris_focus_radius.x, 1.0),
		maxf(iris_focus_radius.y, 1.0)
	) + Vector2.ONE * (iris_edge_softness + iris_safe_margin)
	var visible_bar_height := (
		size.y * _bar_cover_ratio * _frame_progress
	)
	var minimum_center := Vector2(
		safe_radius.x,
		visible_bar_height + safe_radius.y
	)
	var maximum_center := Vector2(
		size.x - safe_radius.x,
		size.y - visible_bar_height - safe_radius.y
	)
	if minimum_center.x > maximum_center.x:
		anchor_center.x = size.x * 0.5
	else:
		anchor_center.x = clampf(
			anchor_center.x,
			minimum_center.x,
			maximum_center.x
		)
	if minimum_center.y > maximum_center.y:
		anchor_center.y = size.y * 0.5
	else:
		anchor_center.y = clampf(
			anchor_center.y,
			minimum_center.y,
			maximum_center.y
		)
	return anchor_center


func _get_open_iris_radius() -> Vector2:
	var viewport_diagonal := size.length()
	return Vector2.ONE * maxf(viewport_diagonal, 1.0)


func _update_iris_material() -> void:
	if _iris_material == null or size.y <= 0.0:
		return
	var safe_size := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	var minimum_radius := maxf(
		minf(_iris_radius_pixels.x, _iris_radius_pixels.y),
		1.0
	)
	_iris_material.set_shader_parameter(
		&"aperture_center",
		_iris_center_pixels / safe_size
	)
	_iris_material.set_shader_parameter(
		&"aperture_radius",
		_iris_radius_pixels / safe_size.y
	)
	_iris_material.set_shader_parameter(
		&"viewport_aspect",
		safe_size.x / safe_size.y
	)
	_iris_material.set_shader_parameter(
		&"edge_softness",
		clampf(iris_edge_softness / minimum_radius, 0.0, 0.95)
	)
	_iris_material.set_shader_parameter(
		&"blackout_color",
		iris_blackout_color
	)


func _layout_bars() -> void:
	if top_bar == null or bottom_bar == null:
		return
	var frame_size := size
	var bar_height := frame_size.y * _bar_cover_ratio
	top_bar.modulate.a = _frame_progress
	bottom_bar.modulate.a = _frame_progress
	top_bar.position = Vector2(0.0, -bar_height * (1.0 - _frame_progress))
	top_bar.size = Vector2(frame_size.x, bar_height)
	bottom_bar.position = Vector2(
		0.0,
		frame_size.y - bar_height * _frame_progress
	)
	bottom_bar.size = Vector2(frame_size.x, bar_height)
