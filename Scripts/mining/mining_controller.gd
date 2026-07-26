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
	var start_cell: Vector2i
	var depth_rows: int
	var half_width_cells: int


	## Captures the tool and modifiers earned by one timing result.
	func _init(
		requested_combo: int,
		requested_pickaxes: Array[PickaxeDefinition],
		requested_path_direction: int = 0,
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
		path_direction = clampi(requested_path_direction, -1, 1)


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
	swing_speed_multiplier: float,
	path_direction: int
)
## Reports combo before synchronous terrain damage chooses its layer masks.
signal dig_presentation_started(combo: int)
## Starts a bounded prediction batch. Exact swings retain any candidate images
## that already match; a regenerated target set replaces obsolete candidates.
signal dig_visuals_preparation_started(keep_completed: bool)
## Gives terrain presentation the successful swing's deterministic primary hit
## during wind-up. This prepares mask transforms only; impact still owns damage,
## particles, texture publication, and every player-visible consequence.
signal dig_visuals_preparation_requested(
	start_cell: Vector2i,
	depth_rows: int,
	half_width_cells: int,
	target_cell_x: int,
	combo: int
)
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
	combo_strength: float,
	swing_side: int
)
@export var config: MiningConfig
@export var terrain_manager: TerrainManager
@export var view_controller: ViewController

var _game_state: RunState

# Narrative pickaxe gifts replace this bounded snapshot. Encounter progression
# overrides their legacy gameplay modifiers during the production run.
var _active_pickaxes: Array[PickaxeDefinition] = []
var _progression_level: EncounterProgressionLevel
var _path_direction: int = 1
var _pending_swing: SwingRequest
var _pending_combo_strength: float = 0.0
var _is_swing_pending: bool = false
var _has_resolved_pending_impact: bool = false
var _is_swing_queue_paused: bool = false
var _latest_candidate_combo: int = 1
var _latest_candidate_directions := PackedInt32Array()
# Widened, straightened descent authored by the credits band. Zero and a
# negative span mean ordinary mining, so every depth outside that band resolves
# its swing exactly as it did before the inscriptions existed.
var _inscription_minimum_half_width_cells: int = 0
var _inscription_maximum_snake_half_span_cells: int = -1
# Each success adds at most its primary request and one authored double hit.
# Swing completion pops requests; a miss or run reset clears the remainder.
var _queued_swings: Array[SwingRequest] = []


## Supplies the authoritative run model at the composition boundary.
func set_run_state(run_state: RunState) -> void:
	_game_state = run_state


## Widens and straightens the shaft while authored inscriptions are passing.
## A swing still costs the player exactly what it always did: this raises the
## floor under the resolved radius and narrows the snake's turn span, so the
## opening is wide enough to read a name through and stays centered on it.
## Zero half-width with a negative span restores ordinary mining.
func set_inscription_dig_band(
	minimum_half_width_cells: int,
	maximum_snake_half_span_cells: int
) -> void:
	_inscription_minimum_half_width_cells = maxi(
		minimum_half_width_cells,
		0
	)
	_inscription_maximum_snake_half_span_cells = (
		maximum_snake_half_span_cells
	)


## Starts a swing for a successful timing result or records a miss.
func resolve_attempt(
	success: bool,
	resolved_combo: int,
	hit_direction: int = 0
) -> void:
	var safe_combo := maxi(resolved_combo, 0)
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
		_active_pickaxes,
		hit_direction
	)
	if (
		_is_swing_pending
		or _is_swing_queue_paused
	):
		_queued_swings.append(primary_swing)
	else:
		_start_swing(primary_swing)

	# Encounter progression owns the production run's double-hit rule. The
	# pickaxe loop remains only as a fallback for isolated legacy previews.
	if _progression_level != null and _progression_level.double_hit:
		_queued_swings.append(SwingRequest.new(
			safe_combo,
			_active_pickaxes,
			hit_direction,
			1.0,
			1.0,
			1.0,
			1.0,
			false
		))
	elif _progression_level == null:
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
				hit_direction,
				definition.follow_up_power_scale,
				definition.follow_up_width_scale,
				definition.follow_up_speed_scale,
				definition.follow_up_debris_scale,
				false
			))


## Starts one retained success and waits for its animated contact frame.
func _start_swing(swing: SwingRequest) -> void:
	var requested_half_width_cells := (
		_get_requested_half_width_cells(swing)
	)
	var path_plan := _get_swing_path_plan(
		swing,
		requested_half_width_cells
	)
	_path_direction = path_plan.x
	swing.path_direction = path_plan.x
	swing.target_cell_x = path_plan.y
	swing.start_cell = Vector2i(
		_game_state.mining_x,
		_game_state.mining_y
	)
	swing.depth_rows = _get_requested_depth_rows(swing)
	swing.half_width_cells = requested_half_width_cells
	_pending_swing = swing
	_pending_combo_strength = clampf(
		float(swing.combo) / float(config.maximum_effect_combo),
		0.0,
		1.0
	)
	_is_swing_pending = true
	_has_resolved_pending_impact = false
	# Once timing succeeds, the target column and impact dimensions cannot change
	# before the authored contact frame. Spend that wind-up preparing the dense
	# stamp, while keeping the logical terrain and particles untouched.
	dig_visuals_preparation_started.emit(true)
	dig_visuals_preparation_requested.emit(
		swing.start_cell,
		swing.depth_rows,
		swing.half_width_cells,
		swing.target_cell_x,
		mini(swing.combo, config.maximum_effect_combo)
	)
	var authored_animation_speed := (
		_progression_level.get_mine_animation_speed_multiplier()
		if _progression_level != null
		else _stack_multiplier(
			swing.pickaxes,
			&"swing_speed_multiplier",
			config.maximum_stack_swing_speed_multiplier
		)
	)
	swing_requested.emit(
		swing.combo,
		_pending_combo_strength,
		authored_animation_speed * swing.speed_scale,
		swing.path_direction
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
	var requested_depth_rows := _pending_swing.depth_rows
	var requested_half_width_cells := _pending_swing.half_width_cells
	# The swing's planned target is the reachable pickaxe contact. The animated
	# marker remains presentation-only because camera movement or a queued swing
	# can briefly place its screen coordinate over terrain the miner cannot reach.
	var impact_cell_x := _pending_swing.target_cell_x
	var fall_cell := _pending_swing.start_cell
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
			requested_depth_rows,
			impact_cell_x
		)
	)
	var surface_after_primary_hit_y: int = surface_after_primary_hit.y
	var crossed_floor_depth: int = -1
	if terrain_manager.encounter_config != null:
		crossed_floor_depth = (
			terrain_manager.encounter_config
			.get_first_crossed_encounter_floor_depth(
				fall_cell.y - config.initial_surface_row,
				surface_after_primary_hit_y - config.initial_surface_row,
				config.total_run_depth
			)
		)
	# A primary hit that opens an encounter chamber has reached its protected
	# floor even when its requested endpoint lies deeper. Starting an aftershock
	# from that surface would destroy the floor the miner must land on.
	if (
		_progression_level == null
		and dig_result.cells_removed > 0
		and crossed_floor_depth < 0
	):
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
			var maximum_crack_count := (
				definition.lightning_max_crack_count
			)
			var maximum_crack_length := (
				definition.lightning_max_crack_length_cells
			)
			var maximum_crack_depth := (
				definition.lightning_max_crack_depth_cells
			)
			# Browser builds keep the same growth curve and layer taper with a
			# smaller bounded mask workload on the impact hot path.
			if OS.has_feature("web"):
				maximum_crack_count = mini(maximum_crack_count, 3)
				maximum_crack_length = mini(maximum_crack_length, 12)
				maximum_crack_depth = mini(maximum_crack_depth, 3)
			var lightning_result := terrain_manager.dig_branching_lightning(
				Vector2i(
					_pending_swing.target_cell_x,
					surface_after_primary_hit_y
				),
				requested_half_width_cells,
				_pending_combo_strength,
				maximum_crack_count,
				maximum_crack_length,
				maximum_crack_depth
			)
			dig_result.absorb(lightning_result)
	var new_mining_position: Vector2i = (
		terrain_manager.find_tunnel_surface_cell(
			fall_cell,
			_pending_swing.target_cell_x,
			requested_depth_rows,
			impact_cell_x
		)
	)
	if (
		crossed_floor_depth < 0
		and terrain_manager.encounter_config != null
	):
		crossed_floor_depth = (
			terrain_manager.encounter_config
			.get_first_crossed_encounter_floor_depth(
				fall_cell.y - config.initial_surface_row,
				new_mining_position.y - config.initial_surface_row,
				config.total_run_depth
			)
		)
	if crossed_floor_depth >= 0:
		new_mining_position.y = mini(
			new_mining_position.y,
			config.initial_surface_row + crossed_floor_depth
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
	var debris_multiplier := (
		1.0
		if _progression_level != null
		else _stack_multiplier(
			_pending_swing.pickaxes,
			&"debris_multiplier",
			config.maximum_stack_debris_multiplier
		)
	)
	impact_resolved.emit(
		impact_screen_position,
		dig_result.cells_removed,
		_pending_combo_strength,
		debris_multiplier * _pending_swing.debris_scale,
		signi(swing_side) if swing_side != 0 else 1
	)
	dig_number_requested.emit(
		impact_screen_position,
		depth_gained,
		_pending_swing.combo,
		_pending_combo_strength,
		signi(swing_side) if swing_side != 0 else 1
	)


## Starts the next retained success after the current follow-through ends.
func finish_swing() -> void:
	if not _is_swing_pending:
		return
	_is_swing_pending = false
	_has_resolved_pending_impact = false
	_pending_swing = null
	_try_start_queued_swing()
	if not _is_swing_pending:
		_prepare_latest_impact_candidates()


## Drops the strike a cinematic interrupted, along with the hits retained behind
## it, so the gate hands mining back in a state that can start a swing again.
##
## A cutscene takes the miner's AnimationPlayer and stops it where it stands, and
## a stopped animation never reports finished, so the swing it interrupted never
## reaches finish_swing. The pending flag then survives the whole conversation:
## the timing bar comes back and still resolves, but every earned hit lands in
## _queued_swings behind a swing that can no longer end, which reads in game as a
## working UI attached to a miner who has stopped digging.
##
## No damage is lost by dropping it. An encounter is scheduled off a depth
## change, which only a resolved impact produces, so the hit that opened the room
## has already done its terrain work by the time the gate is claimed. Anything
## still airborne is a swing the player never sees land.
##
## _pending_swing is deliberately left alone. This is called from inside the
## impact it is interrupting: resolve_impact reaches record_success, the depth
## that produces captures the encounter, the gate claims mining, and control
## comes back here while resolve_impact still has its own emissions to make from
## that same request. Clearing the reference under it crashes the hit that
## earned the cutscene. The next _start_swing replaces it.
func abandon_interrupted_swing() -> void:
	_is_swing_pending = false
	_has_resolved_pending_impact = false
	_queued_swings.clear()


## Pauses retained hits during dialogue floors and resumes them afterward.
func set_swing_queue_paused(is_paused: bool) -> void:
	_is_swing_queue_paused = is_paused
	if is_paused:
		return
	_try_start_queued_swing()


## Reports whether a conversation or camera flow owns the retained-hit gate.
func is_swing_queue_paused() -> bool:
	return _is_swing_queue_paused


## Replaces the cumulative snapshot captured by future earned swings.
func set_active_pickaxes(definitions: Array[PickaxeDefinition]) -> void:
	_active_pickaxes = definitions.duplicate()


## Replaces mining behavior with one complete encounter-authored level.
func set_progression_level(definition: EncounterProgressionLevel) -> void:
	_progression_level = definition


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
	_latest_candidate_combo = 1
	_latest_candidate_directions.clear()
	dig_visuals_preparation_started.emit(false)


## Stores Caspian's up-to-five target outcomes and prepares their unique impact
## directions whenever no already-earned swing owns the prediction cache.
func _on_impact_candidates_changed(
	next_combo: int,
	hit_directions: PackedInt32Array
) -> void:
	var keeps_completed_candidates := _candidate_keys_match(
		next_combo,
		hit_directions
	)
	_latest_candidate_combo = maxi(next_combo, 1)
	_latest_candidate_directions = hit_directions.duplicate()
	if _is_swing_pending or _is_swing_queue_paused:
		return
	_prepare_latest_impact_candidates(keeps_completed_candidates)


## Separates a priority-only reorder from regenerated candidate identities.
func _candidate_keys_match(
	next_combo: int,
	hit_directions: PackedInt32Array
) -> bool:
	var keys_match := (
		maxi(next_combo, 1) == _latest_candidate_combo
		and hit_directions.size() == _latest_candidate_directions.size()
	)
	if keys_match:
		for previous_direction in _latest_candidate_directions:
			if previous_direction not in hit_directions:
				keys_match = false
				break
	return keys_match


## Expands the current target set into bounded terrain-transform candidates.
func _prepare_latest_impact_candidates(
	keep_completed: bool = false
) -> void:
	# Time-to-hit reordering changes urgency, not candidate identity. Preserve
	# finished images across that reorder while replacing unfinished queue work.
	dig_visuals_preparation_started.emit(keep_completed)
	if _latest_candidate_directions.is_empty():
		return
	var start_cell := Vector2i(
		_game_state.mining_x,
		_game_state.mining_y
	)
	for hit_direction in _latest_candidate_directions:
		var swing := SwingRequest.new(
			_latest_candidate_combo,
			_active_pickaxes,
			hit_direction
		)
		var half_width_cells := _get_requested_half_width_cells(swing)
		var path_plan := _get_swing_path_plan(swing, half_width_cells)
		dig_visuals_preparation_requested.emit(
			start_cell,
			_get_requested_depth_rows(swing),
			half_width_cells,
			path_plan.y,
			mini(
				_latest_candidate_combo,
				config.maximum_effect_combo
			)
		)


## Resolves the bounded snake direction and contact column without mutating the
## live path, so up to five timing targets can be evaluated independently.
func _get_swing_path_plan(
	swing: SwingRequest,
	requested_half_width_cells: int
) -> Vector2i:
	var center_cell_x := config.terrain_width_cells / 2
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
	var authored_half_span := config.snake_half_span_cells
	if _inscription_maximum_snake_half_span_cells >= 0:
		authored_half_span = mini(
			authored_half_span,
			_inscription_maximum_snake_half_span_cells
		)
	var safe_half_span := maxi(
		mini(authored_half_span, available_half_span),
		0
	)
	var left_turn_cell_x := center_cell_x - safe_half_span
	var right_turn_cell_x := center_cell_x + safe_half_span
	var resolved_direction := _path_direction
	if _game_state.mining_x >= right_turn_cell_x:
		resolved_direction = -1
	elif _game_state.mining_x <= left_turn_cell_x:
		resolved_direction = 1
	elif swing.path_direction != 0:
		resolved_direction = swing.path_direction
	var horizontal_step_cells := mini(
		config.snake_horizontal_step_cells,
		maxi(requested_half_width_cells, 1)
	)
	var target_cell_x := clampi(
		_game_state.mining_x
			+ resolved_direction * horizontal_step_cells,
		left_turn_cell_x,
		right_turn_cell_x
	)
	return Vector2i(resolved_direction, target_cell_x)


## Resolves the connected tunnel radius for planning and impact damage.
func _get_requested_half_width_cells(swing: SwingRequest) -> int:
	var capped_combo := mini(swing.combo, config.maximum_effect_combo)
	var combo_steps := maxi(capped_combo - 1, 0)
	var combo_added_half_width := (
		config.combo_tunnel_half_width_cells_per_step * combo_steps
	)
	var requested_half_width_cells: int
	if _progression_level != null:
		requested_half_width_cells = _progression_level.scale_impact(
			float(config.base_tunnel_half_width_cells),
			float(combo_added_half_width)
		)
	else:
		requested_half_width_cells = (
			config.base_tunnel_half_width_cells
				+ combo_added_half_width
		)
	var resolved_half_width_cells := maxi(
		roundi(
			float(requested_half_width_cells)
			* (
				1.0
				if _progression_level != null
				else _stack_multiplier(
					swing.pickaxes,
					&"width_multiplier",
					config.maximum_stack_width_multiplier
				)
			)
			* swing.width_scale
		),
		0
	)
	# The inscription floor only ever widens. A combo or a stacked pickaxe that
	# already cuts wider than the authored band keeps its own larger opening.
	return maxi(
		resolved_half_width_cells,
		_inscription_minimum_half_width_cells
	)


## Resolves the vertical impact size identically for wind-up and contact.
func _get_requested_depth_rows(swing: SwingRequest) -> int:
	var capped_combo := mini(swing.combo, config.maximum_effect_combo)
	var combo_steps := maxi(capped_combo - 1, 0)
	var combo_added_depth := (
		config.combo_mine_depth_rows_per_step * combo_steps
	)
	var requested_depth_rows: int
	if _progression_level != null:
		requested_depth_rows = _progression_level.scale_impact(
			float(config.base_mine_depth_rows),
			float(combo_added_depth)
		)
	else:
		requested_depth_rows = (
			config.base_mine_depth_rows + combo_added_depth
		)
		requested_depth_rows = maxi(
			roundi(
				float(requested_depth_rows)
				* _stack_multiplier(
					swing.pickaxes,
					&"power_multiplier",
					config.maximum_stack_power_multiplier
				)
			),
			1
		)
	return maxi(
		roundi(float(requested_depth_rows) * swing.power_scale),
		1
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
