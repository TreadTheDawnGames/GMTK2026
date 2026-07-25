class_name OpeningShotCamera
extends Node

## How it works:
## - Inputs: the authored menu zoom and the bus's live trailing edge. Output:
##   the shared Camera2D's zoom, and only for the length of the opening.
## - apply_menu_framing() holds the wide title shot. start_zoom_in() then waits,
##   still at that framing, until the bus is fully inside it. Only from that
##   moment does the ease toward gameplay_zoom start, and every eased value is
##   capped so the bus's trailing edge stays in frame. The ease is deliberately
##   faster than the bus, so the cap is what actually paces the shot: the right
##   edge of the frame rides the back of the bus as the world closes in, and
##   the last of the zoom lands as the bus pulls away.
## - Holding before the latch is the whole trick. Advancing the ease while the
##   bus is still driving in would let the camera outrun it, and a cap the shot
##   has already passed can never take hold again.
## - Owned state: the eased progress, the reached zoom, the latch, and how long
##   the hold has run. The zoom is re-asserted every processed frame, including
##   while holding: starting a run resets it, and that reset hands the camera
##   back to its gameplay rest zoom underneath this shot.
## - Zoom only ever increases. The cap can only rise once the bus is framed (it
##   drives in, then leaves), so a monotonic zoom keeps the bus covered while
##   stopping a late ease from pulling the shot back out.
## The invariant is that this node writes camera.zoom only between
## apply_menu_framing() and release(), and always leaves it at gameplay_zoom.

signal framing_settled

# Zoom this close to gameplay framing is gameplay framing. Half a percent is
# well under a pixel of parallax at the shot's scale.
const _SETTLE_EPSILON: float = 0.005

@export_category("References")
@export var camera: Camera2D
## Supplies the trailing edge to frame against. Leaving it empty degrades to a
## plain timed zoom rather than failing the opening.
@export var arrival_sequence: ArrivalIntroSequence

@export_category("Framing")
## The title shot's zoom. What limits it is how much world there is to look at:
## at 0.40 the frame is 2880 px wide, against terrain that is 3072 px wide and
## grass bands drawn wider still. Pulling back further than the world is wide
## puts its own left and right edges in shot as hard cuts against the sky, so
## terrain_width_cells and both grass band region_rects have to grow with this.
@export_range(0.2, 1.0, 0.01) var menu_zoom: float = 0.40
## Where the shot has to land: the framing every authored gameplay coordinate
## is measured against.
@export_range(0.5, 2.0, 0.01) var gameplay_zoom: float = 1.0
## How long the zoom would take on its own, measured from the moment the bus is
## first fully framed. Kept shorter than the rest of the bus's drive on purpose:
## the cap holds it back, so this is the speed the shot closes at once the bus
## stops limiting it, not the length of the transition.
@export_range(0.1, 6.0, 0.05) var zoom_in_seconds: float = 0.8
## Viewport pixels kept clear behind the bus, so its trailing edge never sits
## exactly on the frame edge while the camera is still moving.
@export_range(0.0, 96.0, 1.0) var bus_frame_margin_px: float = 12.0
## Longest the shot will wait for the bus before closing on its own. Without it
## a bus that never fits the frame would hold the title framing forever and the
## letterbox would never open.
@export_range(0.5, 12.0, 0.5) var maximum_bus_hold_seconds: float = 4.0
## How hard the camera chases the framing the bus allows. The cap itself jumps
## straight to the bus's own speed the moment it takes hold, so following it
## directly would snap the shot from still to moving in one frame. Trailing it
## with an eased approach starts that motion from rest instead, and trailing a
## limit only ever leaves more of the bus in frame, never less. Lower is looser.
@export_range(0.5, 20.0, 0.1) var zoom_follow_rate: float = 3.5

var _is_active: bool = false
var _has_settled: bool = false
var _bus_has_been_framed: bool = false
var _progress: float = 0.0
var _hold_seconds: float = 0.0
var _reached_zoom: float = 1.0
var _zoom_in_requested: bool = false


## Stays awake while the tree is paused and sleeps until the opening asks.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


## Holds the wide title framing until the player starts a run.
func apply_menu_framing() -> void:
	if camera == null:
		push_error("OpeningShotCamera requires its authored camera.")
		return
	_is_active = true
	_has_settled = false
	_bus_has_been_framed = false
	_progress = 0.0
	_hold_seconds = 0.0
	_reached_zoom = minf(menu_zoom, gameplay_zoom)
	_write_zoom()
	if _zoom_in_requested:
		set_process(true)


## Starts closing the shot onto the bus. Safe to call on the same frame the
## title shot is staged, so the menu never has to know which ran first.
func start_zoom_in() -> void:
	_zoom_in_requested = true
	if _is_active and not _has_settled:
		set_process(true)


## Holds the title framing until the bus fits inside it, then eases in under
## whatever cap the bus's trailing edge allows.
func _process(delta: float) -> void:
	var bus_zoom_cap := _get_bus_zoom_cap()
	if not _bus_has_been_framed:
		_hold_seconds += delta
		if (
			bus_zoom_cap < _reached_zoom
			and _hold_seconds < maximum_bus_hold_seconds
		):
			# Held, not idle. Starting a run resets it, and the reset hands the
			# camera back to its gameplay rest zoom; without re-asserting here
			# the title shot would snap to gameplay framing for the whole hold.
			_write_zoom()
			return
		_bus_has_been_framed = true
	_progress = minf(
		_progress + delta / maxf(zoom_in_seconds, 0.01),
		1.0
	)
	var eased := lerpf(
		minf(menu_zoom, gameplay_zoom),
		gameplay_zoom,
		smoothstep(0.0, 1.0, _progress)
	)
	# Frame-rate independent approach: the same curve at any delta.
	var allowed := minf(eased, bus_zoom_cap)
	_reached_zoom = maxf(
		_reached_zoom,
		lerpf(
			_reached_zoom,
			allowed,
			1.0 - exp(-maxf(zoom_follow_rate, 0.01) * delta)
		)
	)
	_write_zoom()
	# An eased approach closes on its target without ever arriving, so the last
	# hair of the zoom is snapped rather than waited on.
	if (
		_progress >= 1.0
		and _reached_zoom >= gameplay_zoom - _SETTLE_EPSILON
	):
		release()


## Hands the camera back at exactly the authored gameplay framing.
func release() -> void:
	set_process(false)
	_is_active = false
	_reached_zoom = gameplay_zoom
	_write_zoom()
	if _has_settled:
		return
	_has_settled = true
	framing_settled.emit()


## Reports whether the shot has finished closing onto gameplay framing.
func is_settled() -> bool:
	return _has_settled


## Suspends until the shot has landed, or returns immediately if it already has.
func wait_until_settled() -> void:
	if _has_settled:
		return
	await framing_settled


## Returns the tightest zoom that still keeps the bus's trailing edge in frame,
## or INF when there is nothing to frame against, which degrades the shot to a
## plain timed zoom instead of stalling it.
func _get_bus_zoom_cap() -> float:
	if arrival_sequence == null or camera == null:
		return INF
	var rear_edge_x := arrival_sequence.get_bus_rear_edge_x()
	if is_inf(rear_edge_x):
		return INF
	var required_half_width := (
		rear_edge_x
		+ bus_frame_margin_px
		- camera.global_position.x
	)
	if required_half_width <= 0.0:
		return INF
	return (
		get_viewport().get_visible_rect().size.x
		* 0.5
		/ required_half_width
	)


func _write_zoom() -> void:
	if camera == null:
		return
	camera.zoom = Vector2(_reached_zoom, _reached_zoom)
