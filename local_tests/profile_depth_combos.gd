extends SceneTree

## How it works:
## - Teleports to representative deep coordinates instead of replaying every hit.
## - Primes the same predictive stamp cache used by up to five timing targets.
## - Measures preparation slices, impact signal work, and deferred raster work.
## - Resets each case so branch order and prior cache contents cannot help it.
## The invariant is that shipped fidelity must pass every game-jam web budget.

const MINING_SCENE := preload("res://Scenes/mining/mining_proof.tscn")
const LOCAL_MEMORY_SAVE_GAME := preload("res://local_tests/local_memory_save_game.gd")
const PROFILE_DEPTHS: Array[int] = [10_000, 50_000, 100_000]
const MAX_CONFIGURED_HIT_MS: float = 4.0
const MAX_STACKED_HIT_MS: float = 8.0
const MAX_WORK_MS: float = 7.0
# The jam shipping ceiling is 50 ms for a fully drained impact. The tighter
# hit, per-item, and queue guards stay unchanged so this cannot mask a frame
# spike or unbounded backlog merely to accept a longer aggregate drain.
const MAX_TOTAL_MS: float = 50.0
const MAX_QUEUE_SIZE: int = 192
# The deep traversal is intentionally broader than the 20-second microbenches,
# but it still terminates below one minute so a broken stream cannot pin CI.
const WATCHDOG_SECONDS: float = 55.0

var _finished: bool = false


func _initialize() -> void:
	_watchdog.call_deferred()
	_run.call_deferred()


func _watchdog() -> void:
	await create_timer(WATCHDOG_SECONDS, true).timeout
	if _finished:
		return
	push_error(
		"Performance concern: depth-combo profile exceeded %.0f seconds."
		% WATCHDOG_SECONDS
	)
	quit(124)


func _run() -> void:
	var game_state := root.get_node("/root/GameState") as RunState
	game_state.save_game = LOCAL_MEMORY_SAVE_GAME.new()
	var game_root := MINING_SCENE.instantiate()
	var renderer := (
		game_root.get_node("MiningScene/TerrainLayerRenderer")
		as TerrainLayerRenderer
	)
	# Match the shipped profile unless a candidate density is being measured.
	# This keeps every depth run on one profiler and one unchanged budget.
	var requested_mask_pixels := int(
		OS.get_environment("BENCHMARK_MASK_PIXELS_PER_CELL")
	)
	renderer.profile = renderer.profile.duplicate()
	if requested_mask_pixels > 0:
		renderer.profile.mask_pixels_per_cell = requested_mask_pixels
	root.add_child(game_root)
	await process_frame
	print(
		"DEPTH_COMBO_MASK_PIXELS_PER_CELL=%d"
		% renderer.profile.mask_pixels_per_cell
	)
	var mining_scene := game_root.get_node("MiningScene")
	var manager := (
		mining_scene.get_node("TerrainManager") as TerrainManager
	)
	var view_controller := (
		mining_scene.get_node("Systems/ViewController") as ViewController
	)
	view_controller.set_process(false)
	var gem_outcrop_field := (
		mining_scene.get_node("GemOutcropField") as GemOutcropField
	)
	# This profile measures deterministic terrain hit work. A random gem roll
	# performs a separate persistence workflow and must never mutate user:// or
	# turn one depth sample into a disk-I/O sample.
	gem_outcrop_field.spawn_chance = 0.0

	var start_row := manager.config.initial_surface_row
	var maximum_depth_rows := (
		manager.config.base_mine_depth_rows
		+ manager.config.combo_mine_depth_rows_per_step
			* (manager.config.maximum_effect_combo - 1)
	)
	var maximum_half_width_cells := (
		manager.config.base_tunnel_half_width_cells
		+ manager.config.combo_tunnel_half_width_cells_per_step
			* (manager.config.maximum_effect_combo - 1)
	)
	var stacked_depth_rows := roundi(
		float(maximum_depth_rows)
		* manager.config.maximum_stack_power_multiplier
	)
	var stacked_half_width_cells := roundi(
		float(maximum_half_width_cells)
		* manager.config.maximum_stack_width_multiplier
	)
	var budget_failed := false

	for target_depth in PROFILE_DEPTHS:
		# Depth changes chunk indices and world-space mask coordinates; it does
		# not require replaying ~8,300 unrelated base-hit visuals first. Stream
		# the exact destination directly, then benchmark the same two real hits.
		var target_view_position := Vector2(
			16,
			start_row + target_depth
		)
		await _reset_measurement_state(
			manager,
			renderer,
			target_view_position
		)
		renderer._on_dig_presentation_started(
			manager.config.maximum_effect_combo
		)
		var configured_metrics := _measure_combo(
			manager,
			renderer,
			Vector2i(128, start_row + target_depth),
			maximum_depth_rows,
			maximum_half_width_cells
		)
		# The maximum-stack case must not inherit allocated destruction masks or
		# visual history from the configured case merely because it runs second.
		await _reset_measurement_state(
			manager,
			renderer,
			target_view_position
		)
		renderer._on_dig_presentation_started(
			manager.config.maximum_effect_combo
		)
		var stacked_metrics := _measure_combo(
			manager,
			renderer,
			Vector2i(256, start_row + target_depth),
			stacked_depth_rows,
			stacked_half_width_cells
		)
		renderer._defer_impact_rasterization = false
		print(
			(
				"DEPTH_COMBO depth=%d "
				+ "configured_hit_ms=%.2f configured_queue=%d "
				+ "configured_prep_ms=%.2f configured_max_work_ms=%.2f "
				+ "configured_total_ms=%.2f "
				+ "stacked_hit_ms=%.2f stacked_queue=%d "
				+ "stacked_prep_ms=%.2f stacked_max_work_ms=%.2f "
				+ "stacked_total_ms=%.2f "
				+ "static_mib=%.2f nodes=%d"
			)
			% [
				target_depth,
				float(configured_metrics.hit_ms),
				int(configured_metrics.queue),
				float(configured_metrics.max_preparation_ms),
				float(configured_metrics.max_work_ms),
				float(configured_metrics.total_ms),
				float(stacked_metrics.hit_ms),
				int(stacked_metrics.queue),
				float(stacked_metrics.max_preparation_ms),
				float(stacked_metrics.max_work_ms),
				float(stacked_metrics.total_ms),
				(
					Performance.get_monitor(Performance.MEMORY_STATIC)
					/ (1024.0 * 1024.0)
				),
				int(
					Performance.get_monitor(
						Performance.OBJECT_NODE_COUNT
					)
				),
			]
		)
		if (
			float(configured_metrics.hit_ms) > MAX_CONFIGURED_HIT_MS
			or float(stacked_metrics.hit_ms) > MAX_STACKED_HIT_MS
			or float(configured_metrics.max_work_ms) > MAX_WORK_MS
			or float(stacked_metrics.max_work_ms) > MAX_WORK_MS
			or float(configured_metrics.max_preparation_ms) > MAX_WORK_MS
			or float(stacked_metrics.max_preparation_ms) > MAX_WORK_MS
			or float(configured_metrics.total_ms) > MAX_TOTAL_MS
			or float(stacked_metrics.total_ms) > MAX_TOTAL_MS
			or int(configured_metrics.queue) > MAX_QUEUE_SIZE
			or int(stacked_metrics.queue) > MAX_QUEUE_SIZE
		):
			budget_failed = true
			push_error(
				"Depth %d combo terrain exceeded the web budget."
				% target_depth
			)

	print(
		(
			"DEPTH_COMBO_BUDGET configured_hit<=%.2f "
			+ "stacked_hit<=%.2f work<=%.2f total<=%.2f queue<=%d"
		)
		% [
			MAX_CONFIGURED_HIT_MS,
			MAX_STACKED_HIT_MS,
			MAX_WORK_MS,
			MAX_TOTAL_MS,
			MAX_QUEUE_SIZE,
		]
	)
	game_root.queue_free()
	await process_frame
	_finished = true
	quit(1 if budget_failed else 0)


## Restores one cold, intact measurement case without rebuilding the prior
## depth or retaining transformed-stamp LRU state from a differently ordered
## branch. Both configured and stacked measurements use this exact sequence.
func _reset_measurement_state(
	manager: TerrainManager,
	renderer: TerrainLayerRenderer,
	view_position: Vector2
) -> void:
	manager.clear_damage()
	manager.set_view_position(view_position)
	renderer.rebuild_all_chunks()
	renderer._stamp_image_cache.reset(
		renderer.resized_stamp_cache_limit,
		renderer.resized_stamp_cache_max_pixels
	)
	await process_frame
	renderer._defer_impact_rasterization = true


func _measure_combo(
	manager: TerrainManager,
	renderer: TerrainLayerRenderer,
	position: Vector2i,
	depth_rows: int,
	half_width_cells: int
) -> Dictionary:
	# Depth must exercise the same predictive contract as play. Preparation is
	# measured separately and retains the unchanged 7 ms atomic work ceiling.
	renderer._on_dig_visuals_preparation_started(false)
	renderer._on_dig_visuals_preparation_requested(
		position,
		depth_rows,
		half_width_cells,
		position.x,
		manager.config.maximum_effect_combo
	)
	var maximum_preparation_ms := 0.0
	while (
		renderer._pending_stamp_preparation_head
		< renderer._pending_stamp_preparation.size()
	):
		var preparation_started_at := Time.get_ticks_usec()
		renderer._prepare_next_pending_stamp_layer()
		maximum_preparation_ms = maxf(
			maximum_preparation_ms,
			float(Time.get_ticks_usec() - preparation_started_at) / 1000.0
		)
	renderer._compact_pending_stamp_preparation()
	renderer._on_dig_visuals_preparation_started(true)
	renderer._on_dig_visuals_preparation_requested(
		position,
		depth_rows,
		half_width_cells,
		position.x,
		manager.config.maximum_effect_combo
	)
	var hit_started_at := Time.get_ticks_usec()
	manager.dig_tunnel(position, depth_rows, half_width_cells)
	var hit_ms := (
		float(Time.get_ticks_usec() - hit_started_at) / 1000.0
	)
	var queue_size := (
		renderer._pending_impact_work.size()
		- renderer._pending_impact_work_head
	)
	var total_ms := 0.0
	var maximum_work_ms := 0.0
	while (
		renderer._pending_impact_work_head
		< renderer._pending_impact_work.size()
	):
		var work_started_at := Time.get_ticks_usec()
		renderer._process_next_pending_impact_work()
		var work_ms := (
			float(Time.get_ticks_usec() - work_started_at) / 1000.0
		)
		total_ms += work_ms
		maximum_work_ms = maxf(maximum_work_ms, work_ms)
	renderer._compact_pending_impact_work()
	return {
		"hit_ms": hit_ms,
		"queue": queue_size,
		"max_preparation_ms": maximum_preparation_ms,
		"max_work_ms": maximum_work_ms,
		"total_ms": total_ms,
	}
