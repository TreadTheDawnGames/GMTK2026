class_name RatColonyEncounterStage
extends CharacterEncounterStage

## How it works:
## - The encounter presenter is the lead rat already waiting by the miner.
## - Opening, or a named cue, starts a bounded stream of mouse actors.
## - Each follower runs to the work marker, mines, then exits to the right.
## - Strike contacts reuse the shared terrain particles, smoke, and shake route.
## - Closing or cancellation stops timers and frees every transient follower.
## - Owned state is capped to max_live_followers and pruned on every exit.
## - The stage never changes terrain layers or gameplay collision.
## - The invariant is that no transient rat survives the encounter.

const RatAppearanceType = preload(
	"res://Scripts/cinematics/cinematic_rat_appearance.gd"
)

## Requests the separate gameplay colony only after the encounter closes cleanly.
signal persistent_colony_requested

@export_category("Rat Colony")
@export var rat_scene: PackedScene
@export var rat_container: Node2D
@export var rat_appearances: Array[RatAppearanceType] = []
@export_range(1, 12, 1) var max_live_followers: int = 7
@export_range(1, 12, 1) var web_max_live_followers: int = 5
@export_range(0.05, 2.0, 0.05) var spawn_interval_seconds: float = 0.45
@export_range(0.05, 3.0, 0.05) var run_seconds: float = 0.65
@export_range(0.05, 2.0, 0.05) var exit_seconds: float = 0.45
@export_range(0.0, 0.5, 0.01) var strike_interval_seconds: float = 0.08
@export_range(1, 6, 1) var strikes_per_rat: int = 2
@export_range(-96.0, 32.0, 1.0) var floor_offset_y: float = -29.0
## Whether a follower stops at the work marker to mine before leaving.
##
## On, the colony is digging its way down and the pauses are the point. Off, the
## tunnel is a road and they simply cross it: Rotini's introduction is traffic
## passing through, and a rat that stops to swing at a wall on the way reads as
## a different scene. Everything else about the procession is shared.
@export var procession_mines: bool = true
## The cue that lets the colony in, instead of it arriving with the opening.
##
## Empty, and the procession runs from the moment the shot opens. That is
## Rotini's introduction: the tunnel is already somebody's road, the traffic is
## the first thing the player sees, and his line explains something already on
## screen. Named, and the tunnel stays empty until that cue arrives, which is the
## colony beat: nothing is coming until he calls them, and then everything does.
##
## The cue is whatever carries that name - a DialogueLine's Stage Cue, or a
## timeline STAGE_CUE beat - so moving the flood means moving the cue rather than
## editing this stage. It is a lower-case verb phrase and not an animation name;
## an AnimationPlayer clip of the same name still plays if a stage authors one.
@export var procession_cue: StringName

## Growth is bounded by max_live_followers (or the web cap) and pruned on exit.
var _followers: Array[CinematicRatMiner] = []
var _is_spawning: bool = false
var _spawn_generation: int = 0
var _appearance_index: int = 0
var _has_requested_persistent_colony: bool = false


func prepare(
	presenter: CharacterPresenter,
	floor_sampler: Callable
) -> bool:
	if not super.prepare(presenter, floor_sampler):
		return false
	_stop_procession()
	_has_requested_persistent_colony = false
	return true


## Starts the colony only after the lead rat has reached the conversation spot,
## unless this stage waits for a cue to let them in.
func play_opening() -> void:
	await super.play_opening()
	if not procession_cue.is_empty():
		return
	_begin_procession()


## Starts the colony on its authored cue, and otherwise defers to the shared
## stage. Returning what the base returned keeps a caller's "did an animation
## play" answer honest: starting rats is not playing a clip.
func play_cue(cue_id: StringName, line_index: int) -> bool:
	var played_animation := super.play_cue(cue_id, line_index)
	if not procession_cue.is_empty() and cue_id == procession_cue:
		_begin_procession()
	return played_animation


func play_closing() -> void:
	var should_request_persistence := (
		_is_active and not _has_requested_persistent_colony
	)
	_stop_procession()
	if should_request_persistence:
		_has_requested_persistent_colony = true
		persistent_colony_requested.emit()
	await super.play_closing()


func cancel_and_restore() -> void:
	_stop_procession()
	super.cancel_and_restore()


func _exit_tree() -> void:
	_stop_procession()


func validate_stage() -> String:
	var shared_error := super.validate_stage()
	if not shared_error.is_empty():
		return shared_error
	if rat_scene == null or not is_instance_valid(rat_container):
		return "Rat colony stage requires its rat scene and container."
	if rat_appearances.is_empty():
		return "Rat colony stage requires at least one rat appearance."
	return ""


## Opens the stream. Idempotent, because a cue can be re-presented when a player
## walks the dialogue back over the line that carries it.
func _begin_procession() -> void:
	if not _is_active or _is_spawning:
		return
	_is_spawning = true
	_spawn_generation += 1
	_spawn_next_follower(_spawn_generation)


## Reuses one timer at a time; the generation rejects stale callbacks.
func _spawn_next_follower(expected_generation: int) -> void:
	if (
		not _is_spawning
		or expected_generation != _spawn_generation
		or not _is_active
	):
		return
	_prune_followers()
	if _followers.size() < _get_live_follower_cap():
		_spawn_follower()
	get_tree().create_timer(
		spawn_interval_seconds,
		true,
		false,
		true
	).timeout.connect(
		_spawn_next_follower.bind(expected_generation),
		CONNECT_ONE_SHOT
	)


func _spawn_follower() -> void:
	var rat := rat_scene.instantiate() as CinematicRatMiner
	if rat == null:
		push_error("Rat colony stage could not instantiate its rat scene.")
		_is_spawning = false
		return
	rat_container.add_child(rat)
	rat.set_appearance(
		rat_appearances[_appearance_index % rat_appearances.size()]
	)
	_appearance_index += 1
	rat.prepare_for_sequence(
		_resolve_grounded_marker(entrance_marker),
		_appearance_index
	)
	_connect_once(rat.reached_wall, _on_follower_reached_wall)
	_connect_once(rat.ready_to_exit, _on_follower_ready_to_exit)
	_connect_once(rat.run_target_reached, _on_follower_run_target_reached)
	_connect_once(rat.strike_contact, _on_follower_strike_contact)
	_followers.append(rat)
	if not procession_mines:
		# Straight across, one leg, no stop at the wall.
		if not rat.start_run_to_target(
			_resolve_grounded_marker(exit_marker),
			exit_seconds,
			0.0,
			NAN,
			_floor_sampler
		):
			_remove_follower(rat)
		return
	if not rat.start_run_to_wall(
		work_marker.global_position.x,
		run_seconds,
		_floor_sampler
	):
		_remove_follower(rat)


func _on_follower_reached_wall(rat: CinematicRatMiner) -> void:
	if not is_instance_valid(rat) or not _followers.has(rat):
		return
	rat.start_mining_then_exit(
		strikes_per_rat,
		_resolve_grounded_marker(exit_marker),
		exit_seconds,
		strike_interval_seconds
	)


func _on_follower_ready_to_exit(rat: CinematicRatMiner) -> void:
	if not is_instance_valid(rat) or not _followers.has(rat):
		return
	if not rat.start_run_to_target(
		_resolve_grounded_marker(exit_marker),
		exit_seconds,
		0.0,
		NAN,
		_floor_sampler
	):
		_remove_follower(rat)


func _on_follower_run_target_reached(rat: CinematicRatMiner) -> void:
	if not is_instance_valid(rat) or not _followers.has(rat):
		return
	if not _has_reached_exit(rat):
		return
	_remove_follower(rat)


## Reports whether a follower has actually made it to the exit, whichever way the
## procession runs.
##
## This used to ask only whether the rat had got far enough to the RIGHT, which
## silently assumed every colony leaves the way the first one did. Run them the
## other way and no follower is ever retired: they arrive, the test says they are
## still short of the exit, and they pile up at the mouth until the cap stops the
## stream. The direction is taken from the markers themselves so a stage that
## moves its exit cannot disagree with the code that retires actors at it.
func _has_reached_exit(rat: CinematicRatMiner) -> bool:
	var exit_x := exit_marker.global_position.x
	if exit_x < entrance_marker.global_position.x:
		return rat.global_position.x <= exit_x + 1.0
	return rat.global_position.x >= exit_x - 1.0


func _on_follower_strike_contact(screen_position: Vector2) -> void:
	presentation_strike_requested.emit(screen_position)


func _resolve_grounded_marker(marker: Marker2D) -> Vector2:
	var position := marker.global_position
	if _floor_sampler.is_valid():
		var sampled_y: float = _floor_sampler.call(position.x)
		if not is_nan(sampled_y):
			position.y = sampled_y + floor_offset_y
	return position


func _get_live_follower_cap() -> int:
	return (
		mini(max_live_followers, web_max_live_followers)
		if OS.has_feature("web")
		else max_live_followers
	)


func _stop_procession() -> void:
	_is_spawning = false
	_spawn_generation += 1
	for rat in _followers.duplicate():
		_remove_follower(rat)
	_followers.clear()


func _prune_followers() -> void:
	for rat in _followers.duplicate():
		if not is_instance_valid(rat):
			_followers.erase(rat)


func _remove_follower(rat: CinematicRatMiner) -> void:
	_followers.erase(rat)
	if not is_instance_valid(rat):
		return
	rat.cancel_action()
	rat.queue_free()


func _connect_once(source_signal: Signal, target: Callable) -> void:
	if not source_signal.is_connected(target):
		source_signal.connect(target)
