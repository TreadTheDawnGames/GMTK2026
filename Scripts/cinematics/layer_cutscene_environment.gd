class_name LayerCutsceneEnvironment
extends Node2D

## How it works:
## - A reserved real impact opens the gameplay tunnel before the miner falls.
## - Landing hands this component an already-completed physical entrance.
## - Passage and room bounds stay editable as named markers in the scene.
## - The destination stratum is promoted instantly behind the focused iris.
## - Actor and action marker roots follow the sampled destination floor.
## - The environment emits stage readiness but never owns story or actors.
## - Restore and cancel return the exact miner and terrain presentation.
## - The invariant is that one untouched deepest stratum always backs the room.

signal stage_ready
signal restored(completed: bool)
signal failed(reason: String)

enum EnvironmentPhase {
	IDLE,
	PREPARED,
	OPENING_STAGE,
	STAGE_READY,
	RESTORING,
}

@export_category("Gameplay Presentation References")
@export var miner_rig: MinerRig
@export var terrain_renderer: TerrainLayerRenderer
## Assign the miner rig's authored focus marker so openings follow visual motion.
@export var miner_iris_anchor: Marker2D

@export_category("Tunnel Entrance")
@export var passage_bounds_root: Node2D
@export var passage_bounds_top_left: Marker2D
@export var passage_bounds_bottom_right: Marker2D

@export_category("Destination Stage")
@export var tunnel_bounds_top_left: Marker2D
@export var tunnel_bounds_bottom_right: Marker2D
@export var stage_floor_anchor: Marker2D
@export var actor_markers_root: Node2D
@export var action_markers_root: Node2D

@export_category("Depth Promotion")
@export var deep_layer_palette: PackedColorArray = PackedColorArray([
	Color("6b4554"),
	Color("493044"),
	Color("2b2033"),
	Color("171622"),
])
@export_range(0.05, 2.0, 0.05) var restoration_duration: float = 0.45
@export_range(-128, 128, 1) var stage_miner_draw_order: int = 15

var _environment_phase: EnvironmentPhase = EnvironmentPhase.IDLE
var _entrance_impact_prepared: bool = false
var _entrance_impact_committed: bool = false
var _miner_restore_finished: bool = false
var _terrain_restore_finished: bool = false
var _passage_root_authored_position: Vector2
var _stage_floor_authored_position: Vector2
var _actor_markers_authored_position: Vector2
var _action_markers_authored_position: Vector2
var _miner_root_authored_position: Vector2


## Snapshots marker roots for exact replay cleanup.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(miner_rig):
		_miner_root_authored_position = miner_rig.global_position
	if is_instance_valid(passage_bounds_root):
		_passage_root_authored_position = passage_bounds_root.position
	if is_instance_valid(stage_floor_anchor):
		_stage_floor_authored_position = stage_floor_anchor.position
	if is_instance_valid(actor_markers_root):
		_actor_markers_authored_position = actor_markers_root.position
	if is_instance_valid(action_markers_root):
		_action_markers_authored_position = action_markers_root.position


## Immediately expands and reserves the qualifying real impact before framing.
func prepare_entrance_impact() -> bool:
	if (
		_environment_phase != EnvironmentPhase.IDLE
		or _entrance_impact_prepared
		or _entrance_impact_committed
	):
		return false
	var validation_error := validate_environment()
	if not validation_error.is_empty():
		_fail_environment(validation_error, false)
		return false
	if not terrain_renderer.reserve_latest_impact_for_cinematic():
		return false
	var focus_terrain_position := (
		_get_authoritative_landing_focus_terrain_position()
	)
	if (
		is_nan(focus_terrain_position.x)
		or is_nan(focus_terrain_position.y)
	):
		terrain_renderer.release_reserved_cinematic_impact()
		return false
	if not terrain_renderer.prepare_reserved_impact_for_cinematic_traversal(
		terrain_renderer.profile.get_gameplay_layer_count(),
		focus_terrain_position
	):
		terrain_renderer.release_reserved_cinematic_impact()
		return false
	_entrance_impact_prepared = true
	return true


## Rolls back a pending entrance or releases its committed impact reference.
func release_entrance_impact() -> void:
	if is_instance_valid(terrain_renderer):
		terrain_renderer.release_reserved_cinematic_impact()
	_entrance_impact_prepared = false
	_entrance_impact_committed = false


## Takes visual ownership without replacing the already-prepared real impact.
func prepare_environment() -> bool:
	if (
		_environment_phase != EnvironmentPhase.IDLE
		or not _entrance_impact_prepared
		or _entrance_impact_committed
	):
		return false
	var validation_error := validate_environment()
	if not validation_error.is_empty():
		_fail_environment(validation_error, false)
		return false
	if not miner_rig.begin_cinematic_visual_override():
		_fail_environment(
			"Layer cutscene could not reserve miner presentation.",
			false
		)
		return false
	if not terrain_renderer.begin_cinematic_strata_transition(
		deep_layer_palette
	):
		miner_rig.cancel_cinematic_visual_override()
		_fail_environment(
			"Layer cutscene could not reserve terrain presentation.",
			false
		)
		return false
	var entrance_screen_rect := (
		terrain_renderer.get_latest_foreground_opening_screen_rect()
	)
	if not entrance_screen_rect.has_area():
		terrain_renderer.cancel_cinematic_strata_transition()
		miner_rig.cancel_cinematic_visual_override()
		_fail_environment(
			"Layer cutscene lost its prepared entrance.",
			false
		)
		return false
	# Camera catch-up may move the miner after impact preparation. Anchor the
	# passage to the retained real opening's current screen position so framing
	# cannot separate the traversal geometry from the qualifying hit.
	passage_bounds_root.global_position = entrance_screen_rect.get_center()
	var passage_screen_rect := _get_authored_passage_screen_rect()
	if (
		not entrance_screen_rect.intersects(passage_screen_rect)
		or not terrain_renderer.open_cinematic_traversal_passage(
			passage_screen_rect,
			terrain_renderer.profile.get_gameplay_layer_count()
		)
	):
		terrain_renderer.cancel_cinematic_strata_transition()
		miner_rig.cancel_cinematic_visual_override()
		_fail_environment(
			"Layer cutscene could not open its traversal passage.",
			false
		)
		return false
	if not terrain_renderer.commit_reserved_cinematic_impact():
		terrain_renderer.cancel_cinematic_strata_transition()
		miner_rig.cancel_cinematic_visual_override()
		_fail_environment(
			"Layer cutscene could not commit its prepared entrance.",
			false
		)
		return false
	_entrance_impact_committed = true
	_environment_phase = EnvironmentPhase.PREPARED
	return true


## Promotes the already-entered tunnel and emits stage_ready after grounding.
func open_environment_stage() -> bool:
	if _environment_phase != EnvironmentPhase.PREPARED:
		return false
	_environment_phase = EnvironmentPhase.OPENING_STAGE
	_open_destination_stage.call_deferred()
	return true


## Fades the original presentation back and emits restored after both owners finish.
func restore_environment() -> bool:
	if (
		_environment_phase == EnvironmentPhase.IDLE
		or _environment_phase == EnvironmentPhase.RESTORING
	):
		return false
	_environment_phase = EnvironmentPhase.RESTORING
	_miner_restore_finished = false
	_terrain_restore_finished = false
	var miner_restore := miner_rig.restore_cinematic_visual(
		restoration_duration
	)
	var terrain_restore := terrain_renderer.restore_cinematic_strata(
		restoration_duration
	)
	if miner_restore == null:
		_miner_restore_finished = true
	else:
		miner_restore.finished.connect(
			_on_miner_restore_finished,
			CONNECT_ONE_SHOT
		)
	if terrain_restore == null:
		_terrain_restore_finished = true
	else:
		terrain_restore.finished.connect(
			_on_terrain_restore_finished,
			CONNECT_ONE_SHOT
		)
	_try_finish_environment_restore()
	return true


## Immediately restores production presentation after interruption or failure.
func cancel_environment() -> void:
	if _environment_phase == EnvironmentPhase.IDLE:
		release_entrance_impact()
		_reset_environment_markers()
		return
	if is_instance_valid(terrain_renderer):
		terrain_renderer.cancel_cinematic_strata_transition()
	if is_instance_valid(miner_rig):
		miner_rig.cancel_cinematic_visual_override()
	_reset_environment_markers()
	_environment_phase = EnvironmentPhase.IDLE
	restored.emit(false)


## Reports whether this component currently owns miner and terrain presentation.
func is_environment_active() -> bool:
	return _environment_phase != EnvironmentPhase.IDLE


## Returns the normalized editor-authored destination room in screen coordinates.
func get_cutscene_room_screen_rect() -> Rect2:
	return _get_rect_from_markers(
		tunnel_bounds_top_left,
		tunnel_bounds_bottom_right
	)


## Insets the destination room for actor roots and action arcs.
func get_stage_motion_bounds(margin: float = 0.0) -> Rect2:
	var room_rect := get_cutscene_room_screen_rect()
	if not room_rect.has_area():
		return Rect2()
	var maximum_inset := maxf(
		minf(room_rect.size.x, room_rect.size.y) * 0.5 - 0.5,
		0.0
	)
	return room_rect.grow(-minf(maxf(margin, 0.0), maximum_inset))


## Samples the production destination floor at one screen-space x coordinate.
func get_stage_floor_screen_y(screen_x: float) -> float:
	if not is_instance_valid(terrain_renderer):
		return NAN
	return terrain_renderer.get_cinematic_cutscene_floor_screen_y(screen_x)


## Reports whether an actor draws between the promoted room and its backing.
func is_between_stage_strata(draw_order: int) -> bool:
	if (
		not is_instance_valid(terrain_renderer)
		or terrain_renderer.profile == null
	):
		return false
	return (
		draw_order < terrain_renderer.profile.get_layer_z_index(0)
		and draw_order > terrain_renderer.profile.get_layer_z_index(1)
	)


## Grounds one concrete actor/action marker on the production room floor.
func ground_stage_marker(
	marker: Marker2D,
	floor_offset_y: float = 0.0,
	motion_margin: float = 0.0
) -> bool:
	if not is_instance_valid(marker):
		return false
	var support_y := get_stage_floor_screen_y(marker.global_position.x)
	if is_nan(support_y):
		return false
	marker.global_position.y = support_y + floor_offset_y
	if motion_margin > 0.0:
		var motion_bounds := get_stage_motion_bounds(motion_margin)
		if not motion_bounds.has_area():
			return false
		marker.global_position = Vector2(
			clampf(
				marker.global_position.x,
				motion_bounds.position.x,
				motion_bounds.end.x
			),
			clampf(
				marker.global_position.y,
				motion_bounds.position.y,
				motion_bounds.end.y
			)
		)
	return true


## Returns one actionable editor composition error without taking presentation.
func validate_environment() -> String:
	var required_nodes: Array[Node] = [
		miner_rig,
		terrain_renderer,
		miner_iris_anchor,
		passage_bounds_root,
		passage_bounds_top_left,
		passage_bounds_bottom_right,
		tunnel_bounds_top_left,
		tunnel_bounds_bottom_right,
		stage_floor_anchor,
		actor_markers_root,
		action_markers_root,
	]
	for required_node in required_nodes:
		if not is_instance_valid(required_node):
			return "Layer cutscene environment has an unassigned authored node."
	if not is_instance_valid(miner_rig.landing_foot_anchor):
		return "Layer cutscene environment requires the miner's landing foot anchor."
	if terrain_renderer.profile == null:
		return "Layer cutscene environment requires a terrain layer profile."
	var gameplay_layer_count := (
		terrain_renderer.profile.get_gameplay_layer_count()
	)
	var total_layer_count := terrain_renderer.profile.get_layer_count()
	if gameplay_layer_count <= 0:
		return "Layer cutscene requires at least one gameplay layer."
	if total_layer_count < gameplay_layer_count + 2:
		return (
			"Layer cutscene needs one destination stratum and one untouched "
			+ "backing stratum behind gameplay."
		)
	if (
		restoration_duration <= 0.0
		or is_nan(restoration_duration)
		or is_inf(restoration_duration)
	):
		return "Layer cutscene restoration must be positive and finite."
	if not _get_authored_passage_screen_rect().has_area():
		return "Layer cutscene passage bounds must enclose a positive area."
	if not get_cutscene_room_screen_rect().has_area():
		return "Layer cutscene room bounds must enclose a positive area."
	return ""


## Resolves the post-hit body center in terrain space, independent of camera lag.
func _get_authoritative_landing_focus_terrain_position() -> Vector2:
	var game_state: RunState = RunState.get_global(self)
	if (
		game_state == null
		or terrain_renderer == null
		or terrain_renderer.terrain_manager == null
		or terrain_renderer.terrain_manager.config == null
		or miner_rig == null
		or not is_instance_valid(miner_rig.landing_foot_anchor)
		or not is_instance_valid(miner_iris_anchor)
	):
		return Vector2(NAN, NAN)
	var cell_size := float(
		terrain_renderer.terrain_manager.config.terrain_cell_world_size
	)
	var target_terrain_position := Vector2(
		float(game_state.mining_x) * cell_size,
		float(game_state.mining_y) * cell_size
	)
	var stable_focus_screen_position := (
		_miner_root_authored_position
		+ miner_rig.visual_root.position
		+ miner_iris_anchor.position
	)
	var mining_target_reference_screen := Vector2(
		terrain_renderer.terrain_manager.config.terrain_screen_center_x,
		terrain_renderer.terrain_manager.config.mining_face_screen_y
	)
	return (
		target_terrain_position
		+ stable_focus_screen_position
		- mining_target_reference_screen
	)


## Opens the room after gameplay has already completed the physical cave fall.
func _open_destination_stage() -> void:
	if _environment_phase != EnvironmentPhase.OPENING_STAGE:
		return
	var last_gameplay_layer_index := (
		terrain_renderer.profile.get_gameplay_layer_count() - 1
	)
	if not terrain_renderer.promote_cinematic_strata_through(
		last_gameplay_layer_index
	):
		_fail_environment(
			"Could not present the tunnel's destination stratum.",
			true
		)
		return
	if not terrain_renderer.open_cinematic_cutscene_room(
		get_cutscene_room_screen_rect()
	):
		_fail_environment(
			"Could not open the destination cutscene room.",
			true
		)
		return
	if not _ground_stage_roots():
		_fail_environment(
			"Could not ground the cutscene stage on the production floor.",
			true
		)
		return
	if not miner_rig.place_cinematic_foot_at(
		stage_floor_anchor.global_position,
		stage_miner_draw_order
	):
		_fail_environment(
			"Layer cutscene lost miner ownership before stage readiness.",
			true
		)
		return
	_environment_phase = EnvironmentPhase.STAGE_READY
	stage_ready.emit()


## Moves both marker roots by the production floor delta without moving the room.
func _ground_stage_roots() -> bool:
	var support_y := get_stage_floor_screen_y(
		stage_floor_anchor.global_position.x
	)
	if is_nan(support_y):
		return false
	var floor_delta := support_y - stage_floor_anchor.global_position.y
	stage_floor_anchor.global_position.y = support_y
	actor_markers_root.global_position.y += floor_delta
	action_markers_root.global_position.y += floor_delta
	return true


func _get_authored_passage_screen_rect() -> Rect2:
	return _get_rect_from_markers(
		passage_bounds_top_left,
		passage_bounds_bottom_right
	)


func _get_rect_from_markers(
	first_marker: Marker2D,
	second_marker: Marker2D
) -> Rect2:
	if (
		not is_instance_valid(first_marker)
		or not is_instance_valid(second_marker)
	):
		return Rect2()
	var first := first_marker.global_position
	var second := second_marker.global_position
	var minimum := Vector2(
		minf(first.x, second.x),
		minf(first.y, second.y)
	)
	var maximum := Vector2(
		maxf(first.x, second.x),
		maxf(first.y, second.y)
	)
	return Rect2(minimum, maximum - minimum)


func _on_miner_restore_finished() -> void:
	_miner_restore_finished = true
	_try_finish_environment_restore()


func _on_terrain_restore_finished() -> void:
	_terrain_restore_finished = true
	_try_finish_environment_restore()


func _try_finish_environment_restore() -> void:
	if (
		_environment_phase != EnvironmentPhase.RESTORING
		or not _miner_restore_finished
		or not _terrain_restore_finished
	):
		return
	_reset_environment_markers()
	_environment_phase = EnvironmentPhase.IDLE
	restored.emit(true)


func _reset_environment_markers() -> void:
	release_entrance_impact()
	if is_instance_valid(passage_bounds_root):
		passage_bounds_root.position = _passage_root_authored_position
	if is_instance_valid(stage_floor_anchor):
		stage_floor_anchor.position = _stage_floor_authored_position
	if is_instance_valid(actor_markers_root):
		actor_markers_root.position = _actor_markers_authored_position
	if is_instance_valid(action_markers_root):
		action_markers_root.position = _action_markers_authored_position


func _fail_environment(reason: String, restore_active: bool) -> void:
	push_error(reason)
	if restore_active:
		if is_instance_valid(terrain_renderer):
			terrain_renderer.cancel_cinematic_strata_transition()
		if is_instance_valid(miner_rig):
			miner_rig.cancel_cinematic_visual_override()
	_reset_environment_markers()
	_environment_phase = EnvironmentPhase.IDLE
	failed.emit(reason)
