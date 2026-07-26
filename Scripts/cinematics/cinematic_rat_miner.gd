class_name CinematicRatMiner
extends Node2D

## How it works:
## - A coordinator places this authored rat and starts its run.
## - AnimationPlayer owns transform choreography and strike-contact timing.
## - ActorSpriteView optionally supplies named visible art for each action.
## - The strike clip emits its contact point for shared terrain-hit effects.
## - Shared shader depth and a floor-stationary shadow provide 2.5D grounding.
## - Mining repeats, then remains visible until the rat mines offstage right.
## - This node never changes terrain or gameplay state.

const SpeechReactionType = preload(
	"res://Scripts/dialogue/speech_reaction.gd"
)
const RatAppearanceType = preload(
	"res://Scripts/cinematics/cinematic_rat_appearance.gd"
)
const GroundWalkType = preload(
	"res://Scripts/cinematics/ground_walk.gd"
)

signal reached_wall(rat: CinematicRatMiner)
signal run_target_reached(rat: CinematicRatMiner)
signal strike_contact(screen_position: Vector2)
signal mining_strike_requested(
	rat: CinematicRatMiner,
	screen_position: Vector2
)
signal entry_breach_requested(
	rat: CinematicRatMiner,
	screen_position: Vector2
)
signal entry_breach_finished(rat: CinematicRatMiner)
signal exit_strike_requested(
	rat: CinematicRatMiner,
	screen_position: Vector2,
	requested_root_x: float
)
signal ready_to_exit(rat: CinematicRatMiner)
signal exit_step_finished(rat: CinematicRatMiner)
signal jump_finished(rat: CinematicRatMiner)
signal exited(rat: CinematicRatMiner)

enum Action {
	IDLE,
	RUNNING,
	BREACHING,
	MINING,
	EXITING,
}

@export_category("References")
@export var animation_player: AnimationPlayer
@export var visual_root: Node2D
@export var strike_anchor: Marker2D
@export var actor_sprite: Sprite2D
@export var actor_sprite_view: ActorSpriteView
@export var speech_reaction: SpeechReactionType
@export var ground_shadow: ActorGroundShadow
@export var default_appearance: RatAppearanceType

@export_category("Appearance")
@export_range(0.01, 0.75, 0.005) var appearance_scale: float = 0.26

@export_category("Motion")
@export_range(0.05, 2.0, 0.05) var jump_duration: float = 0.45
@export_range(0.0, 240.0, 1.0) var jump_height: float = 72.0
## How far a mouse squeezing out of a fresh wall hole rises before gravity wins.
## Zero makes it drop straight out; the fall accelerates either way.
@export_range(0.0, 120.0, 1.0) var wall_pop_rise: float = 24.0
## Holds the landing squash after a fall so the mouse visibly hits the ground
## before its owner sends it running. Must not outlast the "land" clip.
@export_range(0.0, 1.0, 0.01) var land_recovery_seconds: float = 0.24

@export_category("Depth Order")
@export_range(-128, 128, 1) var front_draw_order: int = 16
@export_range(-128, 128, 1) var behind_draw_order: int = 3

var sequence_index: int = -1
var _action: Action = Action.IDLE
var _action_tween: Tween
var _remaining_strikes: int = 0
var _exit_target: Vector2
var _exit_duration: float = 0.4
var _exit_step_target: Vector2
var _exit_step_is_final: bool = false
var _exit_step_approved: bool = false
var _entry_breach_contact: Vector2
var _strike_pause: float = 0.08
var _action_generation: int = 0
var _authored_z_index: int
var _authored_z_as_relative: bool
var _emit_reached_wall_on_target: bool = false
var _emit_jump_finished_on_target: bool = false
var _land_on_target: bool = false
var _motion_bounds := Rect2()
var _idle_texture: Texture2D
var _strike_texture: Texture2D
var _reduce_motion_enabled: bool = false


## Owns the AnimationPlayer completion route for repeated mining strikes.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_authored_z_index = z_index
	_authored_z_as_relative = z_as_relative
	if default_appearance != null:
		set_appearance(default_appearance)
	elif is_instance_valid(actor_sprite):
		_idle_texture = actor_sprite.texture
	if (
		is_instance_valid(animation_player)
		and not animation_player.animation_finished.is_connected(
			_on_animation_finished
		)
	):
		animation_player.animation_finished.connect(
			_on_animation_finished
		)
	hide()


## Removes arcs, walking bob, and speech bounce without changing destinations.
func set_reduce_motion_enabled(enabled: bool) -> void:
	_reduce_motion_enabled = enabled
	if is_instance_valid(speech_reaction):
		speech_reaction.set_reduce_motion_enabled(enabled)


## Resets the actor at an authored screen-space procession start.
func prepare_for_sequence(
	screen_position: Vector2,
	new_sequence_index: int
) -> void:
	cancel_action()
	sequence_index = new_sequence_index
	global_position = screen_position
	rotation = 0.0
	scale = Vector2.ONE
	restore_visual_depth()
	_action = Action.IDLE
	_show_idle_appearance()
	show()
	if is_instance_valid(animation_player):
		animation_player.play(&"idle")


## Constrains authored entrances and jumps to the already-open tunnel room.
func set_tunnel_motion_bounds(screen_rect: Rect2) -> void:
	_motion_bounds = screen_rect
	if _motion_bounds.has_area():
		global_position = _clamp_to_motion_bounds(global_position)


## Applies one paired color/strike appearance without changing choreography.
func set_appearance(appearance: RatAppearanceType) -> bool:
	if (
		not is_instance_valid(actor_sprite)
		or appearance == null
		or appearance.idle_texture == null
		or appearance.strike_texture == null
	):
		return false
	_idle_texture = appearance.idle_texture
	_strike_texture = appearance.strike_texture
	actor_sprite.texture = _idle_texture
	actor_sprite.scale = Vector2.ONE * appearance_scale
	actor_sprite.modulate = Color.WHITE
	_show_idle_appearance()
	return true


## Sets the generalized cutscene-light shader's recession without tinting art.
##
## Both transient encounter rows and the persistent mining formation call this
## same contract, so a mouse cannot use one depth language in the cutscene and
## another after it joins the player.
func set_visual_depth_ratio(depth_ratio: float) -> void:
	if not is_instance_valid(actor_sprite):
		return
	var depth_material := actor_sprite.material as ShaderMaterial
	if depth_material == null:
		return
	depth_material.set_shader_parameter(
		&"depth_amount",
		clampf(depth_ratio, 0.0, 1.0)
	)


## Mirrors the production miner's grounded travel without taking motion ownership.
func set_ground_travel_active(is_walking: bool) -> void:
	if (
		_action != Action.IDLE
		or not visible
		or not is_instance_valid(animation_player)
	):
		return
	var requested_animation := &"run" if is_walking else &"idle"
	if animation_player.current_animation != requested_animation:
		animation_player.play(requested_animation)


## Runs left-to-right until the actor reaches the authored mining wall.
func start_run_to_wall(
	wall_screen_x: float,
	duration: float,
	floor_sampler: Callable = Callable(),
	arc_height: float = 0.0
) -> bool:
	var started := start_run_to_target(
		Vector2(wall_screen_x, global_position.y),
		duration,
		arc_height,
		NAN,
		floor_sampler
	)
	_emit_reached_wall_on_target = started
	return started


## Runs to any target, optionally following an arc whose peak has an authored X.
func start_run_to_target(
	target: Vector2,
	duration: float,
	arc_height: float = 0.0,
	jump_peak_x: float = NAN,
	floor_sampler: Callable = Callable()
) -> bool:
	if _action != Action.IDLE or not is_instance_valid(visual_root):
		return false
	reset_speech_motion()
	_emit_reached_wall_on_target = false
	_emit_jump_finished_on_target = false
	var start_position := global_position
	var bounded_target := _clamp_to_motion_bounds(target)
	var resolved_duration := maxf(duration, 0.01)
	var resolved_height := (
		0.0
		if _reduce_motion_enabled
		else maxf(arc_height, 0.0)
	)
	_set_ground_shadow_arc(0.0, resolved_height)
	var horizontal_direction := bounded_target.x - start_position.x
	set_facing_direction(
		0
		if is_zero_approx(horizontal_direction)
		else (1 if horizontal_direction > 0.0 else -1)
	)
	var peak_progress := _resolve_jump_peak_progress(
		start_position.x,
		bounded_target.x,
		jump_peak_x
	)
	_action = Action.RUNNING
	_show_walk_appearance()
	if is_instance_valid(animation_player):
		if resolved_height > 0.0:
			animation_player.play(
				&"jump",
				-1.0,
				0.5 / resolved_duration
			)
		else:
			animation_player.play(&"run")
	if resolved_height > 0.0:
		_action_tween = create_tween()
		_action_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_action_tween.tween_method(
			_set_run_progress.bind(
				start_position,
				bounded_target,
				resolved_height,
				peak_progress
			),
			0.0,
			1.0,
			resolved_duration
		).set_trans(Tween.TRANS_LINEAR)
	else:
		var ground_path := GroundWalkType.build_path(
			start_position,
			bounded_target,
			floor_sampler,
			GroundWalkType.DEFAULT_STRIDE_PIXELS
		)
		for point_index in range(ground_path.size()):
			ground_path[point_index] = _clamp_to_motion_bounds(
				ground_path[point_index]
			)
		_action_tween = GroundWalkType.walk_along(
			self,
			ground_path,
			resolved_duration,
			(
				0.0
				if _reduce_motion_enabled
				else GroundWalkType.DEFAULT_STEP_HEIGHT
			)
		)
	_action_tween.tween_callback(_finish_run_to_target)
	return true


## Pops out of an opened wall hole and falls under gravity onto the stage floor.
func start_wall_emergence(
	landing_position: Vector2,
	duration: float
) -> bool:
	if _action != Action.IDLE or not is_instance_valid(visual_root):
		return false
	reset_speech_motion()
	_emit_reached_wall_on_target = false
	_emit_jump_finished_on_target = false
	var start_position := global_position
	var landing_target := _clamp_to_motion_bounds(landing_position)
	var resolved_duration := maxf(duration, 0.01)
	_set_ground_shadow_arc(0.0, wall_pop_rise)
	var horizontal_direction := landing_target.x - start_position.x
	set_facing_direction(
		0
		if is_zero_approx(horizontal_direction)
		else (1 if horizontal_direction > 0.0 else -1)
	)
	_action = Action.RUNNING
	_show_walk_appearance()
	if is_instance_valid(animation_player):
		animation_player.play(&"jump", -1.0, 0.5 / resolved_duration)
	_action_tween = create_tween()
	_action_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_land_on_target = true
	_action_tween.tween_method(
		_set_emergence_progress.bind(start_position, landing_target),
		0.0,
		1.0,
		resolved_duration
	).set_trans(Tween.TRANS_LINEAR)
	_action_tween.tween_callback(_finish_run_to_target)
	return true


## Repeats authored strikes, then keeps mining beyond the right edge.
func start_mining_then_exit(
	strike_count: int,
	exit_screen_position: Vector2,
	exit_time: float,
	strike_interval: float
) -> bool:
	if _action != Action.IDLE:
		return false
	_set_ground_shadow_arc(0.0, 0.0)
	_remaining_strikes = maxi(strike_count, 1)
	_exit_target = exit_screen_position
	_exit_duration = maxf(exit_time, 0.01)
	_strike_pause = maxf(strike_interval, 0.0)
	_action = Action.MINING
	_play_next_strike()
	return true


## Plays one entry strike before the coordinator opens the authored breach.
func start_entry_breach(
	contact_screen_position: Vector2,
	playback_speed: float = 1.0
) -> bool:
	if (
		_action != Action.IDLE
		or not is_instance_valid(animation_player)
		or is_nan(contact_screen_position.x)
		or is_nan(contact_screen_position.y)
	):
		return false
	_set_ground_shadow_arc(0.0, 0.0)
	_entry_breach_contact = contact_screen_position
	_action = Action.BREACHING
	_play_strike_pose()
	animation_player.play(
		&"strike",
		-1.0,
		maxf(playback_speed, 0.1)
	)
	return true


## Exposes the authored offscreen destination without leaking mutable actor state.
func get_exit_target() -> Vector2:
	return _exit_target


## Starts one wall-approved exit step; the coordinator opens terrain first.
func start_exit_step(
	screen_position: Vector2,
	is_final_step: bool
) -> bool:
	if (
		_action != Action.IDLE
		or not is_instance_valid(animation_player)
		or screen_position.x <= global_position.x
	):
		return false
	_exit_step_target = screen_position
	_exit_step_is_final = is_final_step
	_exit_step_approved = false
	_action = Action.EXITING
	_play_strike_pose()
	animation_player.play(&"strike")
	return true


## Allows the pending root step only after the production mask opened ahead.
func approve_exit_step() -> bool:
	if _action != Action.EXITING:
		return false
	_exit_step_approved = true
	return true


## Jumps along a dynamic screen-space arc and returns an awaitable tween.
func jump_to(
	screen_position: Vector2,
	duration: float = -1.0,
	arc_height: float = -1.0
) -> Tween:
	var resolved_duration := (
		jump_duration if duration <= 0.0 else duration
	)
	var resolved_height := (
		jump_height if arc_height < 0.0 else arc_height
	)
	if not start_run_to_target(
		screen_position,
		resolved_duration,
		resolved_height
	):
		return null
	_emit_jump_finished_on_target = true
	return _action_tween


## Switches the whole actor between authored front and behind draw orders.
func set_behind_stage(is_behind: bool) -> void:
	set_plane_draw_order(
		behind_draw_order if is_behind else front_draw_order
	)


## Applies an exact non-relative draw order for crossing visual planes.
func set_plane_draw_order(draw_order: int) -> void:
	z_as_relative = false
	z_index = draw_order


## Restores the draw-order mode authored on the reusable actor scene.
func restore_visual_depth() -> void:
	z_index = _authored_z_index
	z_as_relative = _authored_z_as_relative


## Faces the visible mouse along its current root travel direction.
func set_facing_direction(direction: int) -> void:
	if not is_instance_valid(visual_root) or direction == 0:
		return
	visual_root.scale.x = absf(visual_root.scale.x) * signi(direction)


## Stops pending motion and restores the scene-authored neutral pose.
func cancel_action() -> void:
	_action_generation += 1
	reset_speech_motion()
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()
	_action_tween = null
	_remaining_strikes = 0
	_exit_step_approved = false
	_exit_step_is_final = false
	_entry_breach_contact = Vector2.ZERO
	_action = Action.IDLE
	_emit_reached_wall_on_target = false
	_emit_jump_finished_on_target = false
	_land_on_target = false
	_set_ground_shadow_arc(0.0, 0.0)
	restore_visual_depth()
	_show_idle_appearance()
	if is_instance_valid(animation_player):
		animation_player.stop()
		animation_player.play(&"RESET")


## Restores the visual-only dialogue reaction before the next rat action.
func reset_speech_motion() -> void:
	if is_instance_valid(speech_reaction):
		speech_reaction.reset_speech_motion()
	_show_idle_appearance()


## Bounces the rat presentation without moving its procession root.
func react_to_presented_line() -> void:
	if is_instance_valid(speech_reaction):
		speech_reaction.react_to_presented_line()


## Reports whether this actor can display an optional dialogue pose.
func has_pose(pose_name: StringName) -> bool:
	return (
		actor_sprite_view != null
		and actor_sprite_view.has_pose(pose_name)
	)


## Displays an optional dialogue pose without changing strike contact timing.
func play_pose(pose_name: StringName) -> bool:
	return (
		actor_sprite_view != null
		and actor_sprite_view.play_pose(pose_name)
	)


## Plays one strike; AnimationPlayer calls the contact method at impact.
func _play_next_strike() -> void:
	if _action != Action.MINING:
		return
	if not is_instance_valid(animation_player):
		_finish_mining()
		return
	_play_strike_pose()
	animation_player.play(&"strike")


## Reports the authored pickaxe contact without mutating terrain.
func _emit_strike_contact() -> void:
	if _action not in [
		Action.BREACHING,
		Action.MINING,
		Action.EXITING,
	]:
		return
	var contact_position := global_position
	if _action == Action.BREACHING:
		contact_position = _entry_breach_contact
	elif is_instance_valid(strike_anchor):
		contact_position = strike_anchor.global_position
	strike_contact.emit(contact_position)
	if _action == Action.BREACHING:
		entry_breach_requested.emit(self, contact_position)
		return
	if _action == Action.MINING:
		mining_strike_requested.emit(self, contact_position)
		return
	exit_strike_requested.emit(
		self,
		contact_position,
		_exit_step_target.x
	)


## Counts completed strikes and schedules the next bounded repetition.
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != &"strike":
		return
	_show_idle_appearance()
	if _action == Action.BREACHING:
		_finish_entry_breach()
		return
	if _action == Action.EXITING:
		if _exit_step_approved:
			_begin_exit_step_motion()
		return
	if _action != Action.MINING:
		return
	_remaining_strikes -= 1
	if _remaining_strikes <= 0:
		_finish_mining()
		return
	var current_generation := _action_generation
	get_tree().create_timer(
		_strike_pause,
		true,
		false,
		true
	).timeout.connect(
		_play_next_strike_if_current.bind(current_generation),
		CONNECT_ONE_SHOT
	)


## Rejects stale delayed strikes after interruption or actor reuse.
func _play_next_strike_if_current(expected_generation: int) -> void:
	if expected_generation != _action_generation:
		return
	_play_next_strike()


## Swaps to the authored contact pose without affecting the motion root.
func _show_strike_appearance() -> void:
	if (
		actor_sprite_view != null
		and actor_sprite_view.has_pose(&"strike")
	):
		return
	if (
		is_instance_valid(actor_sprite)
		and _strike_texture != null
		and _action in [
			Action.BREACHING,
			Action.MINING,
			Action.EXITING,
		]
	):
		actor_sprite.texture = _strike_texture


## Starts the visible strike pose without participating in contact timing.
func _play_strike_pose() -> void:
	if actor_sprite_view != null:
		actor_sprite_view.play_pose(&"strike")


## Restores the paired resting pose after contact, cancellation, or reuse.
func _show_idle_appearance() -> void:
	if (
		actor_sprite_view != null
		and actor_sprite_view.play_pose(&"idle")
	):
		return
	if is_instance_valid(actor_sprite) and _idle_texture != null:
		actor_sprite.texture = _idle_texture


## Uses authored walk art when available; otherwise preserves the idle texture.
func _show_walk_appearance() -> void:
	if actor_sprite_view != null:
		actor_sprite_view.play_pose(&"walk")


func _set_run_progress(
	progress: float,
	start_position: Vector2,
	target_position: Vector2,
	arc_height: float,
	peak_progress: float
) -> void:
	var arc_offset := _calculate_arc_offset(
		progress,
		arc_height,
		peak_progress
	)
	var next_position := start_position.lerp(target_position, progress)
	next_position.y -= arc_offset
	global_position = _clamp_to_motion_bounds(next_position)
	_set_ground_shadow_arc(arc_offset, arc_height)


## Traces one true parabola: horizontal speed is constant and the vertical term
## is a single quadratic in progress, so its second derivative — gravity — is
## constant. The mouse leaves the hole rising and lands genuinely accelerating.
func _set_emergence_progress(
	progress: float,
	start_position: Vector2,
	landing_position: Vector2
) -> void:
	var next_position := start_position.lerp(landing_position, progress)
	var resolved_wall_pop_rise := (
		0.0 if _reduce_motion_enabled else wall_pop_rise
	)
	var arc_offset := (
		resolved_wall_pop_rise
		* 4.0
		* progress
		* (1.0 - progress)
	)
	next_position.y -= arc_offset
	global_position = _clamp_to_motion_bounds(next_position)
	_set_ground_shadow_arc(arc_offset, resolved_wall_pop_rise)


func _finish_run_to_target() -> void:
	var should_emit_reached_wall := _emit_reached_wall_on_target
	var should_emit_jump_finished := _emit_jump_finished_on_target
	var should_land := _land_on_target
	_emit_reached_wall_on_target = false
	_emit_jump_finished_on_target = false
	_land_on_target = false
	_set_ground_shadow_arc(0.0, 0.0)
	_action_tween = null
	_action = Action.IDLE
	_show_idle_appearance()
	if is_instance_valid(animation_player):
		animation_player.play(&"land" if should_land else &"idle")
	if should_land and land_recovery_seconds > 0.0:
		# Hold the landing squash before the owner sends this mouse anywhere, so
		# a fall out of the wall reads as hitting the ground and then running.
		var current_generation := _action_generation
		get_tree().create_timer(
			land_recovery_seconds,
			true,
			false,
			true
		).timeout.connect(
			_finish_landing_if_current.bind(current_generation),
			CONNECT_ONE_SHOT
		)
		return
	run_target_reached.emit(self)
	if should_emit_reached_wall:
		reached_wall.emit(self)
	if should_emit_jump_finished:
		jump_finished.emit(self)


## Releases a landed mouse unless it was interrupted or reused mid-recovery.
func _finish_landing_if_current(expected_generation: int) -> void:
	if expected_generation != _action_generation or _action != Action.IDLE:
		return
	run_target_reached.emit(self)


func _resolve_jump_peak_progress(
	start_x: float,
	target_x: float,
	jump_peak_x: float
) -> float:
	if is_nan(jump_peak_x) or is_equal_approx(start_x, target_x):
		return 0.5
	return clampf(
		inverse_lerp(start_x, target_x, jump_peak_x),
		0.05,
		0.95
	)


func _calculate_arc_offset(
	progress: float,
	arc_height: float,
	peak_progress: float
) -> float:
	if arc_height <= 0.0:
		return 0.0
	if progress <= peak_progress:
		var rising_progress := progress / peak_progress
		return arc_height * sin(rising_progress * PI * 0.5)
	var falling_progress := (
		(progress - peak_progress) / (1.0 - peak_progress)
	)
	return arc_height * cos(falling_progress * PI * 0.5)


## Keeps the shadow on the interpolated floor while the actor root takes an arc.
func _set_ground_shadow_arc(
	arc_offset: float,
	maximum_arc_height: float
) -> void:
	if not is_instance_valid(ground_shadow):
		return
	ground_shadow.position.y = maxf(arc_offset, 0.0)
	var contact_strength := 1.0
	if maximum_arc_height > 0.0:
		contact_strength = lerpf(
			1.0,
			0.22,
			clampf(arc_offset / maximum_arc_height, 0.0, 1.0)
		)
	ground_shadow.set_contact_strength(contact_strength)


## Releases the actor only after its visible strike clip has fully recovered.
func _finish_entry_breach() -> void:
	_entry_breach_contact = Vector2.ZERO
	_action = Action.IDLE
	if is_instance_valid(animation_player):
		animation_player.play(&"idle")
	entry_breach_finished.emit(self)


## Ends authored wall mining without moving through the still-solid exit wall.
func _finish_mining() -> void:
	_action_tween = null
	_action = Action.IDLE
	if is_instance_valid(animation_player):
		animation_player.play(&"idle")
	ready_to_exit.emit(self)


## Moves one bounded segment only after its strike opened the production mask.
func _begin_exit_step_motion() -> void:
	if _action != Action.EXITING or not _exit_step_approved:
		return
	_exit_step_approved = false
	_action = Action.RUNNING
	_show_walk_appearance()
	if is_instance_valid(animation_player):
		animation_player.play(&"run")
	_action_tween = create_tween()
	_action_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_action_tween.tween_property(
		self,
		"global_position",
		_exit_step_target,
		_exit_duration
	).set_trans(Tween.TRANS_LINEAR)
	_action_tween.tween_callback(_finish_exit_step)


## Requests another wall step or finishes once the authored exit is reached.
func _finish_exit_step() -> void:
	_action_tween = null
	if _exit_step_is_final:
		_finish_exit()
		return
	_action = Action.IDLE
	_show_idle_appearance()
	if is_instance_valid(animation_player):
		animation_player.play(&"idle")
	exit_step_finished.emit(self)


## Hides the actor before notifying the owning sequence.
func _finish_exit() -> void:
	_action_tween = null
	_action = Action.IDLE
	hide()
	exited.emit(self)


## Clamps only room entrances and jumps; approved exit steps extend the room.
func _clamp_to_motion_bounds(screen_position: Vector2) -> Vector2:
	if not _motion_bounds.has_area():
		return screen_position
	return Vector2(
		clampf(
			screen_position.x,
			_motion_bounds.position.x,
			_motion_bounds.end.x
		),
		clampf(
			screen_position.y,
			_motion_bounds.position.y,
			_motion_bounds.end.y
		)
	)
