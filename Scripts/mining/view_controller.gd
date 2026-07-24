class_name ViewController
extends Node

## How it works:
## - target_view_y is the authoritative terrain row beneath the miner.
## - _current_miner_y accelerates toward it when a hit opens a gap.
## - Smooth mode eases after the miner and closes its lag after contact.
## - Chunk mode holds one page until the miner crosses its halfway point.
## - Review mode moves the view only; returning uses its own fast free fall.
## The invariant is that screen offset always equals miner row minus view row.

signal landing_reached(mining_y: int)
signal review_started
signal miner_view_reached
signal miner_screen_offset_changed(screen_offset_y: float)

enum ViewMode {
	FOLLOWING_MINER,
	REVIEWING,
	RETURNING,
}

@export var config: MiningConfig
@export var terrain_manager: TerrainManager

## Terrain row currently presented at the fixed mining-face screen position.
var current_view_y: float
## Latest supporting terrain row resolved by MiningController.
var target_view_y: float
## Presentation-only miner row; gameplay depth remains owned by GameState.
var _current_miner_y: float
## Downward row velocity retained across frames and consecutive openings.
var _mining_fall_velocity: float = 0.0
var _review_target_y: float
var _return_velocity: float = 0.0
var _last_landing_y: int
var _view_mode: ViewMode = ViewMode.FOLLOWING_MINER
var _last_miner_screen_offset: float = NAN
var _is_encounter_focus_active: bool = false


## Starts the view at the ground surface.
func _ready() -> void:
	current_view_y = float(config.initial_surface_row)
	target_view_y = current_view_y
	_current_miner_y = current_view_y
	_review_target_y = current_view_y
	_last_landing_y = config.initial_surface_row
	terrain_manager.set_view_y(current_view_y)


## Advances the active follow, review, or free-fall movement.
func _process(delta: float) -> void:
	if not _is_encounter_focus_active:
		match _view_mode:
			ViewMode.FOLLOWING_MINER:
				_follow_miner(delta)
			ViewMode.REVIEWING:
				_move_review_view(delta)
			ViewMode.RETURNING:
				_fall_to_miner(delta)
	terrain_manager.set_view_y(current_view_y)
	_publish_miner_screen_offset()


## Finishes camera catch-up before an encounter dialogue covers the screen.
func focus_miner_for_encounter() -> void:
	_is_encounter_focus_active = true
	current_view_y = target_view_y
	_current_miner_y = target_view_y
	_review_target_y = target_view_y
	_mining_fall_velocity = 0.0
	_return_velocity = 0.0
	_view_mode = ViewMode.FOLLOWING_MINER
	terrain_manager.set_view_y(current_view_y)
	_publish_miner_screen_offset()


## Returns camera movement to the selected smooth or chunked mining style.
func release_encounter_focus() -> void:
	_is_encounter_focus_active = false
	if config.mining_camera_style == MiningConfig.MiningCameraStyle.CHUNK_SNAP:
		current_view_y = _get_chunk_camera_y(target_view_y)
		terrain_manager.set_view_y(current_view_y)
		_publish_miner_screen_offset()


## Publishes the miner's screen displacement from one coordinate conversion.
func _publish_miner_screen_offset() -> void:
	# One conversion path serves both physical mining falls and detached
	# review, preventing the rig and terrain from using different depth scales.
	var miner_world_y := (
		_current_miner_y
		if _view_mode == ViewMode.FOLLOWING_MINER
		else target_view_y
	)
	var miner_screen_offset := (
		miner_world_y - current_view_y
	) * float(config.terrain_cell_world_size)
	if not is_equal_approx(
		miner_screen_offset,
		_last_miner_screen_offset
	):
		_last_miner_screen_offset = miner_screen_offset
		miner_screen_offset_changed.emit(miner_screen_offset)


## Sets the terrain row the normal view should follow.
func follow_mining_y(mining_y: int) -> void:
	target_view_y = float(mining_y)


## Moves the detached view toward earlier or later visited terrain.
func scroll_review(direction: int) -> void:
	var safe_direction := clampi(direction, -1, 1)
	if safe_direction == 0 or _view_mode == ViewMode.RETURNING:
		return
	if (
		_view_mode == ViewMode.FOLLOWING_MINER
		and safe_direction > 0
	):
		return
	if _view_mode == ViewMode.FOLLOWING_MINER:
		var miner_has_landed := is_equal_approx(
			_current_miner_y,
			target_view_y
		)
		if (
			config.mining_camera_style
				== MiningConfig.MiningCameraStyle.CHUNK_SNAP
		):
			if not miner_has_landed:
				return
		elif not is_equal_approx(current_view_y, target_view_y):
			return
		_current_miner_y = target_view_y
		_view_mode = ViewMode.REVIEWING
		_review_target_y = current_view_y
		review_started.emit()

	_review_target_y = clampf(
		_review_target_y
			+ float(
				safe_direction
				* config.review_scroll_rows_per_step
			),
		float(config.initial_surface_row),
		target_view_y
	)


## Starts an accelerating fall back to the miner's current depth.
func return_to_miner() -> void:
	if _view_mode != ViewMode.REVIEWING:
		return
	_view_mode = ViewMode.RETURNING
	_return_velocity = 0.0


## Reports whether the camera is detached from the miner.
func is_reviewing() -> bool:
	return _view_mode != ViewMode.FOLLOWING_MINER


## Falls through the complete mined gap, then recenters after landing.
func _follow_miner(delta: float) -> void:
	if _current_miner_y < target_view_y:
		_mining_fall_velocity = minf(
			_mining_fall_velocity
				+ config.mining_fall_gravity * delta,
			config.mining_max_fall_speed
		)
		_current_miner_y = minf(
			_current_miner_y
				+ _mining_fall_velocity * delta,
			target_view_y
		)
		if is_equal_approx(_current_miner_y, target_view_y):
			_current_miner_y = target_view_y
			_mining_fall_velocity = 0.0
			_report_mining_landing()

		if (
			config.mining_camera_style
				== MiningConfig.MiningCameraStyle.CHUNK_SNAP
		):
			current_view_y = _get_chunk_camera_y(_current_miner_y)
		else:
			# Follow the physical miner rather than the resolved floor. This
			# frame-rate-independent lag preserves downward screen travel.
			var follow_weight := (
				1.0
				- exp(-config.mining_camera_follow_speed * delta)
			)
			current_view_y = lerpf(
				current_view_y,
				_current_miner_y,
				follow_weight
			)
		return
	if _current_miner_y > target_view_y:
		_current_miner_y = target_view_y
		_mining_fall_velocity = 0.0
		_report_mining_landing()

	if (
		config.mining_camera_style
			== MiningConfig.MiningCameraStyle.CHUNK_SNAP
	):
		current_view_y = _get_chunk_camera_y(_current_miner_y)
		return

	# Once supported, finish the smooth camera motion without snapping.
	current_view_y = move_toward(
		current_view_y,
		target_view_y,
		config.landing_recenter_speed * delta
	)
	if not is_equal_approx(current_view_y, target_view_y):
		return
	current_view_y = target_view_y


## Emits one landing after the presentation miner reaches its supporting row.
func _report_mining_landing() -> void:
	var landing_y := roundi(target_view_y)
	if landing_y == _last_landing_y:
		return
	_last_landing_y = landing_y
	landing_reached.emit(landing_y)


## Moves the review camera toward the most recent wheel target.
func _move_review_view(delta: float) -> void:
	var remaining_distance := absf(
		_review_target_y - current_view_y
	)
	var speed_weight := smoothstep(
		0.0,
		config.review_scroll_acceleration_distance,
		remaining_distance
	)
	var scroll_speed := lerpf(
		config.review_scroll_close_speed,
		config.review_scroll_speed,
		speed_weight
	)
	current_view_y = move_toward(
		current_view_y,
		_review_target_y,
		scroll_speed * delta
	)
	if (
		is_equal_approx(current_view_y, target_view_y)
		and is_equal_approx(_review_target_y, target_view_y)
	):
		_finish_return_to_miner()


## Accelerates the detached camera until it reaches the miner.
func _fall_to_miner(delta: float) -> void:
	var return_view_y := target_view_y
	if (
		config.mining_camera_style
			== MiningConfig.MiningCameraStyle.CHUNK_SNAP
	):
		return_view_y = _get_chunk_camera_y(target_view_y)
	_return_velocity = minf(
		_return_velocity + config.return_fall_gravity * delta,
		config.return_max_fall_speed
	)
	current_view_y = minf(
		current_view_y + _return_velocity * delta,
		return_view_y
	)
	if current_view_y >= return_view_y:
		_finish_return_to_miner()


## Reattaches the camera and reports that mining can resume.
func _finish_return_to_miner() -> void:
	current_view_y = (
		_get_chunk_camera_y(target_view_y)
		if config.mining_camera_style
			== MiningConfig.MiningCameraStyle.CHUNK_SNAP
		else target_view_y
	)
	_current_miner_y = target_view_y
	_review_target_y = target_view_y
	_mining_fall_velocity = 0.0
	_return_velocity = 0.0
	_view_mode = ViewMode.FOLLOWING_MINER
	miner_view_reached.emit()


## Returns the fixed page selected by crossing a chunk's halfway point.
func _get_chunk_camera_y(miner_y: float) -> float:
	var chunk_rows := float(config.chunk_height_cells)
	var descended_rows := maxf(
		miner_y - float(config.initial_surface_row),
		0.0
	)
	var camera_chunk_index := floori(
		descended_rows / chunk_rows + 0.5
	)
	return minf(
		float(config.initial_surface_row)
			+ float(camera_chunk_index) * chunk_rows,
		float(config.get_bottom_surface_row())
	)
