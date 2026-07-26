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
## The horde has started pouring through. Whoever owns the miner floors him.
signal stampede_started
## The last of them is off screen. The miner can get up.
signal stampede_finished
## The approaching horde is close enough to shake the frame.
signal stampede_rumble_started(strength_px: float)
## The last mouse has passed and the frame can settle.
signal stampede_rumble_finished

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
## Empty, and the procession runs from the moment the shot opens. Named, and the
## tunnel stays empty until that cue arrives: nothing is coming until somebody
## calls them, and then everything does.
##
## Both of the shipped colony beats now use the named form. Rotini's introduction
## was the empty one until Zefin's direction changed it to a stampede - the room
## is empty, he walks up out of nothing, and the horde only pours through on
## "Come on, boys!", so the flood is the answer to the line rather than scenery
## that was already running behind it.
##
## The cue is whatever carries that name - a DialogueLine's Stage Cue, or a
## timeline STAGE_CUE beat - so moving the flood means moving the cue rather than
## editing this stage. It is a lower-case verb phrase and not an animation name;
## an AnimationPlayer clip of the same name still plays if a stage authors one.
@export var procession_cue: StringName
## Advance warning between Rotini's call and the first mouse entering frame.
##
## The rumble starts immediately and stays active through the crossing. Zero
## preserves the immediate procession used by stages without a telegraph.
@export_range(0.0, 6.0, 0.1) var stampede_warning_seconds: float = 0.0
@export_range(0.0, 20.0, 0.25) var stampede_rumble_strength_px: float = 5.0
## Minimum time the spawn tap stays open after the warning. This keeps a fast
## dialogue advance from reducing a whole stampede to its first mouse.
@export_range(0.0, 8.0, 0.1) var stampede_minimum_run_seconds: float = 0.0
## Optional authored stampede sound. Rotini's introduction owns this player so
## audio can be dropped into the scene without changing procession code.
@export var stampede_audio: AudioStreamPlayer
## How long the closing waits for the last of them to leave before it gives up
## and frees them where they stand. Only reached if a follower is stuck, which
## would otherwise hold the encounter open indefinitely.
@export_range(0.5, 12.0, 0.5) var stampede_drain_timeout_seconds: float = 6.0
## Draw order within the rat container for a drawn crowd, and for a single mouse.
##
## Relative to the container, so these order the colony against itself and leave
## its place in the scene alone. The defaults put clumps one layer behind, which
## is the only arrangement that reads: a clump is a still drawing of two dozen
## mice, and anything running in front of it is what makes the whole mass look
## like it is moving.
@export_range(-8, 8, 1) var clump_draw_order: int = -1
@export_range(-8, 8, 1) var single_draw_order: int = 0
## Size multipliers on the rat scene's own appearance scale, for a drawn crowd
## and for a single mouse.
##
## One at both, the default, leaves every follower exactly the size the rat scene
## authored. A stampede wants the clumps much larger than that: the drawing is
## padded to the same registration as a single mouse, so at parity it renders as
## one mouse-high strip of very small mice and the floor shows through between
## the gaps. Scaling it up is what turns the same drawing into a wall.
##
## Kept as multipliers rather than absolute scales so the rat scene stays the one
## place a mouse's size is decided, and a stage only says how much bigger.
@export_range(0.25, 4.0, 0.05) var clump_scale_multiplier: float = 1.0
@export_range(0.25, 4.0, 0.05) var single_scale_multiplier: float = 1.0
## How many receding rows the procession runs in.
##
## One, the default, is the single-file stream every colony ran as before.
##
## More than one is how a crossing crowd gets bulk without oversized art. The
## persistent colony fills its frame with four ranks of ordinary-sized rats, not
## with big ones, and a stream trying to reach the same density by scaling its
## drawings up instead ends with a handful of enormous mice and the floor showing
## between them. Rows put the extra bodies behind, where a crowd keeps them.
@export_range(1, 5, 1) var procession_rows: int = 1
## How far each row back sits above the one in front, and how much smaller.
##
## Positive rise moves a row up the screen, which with the shrink is what reads as
## standing further down the tunnel rather than floating.
@export_range(0.0, 64.0, 1.0) var procession_row_rise_pixels: float = 18.0
@export_range(0.5, 1.0, 0.01) var procession_row_scale_falloff: float = 0.88
## How high a running mouse hops, in pixels. Zero runs them flat along the floor.
##
## Zephan asked for little mice jumping up and around rather than sliding past.
## The arc is per-leg, so a follower crossing the room bounces the whole way
## instead of taking one jump at the start.
@export_range(0.0, 96.0, 1.0) var procession_hop_pixels: float = 0.0

## Growth is bounded by max_live_followers (or the web cap) and pruned on exit.
var _followers: Array[CinematicRatMiner] = []
var _is_spawning: bool = false
var _spawn_generation: int = 0
var _appearance_index: int = 0
var _has_requested_persistent_colony: bool = false
var _is_warning: bool = false
var _is_rumbling: bool = false
var _procession_started_msec: int = 0


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
	if not _is_active or not procession_cue.is_empty():
		return
	_begin_procession()


## Starts the colony on its authored cue, and otherwise defers to the shared
## stage. A procession is a recognized stage action even though it is not an
## AnimationPlayer clip, so the cue reports that it was handled.
func play_cue(cue_id: StringName, line_index: int) -> bool:
	if (
		_is_active
		and not procession_cue.is_empty()
		and cue_id == procession_cue
	):
		_begin_stampede_warning()
		return true
	return super.play_cue(cue_id, line_index)


func play_closing() -> void:
	var should_request_persistence := (
		_is_active and not _has_requested_persistent_colony
	)
	# Let them finish leaving before anything else closes.
	#
	# The conversation ends on the line that started the stampede, so tearing the
	# procession down here would cut it off at its own first frame - the horde
	# would appear and vanish on the same beat the player is still reading. They
	# run off under their own power, and only then does the shot close.
	await _await_stampede_drained()
	_stop_procession()
	if should_request_persistence:
		_has_requested_persistent_colony = true
		persistent_colony_requested.emit()
	await super.play_closing()


## Stops new arrivals and waits for the ones already running to leave the frame.
func _await_stampede_drained() -> void:
	while _is_warning and _is_active:
		await get_tree().process_frame
	var minimum_run_deadline := (
		_procession_started_msec
		+ int(stampede_minimum_run_seconds * 1000.0)
	)
	while (
		_is_spawning
		and _is_active
		and Time.get_ticks_msec() < minimum_run_deadline
	):
		await get_tree().process_frame
	if not _is_spawning and _followers.is_empty():
		_finish_stampede_rumble()
		return
	# Stop the tap first, then wait for the pipe to empty. Leaving it running
	# means new followers keep spawning into a shot that is trying to end.
	_is_spawning = false
	_spawn_generation += 1
	var deadline := (
		Time.get_ticks_msec()
		+ int(stampede_drain_timeout_seconds * 1000.0)
	)
	while Time.get_ticks_msec() < deadline:
		_prune_followers()
		if _followers.is_empty():
			break
		await get_tree().process_frame
		if not _is_active:
			return
	stampede_finished.emit()
	_finish_stampede_rumble()


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
	_procession_started_msec = Time.get_ticks_msec()
	_spawn_generation += 1
	stampede_started.emit()
	_spawn_next_follower(_spawn_generation)


## Telegraphs the off-screen horde before any mouse enters the frame.
func _begin_stampede_warning() -> void:
	if not _is_active or _is_warning or _is_spawning:
		return
	_is_warning = true
	_is_rumbling = true
	stampede_rumble_started.emit(stampede_rumble_strength_px)
	if stampede_audio != null and stampede_audio.stream != null:
		stampede_audio.play()
	if stampede_warning_seconds <= 0.0:
		_finish_stampede_warning()
		return
	get_tree().create_timer(
		stampede_warning_seconds,
		true,
		false,
		true
	).timeout.connect(_finish_stampede_warning, CONNECT_ONE_SHOT)


func _finish_stampede_warning() -> void:
	if not _is_warning:
		return
	_is_warning = false
	if _is_active:
		_begin_procession()


func _finish_stampede_rumble() -> void:
	if not _is_rumbling:
		return
	_is_rumbling = false
	if stampede_audio != null:
		stampede_audio.stop()
	stampede_rumble_finished.emit()


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
	var appearance := rat_appearances[
		_appearance_index % rat_appearances.size()
	]
	var is_clump := (
		appearance != null and appearance.depicted_rat_count > 1
	)
	# Which row back this one runs in. Cycling by spawn index rather than choosing
	# at random keeps every row equally fed, so the crowd stays even instead of
	# clumping into whichever row won the die rolls.
	var row := _appearance_index % maxi(procession_rows, 1)
	# Size before appearance, because set_appearance is what applies the scale to
	# the sprite. Setting it afterwards leaves the actor drawn at the old size
	# until something else reassigns the art.
	rat.appearance_scale *= (
		(clump_scale_multiplier if is_clump else single_scale_multiplier)
		* pow(procession_row_scale_falloff, float(row))
	)
	rat.set_appearance(appearance)
	_appearance_index += 1
	rat.prepare_for_sequence(
		_get_row_entrance(row),
		_appearance_index
	)
	# Preparation restores the actor's authored depth, so the stage-specific
	# crowd order belongs after it. A drawn clump is a backdrop and the single
	# runners in front are what make the whole mass look like it is moving.
	#
	# Taken from depicted_rat_count rather than authored per slot, because "is
	# this a crowd" is already recorded there and saying it twice is one more
	# place to disagree.
	# Rows behind the front one recede a layer each, so a crowd reads as depth
	# rather than as one row drawn on top of another.
	rat.z_index = (
		(clump_draw_order if is_clump else single_draw_order) - row
	)
	_connect_once(rat.reached_wall, _on_follower_reached_wall)
	_connect_once(rat.ready_to_exit, _on_follower_ready_to_exit)
	_connect_once(rat.run_target_reached, _on_follower_run_target_reached)
	_connect_once(rat.strike_contact, _on_follower_strike_contact)
	_followers.append(rat)
	if not procession_mines:
		# Straight across, one leg, no stop at the wall.
		if not rat.start_run_to_target(
			_get_row_exit(row),
			exit_seconds,
			procession_hop_pixels,
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


## Where one row enters, and where it leaves. Rows behind the front sit further
## up the screen by the authored rise, which with their smaller scale is what
## reads as standing further down the tunnel rather than hovering over the floor
## in front of it.
func _get_row_entrance(row: int) -> Vector2:
	return _resolve_grounded_marker(entrance_marker) - Vector2(
		0.0,
		procession_row_rise_pixels * float(row)
	)


func _get_row_exit(row: int) -> Vector2:
	return _resolve_grounded_marker(exit_marker) - Vector2(
		0.0,
		procession_row_rise_pixels * float(row)
	)


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
	_is_warning = false
	_is_spawning = false
	_spawn_generation += 1
	for rat in _followers.duplicate():
		_remove_follower(rat)
	_followers.clear()
	_finish_stampede_rumble()


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
