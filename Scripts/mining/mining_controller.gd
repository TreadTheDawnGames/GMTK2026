class_name MiningController
extends Node

## Turns timing results and hammer contact into terrain damage and player depth.

class SwingRequest:
	## Retains one earned strike until its animation reaches the ground.
	var combo: int
	var pickaxe: PickaxeDefinition
	var aim_direction: int
	var power_scale: float
	var width_scale: float
	var speed_scale: float
	var debris_scale: float
	var counts_as_timing_success: bool


	## Captures the tool and modifiers earned by one timing result.
	func _init(
		requested_combo: int,
		requested_pickaxe: PickaxeDefinition,
		requested_aim_direction: int = 0,
		requested_power_scale: float = 1.0,
		requested_width_scale: float = 1.0,
		requested_speed_scale: float = 1.0,
		requested_debris_scale: float = 1.0,
		requested_counts_as_timing_success: bool = true
	) -> void:
		combo = requested_combo
		pickaxe = requested_pickaxe
		aim_direction = clampi(requested_aim_direction, -1, 1)
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

@export var config: MiningConfig
#@export var run_state: RunState
@export var terrain_manager: TerrainManager
@export var view_controller: ViewController
@export var fall_origin: Marker2D

var _equipped_pickaxe: PickaxeDefinition
var _aim_direction: int = 0
var _pending_swing: SwingRequest
var _pending_combo_strength: float = 0.0
var _is_swing_pending: bool = false
var _has_resolved_pending_impact: bool = false
var _is_swing_queue_paused: bool = false
var _queued_swings: Array[SwingRequest] = []


## Starts a swing for a successful timing result or records a miss.
func resolve_attempt(success: bool, resolved_combo: int) -> void:
	var safe_combo := maxi(resolved_combo, 0)
	if GameState.has_reached_bottom:
		return
	if not success:
		GameState.record_failure(safe_combo)
		# A miss stops retained future strikes, but an airborne hit still lands.
		_queued_swings.clear()
		# Keep an active successful swing intact; the timing UI already shows
		# the miss and resets its combo.
		if not _is_swing_pending:
			mine_missed.emit(safe_combo)
		return
	var primary_swing := SwingRequest.new(
		safe_combo,
		_equipped_pickaxe,
		_aim_direction
	)
	if (
		_is_swing_pending
		or _is_swing_queue_paused
	):
		_queued_swings.append(primary_swing)
	else:
		_start_swing(primary_swing)

	# Swift's bonus is tied to the earned timing result and cannot chain itself.
	if (
		_equipped_pickaxe != null
		and _equipped_pickaxe.special_effect
			== PickaxeDefinition.SpecialEffect.RAPID_FOLLOW_UP
	):
		_queued_swings.append(SwingRequest.new(
			safe_combo,
			_equipped_pickaxe,
			_aim_direction,
			_equipped_pickaxe.follow_up_power_scale,
			_equipped_pickaxe.follow_up_width_scale,
			_equipped_pickaxe.follow_up_speed_scale,
			_equipped_pickaxe.follow_up_debris_scale,
			false
		))


## Starts one retained success and waits for its animated contact frame.
func _start_swing(swing: SwingRequest) -> void:
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
		_pickaxe_multiplier(
			swing.pickaxe,
			&"swing_speed_multiplier"
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
			* _pickaxe_multiplier(
				_pending_swing.pickaxe,
				&"power_multiplier"
			)
			* _pending_swing.power_scale
		),
		1
	)
	var requested_half_width_cells := (
		config.base_tunnel_half_width_cells
		+ config.combo_tunnel_half_width_cells_per_step * combo_steps
	)
	requested_half_width_cells = maxi(
		roundi(
			float(requested_half_width_cells)
			* _pickaxe_multiplier(
				_pending_swing.pickaxe,
				&"width_multiplier"
			)
			* _pending_swing.width_scale
		),
		0
	)
	var impact_cell_x := terrain_manager.screen_x_to_terrain_cell_x(
		impact_screen_position.x
	)
	var fall_cell := Vector2i(
		terrain_manager.screen_x_to_terrain_cell_x(
			fall_origin.global_position.x
		),
		GameState.mining_y
	)
	# Presentation receives this before TerrainManager emits damage, so every
	# stamp from the primary hit and its special effect shares one combo gate.
	dig_presentation_started.emit(capped_combo)
	var dig_result := terrain_manager.dig_tunnel(
		fall_cell,
		requested_depth_rows,
		requested_half_width_cells,
		impact_cell_x,
		_pending_swing.aim_direction,
		requested_half_width_cells
	)
	var surface_after_primary_hit_y := terrain_manager.find_surface_row(
		fall_cell.x,
		GameState.mining_y
	)
	var crossed_open_chamber := (
		surface_after_primary_hit_y
		> fall_cell.y + requested_depth_rows
	)
	if (
		_pending_swing.pickaxe != null
		and _pending_swing.pickaxe.special_effect
			== PickaxeDefinition.SpecialEffect.AFTERSHOCK
		and _pending_swing.pickaxe.aftershock_depth_rows > 0
		and dig_result.cells_removed > 0
		and not crossed_open_chamber
	):
		var aftershock_result := terrain_manager.dig_tunnel(
			Vector2i(fall_cell.x, surface_after_primary_hit_y),
			_pending_swing.pickaxe.aftershock_depth_rows,
			requested_half_width_cells,
			-1,
			_pending_swing.aim_direction,
			requested_half_width_cells
		)
		dig_result.absorb(aftershock_result)
	elif (
		_pending_swing.pickaxe != null
		and _pending_swing.pickaxe.special_effect
			== PickaxeDefinition.SpecialEffect.BRANCHING_LIGHTNING
		and dig_result.cells_removed > 0
		and not crossed_open_chamber
	):
		var lightning_result := terrain_manager.dig_branching_lightning(
			Vector2i(fall_cell.x, surface_after_primary_hit_y),
			_pending_swing.pickaxe.lightning_depth_rows,
			_pending_swing.pickaxe.lightning_branch_count,
			_pending_swing.pickaxe.lightning_branch_length_cells
		)
		dig_result.absorb(lightning_result)
	var new_mining_y := terrain_manager.find_surface_row(
		fall_cell.x,
		GameState.mining_y
	)
	var depth_gained := maxi(new_mining_y - GameState.mining_y, 0)
	GameState.record_success(
		depth_gained,
		new_mining_y,
		_pending_swing.combo,
		_pending_swing.counts_as_timing_success
	)
	view_controller.follow_mining_y(GameState.mining_y)
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
		_pickaxe_multiplier(
			_pending_swing.pickaxe,
			&"debris_multiplier"
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
	if GameState.has_reached_bottom:
		_queued_swings.clear()
		return
	_try_start_queued_swing()


## Pauses retained hits during dialogue floors and resumes them afterward.
func set_swing_queue_paused(is_paused: bool) -> void:
	_is_swing_queue_paused = is_paused
	if is_paused:
		return
	_try_start_queued_swing()


## Applies the pickaxe modifiers used by future swings.
func set_equipped_pickaxe(definition: PickaxeDefinition) -> void:
	_equipped_pickaxe = definition


## Selects the side captured by the next successful timing result.
func set_aim_direction(direction: int) -> void:
	_aim_direction = clampi(direction, -1, 1)


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
		or GameState.has_reached_bottom
	):
		return
	_start_swing(_queued_swings.pop_front())


## Returns one strike-pickaxe modifier or the neutral value.
func _pickaxe_multiplier(
	pickaxe: PickaxeDefinition,
	property_name: StringName
) -> float:
	if pickaxe == null:
		return 1.0
	return maxf(float(pickaxe.get(property_name)), 0.0)
