class_name MiningController
extends Node

## Turns timing results and hammer contact into terrain damage and player depth.

class SwingRequest:
	## Retains one earned strike until its animation reaches the ground.
	var combo: int
	var pickaxes: Array[PickaxeDefinition]
	var power_scale: float
	var width_scale: float
	var speed_scale: float
	var debris_scale: float
	var counts_as_timing_success: bool
	var path_direction: int = 1
	var target_cell_x: int


	## Captures the tool and modifiers earned by one timing result.
	func _init(
		requested_combo: int,
		requested_pickaxes: Array[PickaxeDefinition],
		requested_power_scale: float = 1.0,
		requested_width_scale: float = 1.0,
		requested_speed_scale: float = 1.0,
		requested_debris_scale: float = 1.0,
		requested_counts_as_timing_success: bool = true
	) -> void:
		combo = requested_combo
		# Progression replaces rather than mutates this array, so queued hits
		# retain a stable <=10-item snapshot without another per-hit allocation.
		pickaxes = requested_pickaxes
		power_scale = requested_power_scale
		width_scale = requested_width_scale
		speed_scale = requested_speed_scale
		debris_scale = requested_debris_scale
		counts_as_timing_success = requested_counts_as_timing_success


## Reports the terrain and depth changed by a completed hit.
signal mine_resolved(
	depth_gained: int,
	cells_removed: int,
	combo: int,
	combo_strength: float
)
## Reports a timing miss without starting a mining animation.
signal mine_missed(combo: int)
## Requests the miner's swing animation for an earned hit.
signal swing_requested(
	combo: int,
	combo_strength: float,
	swing_speed_multiplier: float
)
## Reports combo before synchronous terrain damage chooses its layer masks.
signal dig_presentation_started(combo: int)
## Requests impact presentation at the hammer contact point.
signal impact_resolved(
	screen_position: Vector2,
	cells_removed: int,
	combo_strength: float,
	debris_multiplier: float,
	swing_side: int
)
## Requests the hit's downward distance at the hammer contact point.
signal dig_number_requested(
	screen_position: Vector2,
	depth_gained: int,
	combo: int,
	combo_strength: float
)
## Faces the miner toward the automatically selected tunnel direction.
signal path_direction_changed(direction: int)

@export var config: MiningConfig
@export var terrain_manager: TerrainManager
@export var view_controller: ViewController

@onready var _game_state: RunState = RunState.get_global(self)

# Authored progression contains exactly ten definitions; merchant grants only
# replace this bounded snapshot and never grow it per hit.
var _active_pickaxes: Array[PickaxeDefinition] = []
var _path_direction: int = 1
var _pending_swing: SwingRequest
var _pending_combo_strength: float = 0.0
var _is_swing_pending: bool = false
var _has_resolved_pending_impact: bool = false
var _is_swing_queue_paused: bool = false
var _queued_swings: Array[SwingRequest] = []


## Starts a swing for a successful timing result or records a miss.
func resolve_attempt(success: bool, resolved_combo: int) -> void:
	var safe_combo := maxi(resolved_combo, 0)
	if _game_state.has_reached_bottom:
		return
	if not success:
		_game_state.record_failure(safe_combo)
		# A miss stops retained future strikes, but an airborne hit still lands.
		_queued_swings.clear()
		# Keep an active successful swing intact; the timing UI already shows
		# the miss and resets its combo.
		if not _is_swing_pending:
			mine_missed.emit(safe_combo)
		return
	var primary_swing := SwingRequest.new(
		safe_combo,
		_active_pickaxes
	)
	if (
		_is_swing_pending
		or _is_swing_queue_paused
	):
		_queued_swings.append(primary_swing)
	else:
		_start_swing(primary_swing)

	# Every owned rapid-follow-up pickaxe adds one bonus swing. Bonus swings
	# retain the complete stack but cannot recursively create more swings.
	for definition in _active_pickaxes:
		if (
			definition == null
			or definition.special_effect
				!= PickaxeDefinition.SpecialEffect.RAPID_FOLLOW_UP
		):
			continue
		_queued_swings.append(SwingRequest.new(
			safe_combo,
			_active_pickaxes,
			definition.follow_up_power_scale,
			definition.follow_up_width_scale,
			definition.follow_up_speed_scale,
			definition.follow_up_debris_scale,
			false
		))


## Starts one retained success and waits for its animated contact frame.
func _start_swing(swing: SwingRequest) -> void:
	var center_cell_x := config.terrain_width_cells / 2
	var requested_half_width_cells := (
		_get_requested_half_width_cells(swing)
	)
	var available_half_span := (
		center_cell_x - requested_half_width_cells - 1
	)
	if terrain_manager.encounter_config != null:
		available_half_span = mini(
			available_half_span,
			terrain_manager.encounter_config.chamber_width_cells / 2
				- requested_half_width_cells
				- 1
		)
	var safe_half_span := maxi(
		mini(config.snake_half_span_cells, available_half_span),
		0
	)
	var left_turn_cell_x := center_cell_x - safe_half_span
	var right_turn_cell_x := center_cell_x + safe_half_span
	if _game_state.mining_x >= right_turn_cell_x:
		_path_direction = -1
	elif _game_state.mining_x <= left_turn_cell_x:
		_path_direction = 1
	swing.path_direction = _path_direction
	var horizontal_step_cells := mini(
		config.snake_horizontal_step_cells,
		maxi(requested_half_width_cells, 1)
	)
	swing.target_cell_x = clampi(
		_game_state.mining_x
			+ swing.path_direction * horizontal_step_cells,
		left_turn_cell_x,
		right_turn_cell_x
	)
	path_direction_changed.emit(swing.path_direction)
	_pending_swing = swing
	_pending_combo_strength = clampf(
		float(swing.combo) / float(config.maximum_effect_combo),
		0.0,
		1.0
	)
	_is_swing_pending = true
	_has_resolved_pending_impact = false
	swing_requested.emit(
		swing.combo,
		_pending_combo_strength,
		_stack_multiplier(
			swing.pickaxes,
			&"swing_speed_multiplier",
			config.maximum_stack_swing_speed_multiplier
		) * swing.speed_scale
	)


## Breaks terrain where the animated hammer reaches its contact keyframe.
func resolve_impact(
	impact_screen_position: Vector2,
	swing_side: int = 1
) -> void:
	if (
		not _is_swing_pending
		or _has_resolved_pending_impact
	):
		return
	_has_resolved_pending_impact = true

	var capped_combo := mini(
		_pending_swing.combo,
		config.maximum_effect_combo
	)
	var combo_steps := maxi(capped_combo - 1, 0)
	var requested_depth_rows := (
		config.base_mine_depth_rows
		+ config.combo_mine_depth_rows_per_step * combo_steps
	)
	requested_depth_rows = maxi(
		roundi(
			float(requested_depth_rows)
			* _stack_multiplier(
				_pending_swing.pickaxes,
				&"power_multiplier",
				config.maximum_stack_power_multiplier
			)
			* _pending_swing.power_scale
		),
		1
	)
	var requested_half_width_cells := (
		_get_requested_half_width_cells(_pending_swing)
	)
	var impact_cell_x := terrain_manager.screen_x_to_terrain_cell_x(
		impact_screen_position.x
	)
	var fall_cell := Vector2i(
		_game_state.mining_x,
		_game_state.mining_y
	)
	# Presentation receives this before TerrainManager emits damage, so every
	# stamp from the primary hit and its special effect shares one combo gate.
	dig_presentation_started.emit(capped_combo)
	var dig_result := terrain_manager.dig_tunnel(
		fall_cell,
		requested_depth_rows,
		requested_half_width_cells,
		impact_cell_x,
		_pending_swing.target_cell_x
	)
	var surface_after_primary_hit: Vector2i = (
		terrain_manager.find_tunnel_surface_cell(
			fall_cell,
			_pending_swing.target_cell_x,
			requested_depth_rows
		)
	)
	var surface_after_primary_hit_y: int = surface_after_primary_hit.y
	var crossed_open_chamber := (
		surface_after_primary_hit_y
		> fall_cell.y + requested_depth_rows
	)
	if dig_result.cells_removed > 0 and not crossed_open_chamber:
		for definition in _pending_swing.pickaxes:
			if (
				definition == null
				or definition.special_effect
					!= PickaxeDefinition.SpecialEffect.AFTERSHOCK
				or definition.aftershock_depth_rows <= 0
			):
				continue
			var aftershock_result := terrain_manager.dig_tunnel(
				Vector2i(
					_pending_swing.target_cell_x,
					surface_after_primary_hit_y
				),
				definition.aftershock_depth_rows,
				requested_half_width_cells,
				-1,
				_pending_swing.target_cell_x
			)
			dig_result.absorb(aftershock_result)
			surface_after_primary_hit_y = terrain_manager.find_surface_row(
				_pending_swing.target_cell_x,
				_game_state.mining_y
			)
		for definition in _pending_swing.pickaxes:
			if (
				definition == null
				or definition.special_effect
					!= PickaxeDefinition.SpecialEffect.BRANCHING_LIGHTNING
			):
				continue
			var lightning_result := terrain_manager.dig_branching_lightning(
				Vector2i(
					_pending_swing.target_cell_x,
					surface_after_primary_hit_y
				),
				definition.lightning_depth_rows,
				definition.lightning_branch_count,
				definition.lightning_branch_length_cells
			)
			dig_result.absorb(lightning_result)
	var new_mining_position: Vector2i = (
		terrain_manager.find_tunnel_surface_cell(
			fall_cell,
			_pending_swing.target_cell_x,
			requested_depth_rows
		)
	)
	var new_mining_y: int = new_mining_position.y
	var depth_gained := maxi(new_mining_y - _game_state.mining_y, 0)
	_game_state.record_success(
		depth_gained,
		new_mining_position,
		_pending_swing.combo,
		_pending_swing.counts_as_timing_success
	)
	view_controller.follow_mining_position(
		Vector2i(_game_state.mining_x, _game_state.mining_y)
	)
	mine_resolved.emit(
		depth_gained,
		dig_result.cells_removed,
		_pending_swing.combo,
		_pending_combo_strength
	)
	impact_resolved.emit(
		impact_screen_position,
		dig_result.cells_removed,
		_pending_combo_strength,
		_stack_multiplier(
			_pending_swing.pickaxes,
			&"debris_multiplier",
			config.maximum_stack_debris_multiplier
		) * _pending_swing.debris_scale,
		signi(swing_side) if swing_side != 0 else 1
	)
	dig_number_requested.emit(
		impact_screen_position,
		depth_gained,
		_pending_swing.combo,
		_pending_combo_strength
	)


## Starts the next retained success after the current follow-through ends.
func finish_swing() -> void:
	if not _is_swing_pending:
		return
	_is_swing_pending = false
	_has_resolved_pending_impact = false
	_pending_swing = null
	if _game_state.has_reached_bottom:
		_queued_swings.clear()
		return
	_try_start_queued_swing()


## Pauses retained hits during dialogue floors and resumes them afterward.
func set_swing_queue_paused(is_paused: bool) -> void:
	_is_swing_queue_paused = is_paused
	if is_paused:
		return
	_try_start_queued_swing()


## Replaces the cumulative snapshot captured by future earned swings.
func set_active_pickaxes(definitions: Array[PickaxeDefinition]) -> void:
	_active_pickaxes = definitions.duplicate()


## Reports whether the camera may leave without interrupting a strike.
func can_start_view_review() -> bool:
	return (
		not _is_swing_pending
		and not _is_swing_queue_paused
		and _queued_swings.is_empty()
	)


## Starts the next earned hit when animation and dialogue allow it.
func _try_start_queued_swing() -> void:
	if (
		_is_swing_queue_paused
		or _is_swing_pending
		or _queued_swings.is_empty()
		or _game_state.has_reached_bottom
	):
		return
	_start_swing(_queued_swings.pop_front())


## Restores the initial rightward leg and drops stale retained swings.
func _on_run_reset() -> void:
	_path_direction = 1
	_pending_swing = null
	_is_swing_pending = false
	_has_resolved_pending_impact = false
	_queued_swings.clear()


## Resolves the connected tunnel radius for planning and impact damage.
func _get_requested_half_width_cells(swing: SwingRequest) -> int:
	var capped_combo := mini(swing.combo, config.maximum_effect_combo)
	var combo_steps := maxi(capped_combo - 1, 0)
	var requested_half_width_cells := (
		config.base_tunnel_half_width_cells
		+ config.combo_tunnel_half_width_cells_per_step * combo_steps
	)
	return maxi(
		roundi(
			float(requested_half_width_cells)
			* _stack_multiplier(
				swing.pickaxes,
				&"width_multiplier",
				config.maximum_stack_width_multiplier
			)
			* swing.width_scale
		),
		0
	)


## Adds each definition's delta from neutral and caps cumulative run power.
func _stack_multiplier(
	pickaxes: Array[PickaxeDefinition],
	property_name: StringName,
	maximum_multiplier: float
) -> float:
	var combined_multiplier := 1.0
	for definition in pickaxes:
		if definition == null:
			continue
		combined_multiplier += (
			float(definition.get(property_name)) - 1.0
		)
	return clampf(
		combined_multiplier,
		0.1,
		maxf(maximum_multiplier, 0.1)
	)
