class_name LayerBreakthroughSequence
extends LayerCutsceneEnvironment

## How it works:
## - LayerCutsceneEnvironment opens the stage after the real gameplay fall.
## - This facade requests external dialogue while retaining its public signals.
## - The destination stage owns lead/follower rat markers and mining targets.
## - A bounded rat loop mines real masks throughout both final dialogue beats.
## - The last line stops spawning, drains the cast, then restores presentation.
## - Interruption cancels actors before delegating exact environment cleanup.
## - The invariant is that rats never replace the next depth encounter.

const RatAppearanceType = preload(
	"res://Scripts/cinematics/cinematic_rat_appearance.gd"
)

signal sequence_started
signal dialogue_beat_requested(beat_id: StringName)
signal tunnel_stage_ready
signal rat_strike_requested(screen_position: Vector2)
signal sequence_restored(completed: bool)
signal sequence_failed(reason: String)

const DISCOVERY_BEAT: StringName = &"discovery"
const RAT_WARNING_BEAT: StringName = &"rat_warning"
const MINER_RESPONSE_BEAT: StringName = &"miner_response"

enum Phase {
	IDLE,
	WAITING_FOR_DISCOVERY_DIALOGUE,
	OPENING_TUNNEL_STAGE,
	REVEALING_TUNNEL,
	WAITING_FOR_TUNNEL_REVEAL,
	LEAD_RAT_ENTERING,
	WAITING_FOR_RAT_DIALOGUE,
	WAITING_FOR_MINER_DIALOGUE,
	DRAINING_RAT_PROCESSION,
	RESTORING,
}

@export_category("Rat Stage References")
@export var mining_targets_root: Node2D
@export_range(0.0, 2.0, 0.05) var tunnel_reveal_pause: float = 0.3

@export_category("Rat Procession References")
@export var lead_rat: CinematicRatMiner
@export var rat_scene: PackedScene
@export var rat_container: Node2D
@export var rat_spawn_anchor: Marker2D
@export var lead_warning_anchor: Marker2D
@export var rat_exit_anchor: Marker2D
@export var rat_entry_points_root: Node2D
## Rutini's own paired art. Keep it out of rat_appearances so the speaking lead
## stays visually distinct from every follower for the whole procession.
@export var lead_rat_appearance: RatAppearanceType
## Paired follower color/strike variants; sequence_index cycles this array.
@export var rat_appearances: Array[RatAppearanceType] = []

@export_category("Rat Procession")
@export_range(-64.0, 0.0, 1.0) var rat_floor_offset_y: float = -29.0
@export_range(0, 12, 1) var max_live_follower_rats: int = 7
## Caps live followers on web; each follower is freed after its own exit.
@export_range(0, 12, 1) var web_max_live_follower_rats: int = 5
@export_range(0.05, 2.0, 0.05) var lead_rat_run_duration: float = 0.75
@export_range(0.05, 2.0, 0.05) var follower_run_duration: float = 0.65
## Paces arrivals into a steady trickle. Short values let the cast fill to its
## cap in one burst and then re-burst as a whole group exits together.
@export_range(0.05, 2.0, 0.05) var follower_spawn_interval: float = 0.45
@export_range(0.0, 1.0, 0.01) var rat_strike_interval: float = 0.08
## Duration of one strike-approved root step, not one wall-crossing tween.
@export_range(0.05, 2.0, 0.05) var rat_exit_duration: float = 0.18
## Overlaps production indents by 24 px so organic cut edges join cleanly.
@export_range(8.0, 72.0, 1.0) var rat_exit_step_distance: float = 72.0
## Insets actor roots and jump arcs; only each rat's StrikeAnchor reaches rock.
@export_range(0.0, 96.0, 1.0) var rat_tunnel_root_margin: float = 64.0
@export_range(0.0, 2.0, 0.05) var response_pause: float = 0.25
@export_range(8.0, 96.0, 1.0) var rat_indent_diameter: float = 96.0
@export_range(-128, 128, 1) var rat_front_draw_order: int = 16
@export_range(-128, 128, 1) var rat_behind_draw_order: int = 14

@export_category("Rat Entries")
## Absolute order between promoted layer five (2) and its backing layer (0).
@export_range(-128, 128, 1) var rat_entry_behind_draw_order: int = 1
@export_range(0.05, 2.0, 0.05) var rat_entry_duration: float = 0.42
@export_range(8.0, 96.0, 1.0) var rat_entry_indent_diameter: float = 64.0

var _phase: Phase = Phase.IDLE
## Live growth is bounded to max_live_follower_rats (12, or web cap) and pruned.
var _active_followers: Array[CinematicRatMiner] = []
## Growth matches the bounded active cast and is cleared on exit or cancellation.
var _rat_targets: Dictionary[int, CinematicRatMiningTarget] = {}
var _procession_tween: Tween
var _response_tween: Tween
var _rat_spawning_active: bool = false
var _lead_rat_active: bool = false
var _next_rat_sequence_index: int = 1
var _mining_targets: Array[CinematicRatMiningTarget] = []
var _rat_entry_points: Array[CinematicRatEntryPoint] = []
# Target-keyed growth is bounded by the authored target count (four today).
var _opened_rat_target_ids: Dictionary[int, bool] = {}
var _rat_exit_frontiers: Dictionary[int, float] = {}
# Entry-keyed growth is bounded by the four authored entry markers.
var _opened_rat_entry_ids: Dictionary[int, bool] = {}
# Live growth is bounded by the follower cap and pruned at entry completion/exit.
var _pending_rat_entry_targets: Dictionary[int, CinematicRatMiningTarget] = {}
var _pending_rat_entry_points: Dictionary[int, CinematicRatEntryPoint] = {}
## Bounded by two lead markers plus the authored mining-target count (four today).
var _authored_ground_marker_positions: Dictionary[Marker2D, Vector2] = {}


## Resolves rat content and maps generic environment lifecycle to this facade.
func _ready() -> void:
	super._ready()
	_collect_authored_mining_targets()
	_collect_authored_rat_entry_points()
	_authored_ground_marker_positions.clear()
	for marker: Marker2D in [rat_spawn_anchor, lead_warning_anchor]:
		if is_instance_valid(marker):
			_authored_ground_marker_positions[marker] = marker.position
	for mining_target in _mining_targets:
		_authored_ground_marker_positions[mining_target] = (
			mining_target.position
		)
	_connect_once(stage_ready, _on_environment_stage_ready)
	_connect_once(restored, _on_environment_restored)
	_connect_once(failed, _on_environment_failed)
	if is_instance_valid(lead_rat):
		_register_rat(lead_rat)
		_connect_once(lead_rat.reached_wall, _on_lead_rat_reached_wall)
	_reset_authored_stage()


## Starts one visual breakthrough after the coordinator has gated gameplay.
func play_breakthrough() -> bool:
	if _phase != Phase.IDLE:
		return false
	var validation_error := _get_validation_error()
	if not validation_error.is_empty():
		_fail_without_sequence(validation_error)
		return false
	if not prepare_environment():
		return false

	_cleanup_followers()
	show()
	lead_rat.hide()
	_phase = Phase.WAITING_FOR_DISCOVERY_DIALOGUE
	sequence_started.emit()
	_request_discovery_dialogue.call_deferred()
	return true


## Acknowledges one external dialogue segment and advances its stage phase.
func complete_dialogue_beat(beat_id: StringName) -> bool:
	if (
		beat_id == DISCOVERY_BEAT
		and _phase == Phase.WAITING_FOR_DISCOVERY_DIALOGUE
	):
		_phase = Phase.OPENING_TUNNEL_STAGE
		if open_environment_stage():
			return true
		return false
	if (
		beat_id == RAT_WARNING_BEAT
		and _phase == Phase.WAITING_FOR_RAT_DIALOGUE
	):
		_phase = Phase.WAITING_FOR_MINER_DIALOGUE
		_request_miner_response_after_pause()
		return true
	if (
		beat_id == MINER_RESPONSE_BEAT
		and _phase == Phase.WAITING_FOR_MINER_DIALOGUE
	):
		_stop_rat_spawning()
		_phase = Phase.DRAINING_RAT_PROCESSION
		_try_finish_rat_drain()
		return true
	return false


## Requests the landing reaction only after the controller marks us active.
func _request_discovery_dialogue() -> void:
	if _phase == Phase.WAITING_FOR_DISCOVERY_DIALOGUE:
		dialogue_beat_requested.emit(DISCOVERY_BEAT)


## Continues only after the frame owner has opened the iris onto layer five.
func complete_tunnel_reveal() -> bool:
	if _phase != Phase.WAITING_FOR_TUNNEL_REVEAL:
		return false
	_start_lead_rat_entrance()
	return true


## Immediately restores terrain and miner visuals after any interruption.
func abort_and_restore() -> void:
	if _phase == Phase.IDLE:
		return
	_phase = Phase.RESTORING
	_stop_rat_spawning()
	if is_instance_valid(lead_rat):
		lead_rat.cancel_action()
	for rat in _active_followers:
		if is_instance_valid(rat):
			rat.cancel_action()
	_cleanup_followers()
	cancel_environment()


## Reports whether this scene currently owns cutscene presentation.
func is_sequence_active() -> bool:
	return _phase != Phase.IDLE


## Grounds rat-specific markers after the reusable room and miner are ready.
func _on_environment_stage_ready() -> void:
	if _phase != Phase.OPENING_TUNNEL_STAGE:
		return
	_phase = Phase.REVEALING_TUNNEL
	if not _ground_choreography_on_tunnel():
		_fail_active_sequence(
			"Could not ground rat choreography on the cutscene room floor."
		)
		return
	lead_rat.prepare_for_sequence(rat_spawn_anchor.global_position, -1)
	lead_rat.set_tunnel_motion_bounds(_get_rat_root_motion_bounds())
	lead_rat.hide()
	_phase = Phase.WAITING_FOR_TUNNEL_REVEAL
	tunnel_stage_ready.emit()


## Starts the lead rat once the cave and viewport have both been revealed.
func _start_lead_rat_entrance() -> void:
	if _phase != Phase.WAITING_FOR_TUNNEL_REVEAL:
		return
	_phase = Phase.LEAD_RAT_ENTERING
	lead_rat.show()
	get_tree().create_timer(
		tunnel_reveal_pause,
		true,
		false,
		true
	).timeout.connect(
		_run_lead_rat_entrance,
		CONNECT_ONE_SHOT
	)


## Runs the lead only after the authored cave-reveal hold.
func _run_lead_rat_entrance() -> void:
	if _phase != Phase.LEAD_RAT_ENTERING:
		return
	if not lead_rat.start_run_to_wall(
		lead_warning_anchor.global_position.x,
		lead_rat_run_duration,
		get_stage_floor_screen_y
	):
		_fail_active_sequence("Lead rat could not start its entrance.")


## Grounds concrete rat markers at their own production-floor x coordinates.
func _ground_choreography_on_tunnel() -> bool:
	if not get_stage_motion_bounds(rat_tunnel_root_margin).has_area():
		return false
	if (
		not ground_stage_marker(
			rat_spawn_anchor,
			rat_floor_offset_y,
			rat_tunnel_root_margin
		)
		or not ground_stage_marker(
			lead_warning_anchor,
			rat_floor_offset_y,
			rat_tunnel_root_margin
		)
	):
		return false
	for mining_target in _mining_targets:
		if not ground_stage_marker(
			mining_target,
			rat_floor_offset_y + mining_target.floor_offset_y,
			rat_tunnel_root_margin
		):
			return false
	return true


## Keeps every authored root and jump arc inside the real opened room.
func _get_rat_root_motion_bounds() -> Rect2:
	return get_stage_motion_bounds(rat_tunnel_root_margin)


## Starts the live procession as the lead begins its externally owned warning.
func _on_lead_rat_reached_wall(_rat: CinematicRatMiner) -> void:
	if _phase != Phase.LEAD_RAT_ENTERING:
		return
	_phase = Phase.WAITING_FOR_RAT_DIALOGUE
	_start_rat_procession()
	if _phase != Phase.WAITING_FOR_RAT_DIALOGUE:
		return
	dialogue_beat_requested.emit(RAT_WARNING_BEAT)


## Sends the lead mining and starts one bounded, recurring spawn loop.
func _start_rat_procession() -> void:
	_opened_rat_target_ids.clear()
	_rat_exit_frontiers.clear()
	_rat_spawning_active = true
	_lead_rat_active = true
	_next_rat_sequence_index = 1
	lead_rat.sequence_index = 0
	_apply_rat_appearance(lead_rat)
	if not _send_rat_to_mining_target(
		lead_rat,
		_mining_targets.front(),
		follower_run_duration,
		false
	):
		_fail_active_sequence("Lead rat could not reach its mining target.")
		return
	if _get_live_follower_cap() <= 0:
		return
	_schedule_next_rat_spawn(follower_spawn_interval * 0.5)


## Owns the sole recurring timer so the live cast stays bounded indefinitely.
func _schedule_next_rat_spawn(delay: float) -> void:
	if not _rat_spawning_active:
		return
	if _procession_tween != null and _procession_tween.is_valid():
		_procession_tween.kill()
	_procession_tween = create_tween()
	_procession_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_procession_tween.tween_interval(maxf(delay, 0.01))
	_procession_tween.tween_callback(_try_spawn_next_rat)


## Fills one available live slot, then schedules the next bounded attempt.
func _try_spawn_next_rat() -> void:
	_procession_tween = null
	if not _rat_spawning_active:
		return
	if _active_followers.size() < _get_live_follower_cap():
		_spawn_following_rat(_next_rat_sequence_index)
		_next_rat_sequence_index += 1
	if _rat_spawning_active:
		_schedule_next_rat_spawn(follower_spawn_interval)


## Instantiates one reusable authored rat actor for the continuous procession.
func _spawn_following_rat(rat_index: int) -> void:
	var rat := rat_scene.instantiate() as CinematicRatMiner
	if rat == null:
		_fail_active_sequence(
			"Rat procession scene must instantiate CinematicRatMiner."
		)
		return
	rat_container.add_child(rat)
	_active_followers.append(rat)
	_register_rat(rat)
	var entry_point := _rat_entry_points[
		posmod(rat_index - 1, _rat_entry_points.size())
	]
	var entry_is_open := _is_rat_entry_open(entry_point)
	var stagger_y := (
		float(posmod(rat_index, 3) - 1) * 7.0
		if entry_is_open
		else 0.0
	)
	rat.prepare_for_sequence(
		entry_point.global_position
			+ entry_point.behind_start_offset
			+ Vector2(0.0, stagger_y),
		rat_index
	)
	_apply_rat_appearance(rat)
	rat.set_plane_draw_order(rat_entry_behind_draw_order)
	# Three web lanes leave enough of the renderer's bounded indent budget for
	# every lane to reach offscreen; desktop retains all authored wall spots.
	var usable_target_count := _mining_targets.size()
	if OS.has_feature("web"):
		usable_target_count = mini(usable_target_count, 3)
	var mining_target := _mining_targets[
		posmod(rat_index + 1, usable_target_count)
	]
	_pending_rat_entry_targets[rat.get_instance_id()] = mining_target
	if entry_is_open:
		if not _start_rat_entry_run(rat, entry_point):
			_fail_active_sequence("A rat could not enter its open cave route.")
		return
	_pending_rat_entry_points[rat.get_instance_id()] = entry_point
	if not rat.start_entry_breach(entry_point.global_position):
		_fail_active_sequence("A rat could not strike its authored cave entry.")


## Resolves the platform-specific live follower ceiling without stopping churn.
func _get_live_follower_cap() -> int:
	if OS.has_feature("web"):
		return mini(
			max_live_follower_rats,
			web_max_live_follower_rats
		)
	return max_live_follower_rats


## Allows existing actors to finish during either dialogue and the final drain.
func _rat_actions_may_continue() -> bool:
	return _phase in [
		Phase.WAITING_FOR_RAT_DIALOGUE,
		Phase.WAITING_FOR_MINER_DIALOGUE,
		Phase.DRAINING_RAT_PROCESSION,
	]


## Gives the lead its own art and cycles follower art by stable sequence index.
func _apply_rat_appearance(rat: CinematicRatMiner) -> void:
	if not is_instance_valid(rat):
		return
	if rat == lead_rat and lead_rat_appearance != null:
		rat.set_appearance(lead_rat_appearance)
		return
	if rat_appearances.is_empty():
		return
	var appearance := rat_appearances[
		posmod(rat.sequence_index, rat_appearances.size())
	]
	if appearance != null:
		rat.set_appearance(appearance)


## Reports whether an authored route is open without changing presentation.
func _is_rat_entry_open(entry_point: CinematicRatEntryPoint) -> bool:
	return (
		is_instance_valid(entry_point)
		and (
			not entry_point.requires_breach
			or _opened_rat_entry_ids.has(entry_point.get_instance_id())
		)
	)


## Enters the cave the way this marker is authored, then lands on the real floor.
## A breaching marker is a hole in the backing wall the mouse falls out of; an
## open marker is the side route it simply runs in along.
func _start_rat_entry_run(
	rat: CinematicRatMiner,
	entry_point: CinematicRatEntryPoint
) -> bool:
	if not is_instance_valid(rat) or not is_instance_valid(entry_point):
		return false
	var motion_bounds := _get_rat_root_motion_bounds()
	if not motion_bounds.has_area():
		return false
	var landing_x := clampf(
		entry_point.global_position.x + entry_point.emergence_travel_x,
		motion_bounds.position.x,
		motion_bounds.end.x
	)
	var floor_y := get_stage_floor_screen_y(landing_x)
	if is_nan(floor_y):
		return false
	var landing_position := Vector2(landing_x, floor_y + rat_floor_offset_y)
	if not entry_point.requires_breach:
		return rat.start_run_to_target(
			landing_position,
			rat_entry_duration,
			0.0,
			NAN,
			get_stage_floor_screen_y
		)
	return rat.start_wall_emergence(landing_position, rat_entry_duration)


## Opens one real foreground breach at the actor's strike contact frame.
func _on_rat_entry_breach_requested(
	rat: CinematicRatMiner,
	screen_position: Vector2
) -> void:
	if not _rat_actions_may_continue() or not is_instance_valid(rat):
		return
	var rat_id := rat.get_instance_id()
	var entry_point: CinematicRatEntryPoint = (
		_pending_rat_entry_points.get(rat_id)
	)
	if not is_instance_valid(entry_point):
		_fail_active_sequence("A breaching rat lost its authored entry.")
		return
	var entry_id := entry_point.get_instance_id()
	if _opened_rat_entry_ids.has(entry_id):
		return
	if not terrain_renderer.punch_cinematic_tunnel_indent(
		screen_position,
		rat_entry_indent_diameter
	):
		_fail_active_sequence("A rat could not open its authored cave entry.")
		return
	_opened_rat_entry_ids[entry_id] = true
	rat_strike_requested.emit(screen_position)


## Sends a first breacher through only after its strike pose fully recovers.
func _on_rat_entry_breach_finished(rat: CinematicRatMiner) -> void:
	if not _rat_actions_may_continue() or not is_instance_valid(rat):
		return
	var rat_id := rat.get_instance_id()
	var entry_point: CinematicRatEntryPoint = (
		_pending_rat_entry_points.get(rat_id)
	)
	if not is_instance_valid(entry_point):
		_fail_active_sequence("A rat finished an unassigned cave breach.")
		return
	_pending_rat_entry_points.erase(rat_id)
	if not _is_rat_entry_open(entry_point):
		_fail_active_sequence("A rat's authored cave breach never opened.")
		return
	if not _start_rat_entry_run(rat, entry_point):
		_fail_active_sequence("A rat could not enter through its cave breach.")


## Assigns a wall plane and starts one authored run across layer five.
func _send_rat_to_mining_target(
	rat: CinematicRatMiner,
	mining_target: CinematicRatMiningTarget,
	duration: float,
	jump_over_miner: bool
) -> bool:
	if not is_instance_valid(rat) or not is_instance_valid(mining_target):
		return false
	rat.set_plane_draw_order(
		rat_front_draw_order
		if mining_target.front_of_miner
		else rat_behind_draw_order
	)
	_rat_targets[rat.get_instance_id()] = mining_target
	var jump_peak_x := (
		stage_floor_anchor.global_position.x
		if jump_over_miner
		else NAN
	)
	if rat.start_run_to_target(
		mining_target.global_position,
		duration,
		mining_target.jump_height if jump_over_miner else 0.0,
		jump_peak_x,
		get_stage_floor_screen_y
	):
		return true
	_rat_targets.erase(rat.get_instance_id())
	return false


## Starts bounded mining after a mouse reaches its assigned wall indent.
func _on_rat_run_target_reached(rat: CinematicRatMiner) -> void:
	if not _rat_actions_may_continue():
		return
	var target_id := rat.get_instance_id()
	var entry_target: CinematicRatMiningTarget = (
		_pending_rat_entry_targets.get(target_id)
	)
	if is_instance_valid(entry_target):
		_pending_rat_entry_targets.erase(target_id)
		rat.set_tunnel_motion_bounds(_get_rat_root_motion_bounds())
		# A mouse that just landed runs off along the floor unless its lane is
		# authored high enough that only an arc can reach it.
		if not _send_rat_to_mining_target(
			rat,
			entry_target,
			follower_run_duration,
			entry_target.jump_height > 0.0
		):
			_fail_active_sequence(
				"A rat entered the cave but could not reach its wall target."
			)
		return
	var mining_target: CinematicRatMiningTarget = _rat_targets.get(
		target_id
	)
	if not is_instance_valid(mining_target):
		_fail_active_sequence("A rat reached an unassigned mining target.")
		return
	if not rat.start_mining_then_exit(
		mining_target.strike_count,
		Vector2(
			rat_exit_anchor.global_position.x
				+ 12.0 * float(posmod(rat.sequence_index, 3)),
			rat.global_position.y
		),
		rat_exit_duration,
		rat_strike_interval
	):
		_fail_active_sequence("A rat could not start mining.")


## Opens each authored wall spot once while every assigned rat still strikes it.
func _on_rat_mining_strike_requested(
	rat: CinematicRatMiner,
	screen_position: Vector2
) -> void:
	if not _rat_actions_may_continue():
		return
	var mining_target := _get_rat_mining_target(rat)
	if not is_instance_valid(mining_target):
		_fail_active_sequence("A mining rat lost its authored wall target.")
		return
	var target_id := mining_target.get_instance_id()
	if not _opened_rat_target_ids.has(target_id):
		if not terrain_renderer.punch_cinematic_tunnel_indent(
			screen_position,
			rat_indent_diameter
		):
			_fail_active_sequence(
				"An authored rat strike could not open the production wall."
			)
			return
		_opened_rat_target_ids[target_id] = true
		_rat_exit_frontiers[target_id] = (
			rat.global_position.x + rat_exit_step_distance
		)
	rat_strike_requested.emit(screen_position)


## Opens only the next bounded segment, then releases that rat root to follow it.
func _on_rat_exit_strike_requested(
	rat: CinematicRatMiner,
	screen_position: Vector2,
	requested_root_x: float
) -> void:
	if not _rat_actions_may_continue():
		return
	var mining_target := _get_rat_mining_target(rat)
	if not is_instance_valid(mining_target):
		_fail_active_sequence("An exiting rat lost its authored wall lane.")
		return
	var target_id := mining_target.get_instance_id()
	var open_frontier: float = _rat_exit_frontiers.get(
		target_id,
		mining_target.global_position.x
	)
	if requested_root_x > open_frontier + 0.5:
		# Once the root itself is right of the viewport, the prior overlapping
		# indent already protects its last visible pixels. No offscreen terrain
		# mutation is needed to move the remaining sprite width out of view.
		if rat.global_position.x < get_viewport_rect().size.x:
			if not terrain_renderer.punch_cinematic_tunnel_indent(
				screen_position,
				rat_indent_diameter
			):
				_fail_active_sequence(
					"An exiting rat could not mine its next "
					+ "production-wall step."
				)
				return
		open_frontier = requested_root_x
		_rat_exit_frontiers[target_id] = open_frontier
	rat_strike_requested.emit(screen_position)
	if not rat.approve_exit_step():
		_fail_active_sequence("An exiting rat rejected its opened wall step.")


## Starts the first bounded wall step after authored mining completes.
func _on_rat_ready_to_exit(rat: CinematicRatMiner) -> void:
	if _rat_actions_may_continue():
		_start_next_rat_exit_step(rat)


## Continues a rat only after its prior opened segment was fully traversed.
func _on_rat_exit_step_finished(rat: CinematicRatMiner) -> void:
	if _rat_actions_may_continue():
		_start_next_rat_exit_step(rat)


## Advances at most one indent diameter and marks only the offscreen step final.
func _start_next_rat_exit_step(rat: CinematicRatMiner) -> void:
	if not is_instance_valid(rat):
		return
	var exit_target := rat.get_exit_target()
	var remaining_distance := exit_target.x - rat.global_position.x
	if remaining_distance <= 0.0:
		_fail_active_sequence("A rat reached an invalid completed exit step.")
		return
	var step_distance := minf(
		rat_exit_step_distance,
		remaining_distance
	)
	var step_target := Vector2(
		rat.global_position.x + step_distance,
		exit_target.y
	)
	if not rat.start_exit_step(
		step_target,
		is_equal_approx(step_target.x, exit_target.x)
	):
		_fail_active_sequence("A rat could not start its next mined exit step.")


## Resolves the stable authored lane retained until that rat exits.
func _get_rat_mining_target(
	rat: CinematicRatMiner
) -> CinematicRatMiningTarget:
	if not is_instance_valid(rat):
		return null
	return _rat_targets.get(rat.get_instance_id())


## Prunes followers after each has mined fully beyond the right viewport edge.
func _on_rat_exited(rat: CinematicRatMiner) -> void:
	if not _rat_actions_may_continue():
		return
	_rat_targets.erase(rat.get_instance_id())
	_pending_rat_entry_targets.erase(rat.get_instance_id())
	_pending_rat_entry_points.erase(rat.get_instance_id())
	if rat == lead_rat:
		_lead_rat_active = false
	else:
		_active_followers.erase(rat)
		rat.queue_free()
	_try_finish_rat_drain()


## Advances to the final line after an authored pause, never after actor exits.
func _request_miner_response_after_pause() -> void:
	if response_pause <= 0.0:
		_request_miner_response()
		return
	if _response_tween != null and _response_tween.is_valid():
		_response_tween.kill()
	_response_tween = create_tween()
	_response_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_response_tween.tween_interval(response_pause)
	_response_tween.tween_callback(_request_miner_response)


## Requests the miner quip from its live authored mouth marker.
func _request_miner_response() -> void:
	_response_tween = null
	if _phase != Phase.WAITING_FOR_MINER_DIALOGUE:
		return
	dialogue_beat_requested.emit(MINER_RESPONSE_BEAT)


## Cancels the sole spawn timer before the last dialogue begins draining actors.
func _stop_rat_spawning() -> void:
	_rat_spawning_active = false
	if _procession_tween != null and _procession_tween.is_valid():
		_procession_tween.kill()
	_procession_tween = null


## Restores only after the last dialogue ended and every live rat left right.
func _try_finish_rat_drain() -> void:
	if (
		_phase == Phase.DRAINING_RAT_PROCESSION
		and not _lead_rat_active
		and _active_followers.is_empty()
	):
		_begin_restoration()


## Delegates exact miner/terrain restoration after the rat cast drains.
func _begin_restoration() -> void:
	_phase = Phase.RESTORING
	if not restore_environment():
		_fail_active_sequence(
			"Layer breakthrough environment could not begin restoration."
		)


## Maps generic restoration back to the facade contract consumed by its controller.
func _on_environment_restored(completed: bool) -> void:
	if _phase != Phase.RESTORING:
		return
	_cleanup_followers()
	_reset_authored_stage()
	_phase = Phase.IDLE
	sequence_restored.emit(completed)


## Maps a generic environment failure without exposing its private state.
func _on_environment_failed(reason: String) -> void:
	if _phase != Phase.IDLE:
		_cleanup_followers()
		_reset_authored_stage()
		_phase = Phase.IDLE
		sequence_restored.emit(false)
	sequence_failed.emit(reason)


## Reads the repeated wall destinations kept human-editable in the scene.
func _collect_authored_mining_targets() -> void:
	_mining_targets.clear()
	if not is_instance_valid(mining_targets_root):
		return
	for child in mining_targets_root.get_children():
		if child is CinematicRatMiningTarget:
			_mining_targets.append(child as CinematicRatMiningTarget)


## Reads the four reusable side/ceiling entry markers in authored order.
func _collect_authored_rat_entry_points() -> void:
	_rat_entry_points.clear()
	if not is_instance_valid(rat_entry_points_root):
		return
	for child in rat_entry_points_root.get_children():
		if child is CinematicRatEntryPoint:
			_rat_entry_points.append(child as CinematicRatEntryPoint)


## Connects shared rat signals while each actor owns its animation.
func _register_rat(rat: CinematicRatMiner) -> void:
	_connect_once(rat.run_target_reached, _on_rat_run_target_reached)
	_connect_once(
		rat.entry_breach_requested,
		_on_rat_entry_breach_requested
	)
	_connect_once(
		rat.entry_breach_finished,
		_on_rat_entry_breach_finished
	)
	_connect_once(
		rat.mining_strike_requested,
		_on_rat_mining_strike_requested
	)
	_connect_once(
		rat.exit_strike_requested,
		_on_rat_exit_strike_requested
	)
	_connect_once(rat.ready_to_exit, _on_rat_ready_to_exit)
	_connect_once(rat.exit_step_finished, _on_rat_exit_step_finished)
	_connect_once(rat.exited, _on_rat_exited)


## Frees every runtime follower and resets the authored lead.
func _cleanup_followers() -> void:
	_stop_rat_spawning()
	if _response_tween != null and _response_tween.is_valid():
		_response_tween.kill()
	_response_tween = null
	_lead_rat_active = false
	_next_rat_sequence_index = 1
	for rat in _active_followers:
		if is_instance_valid(rat):
			rat.queue_free()
	_active_followers.clear()
	_rat_targets.clear()
	_pending_rat_entry_targets.clear()
	_pending_rat_entry_points.clear()
	_opened_rat_target_ids.clear()
	_rat_exit_frontiers.clear()
	_opened_rat_entry_ids.clear()
	if is_instance_valid(lead_rat):
		lead_rat.cancel_action()
		lead_rat.hide()


## Returns one actionable composition error before taking presentation state.
func _get_validation_error() -> String:
	var environment_error := validate_environment()
	if not environment_error.is_empty():
		return environment_error
	var required_nodes: Array[Node] = [
		mining_targets_root,
		lead_rat,
		rat_container,
		rat_spawn_anchor,
		lead_warning_anchor,
		rat_exit_anchor,
		rat_entry_points_root,
	]
	for required_node in required_nodes:
		if not is_instance_valid(required_node):
			return "Layer breakthrough has an unassigned authored node."
	if rat_scene == null:
		return "Layer breakthrough requires a rat PackedScene."
	if _mining_targets.is_empty():
		return "Layer breakthrough requires at least one rat mining target."
	var open_entry_count := 0
	var breach_entry_count := 0
	for entry_point in _rat_entry_points:
		if entry_point.requires_breach:
			breach_entry_count += 1
		else:
			open_entry_count += 1
	if open_entry_count < 1 or breach_entry_count < 3:
		return (
			"Rat entries require one open side route and three foreground "
			+ "breaches."
		)
	if not is_between_stage_strata(rat_entry_behind_draw_order):
		return (
			"Rat entry draw order must sit below promoted layer five and "
			+ "above its backing."
		)
	if lead_rat_appearance != null and rat_appearances.has(lead_rat_appearance):
		return (
			"Rutini's appearance must stay out of the follower cycle so the "
			+ "speaking lead reads as one specific rat."
		)
	if rat_exit_step_distance > rat_indent_diameter - 24.0:
		return (
			"Rat exit steps need 24 pixels of overlap between terrain "
			+ "indents."
		)
	return ""


## Emits a failure before gameplay presentation has been reserved.
func _fail_without_sequence(reason: String) -> void:
	release_entrance_impact()
	push_error(reason)
	sequence_failed.emit(reason)


## Restores all owned presentation before exposing an active failure.
func _fail_active_sequence(reason: String) -> void:
	push_error(reason)
	abort_and_restore()
	sequence_failed.emit(reason)


## Restores authored visibility for replay.
func _reset_authored_stage() -> void:
	for marker: Marker2D in _authored_ground_marker_positions:
		if is_instance_valid(marker):
			marker.position = _authored_ground_marker_positions[marker]
	hide()


## Connects one signal without creating a duplicate route.
func _connect_once(source_signal: Signal, target: Callable) -> void:
	if not source_signal.is_connected(target):
		source_signal.connect(target)
