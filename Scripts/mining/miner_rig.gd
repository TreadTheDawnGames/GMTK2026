class_name MinerRig
extends Node2D

## Plays the miner's drawn frames and reports the authored contact moment.

const SpeechReactionType = preload(
	"res://Scripts/dialogue/speech_reaction.gd"
)
const GroundWalkType = preload(
	"res://Scripts/cinematics/ground_walk.gd"
)

signal impact_contact(screen_position: Vector2)
signal swing_finished

@export_category("Playback")
@export_range(0.1, 4.0, 0.05) var animation_speed_multiplier: float = 1.0
@export_range(0.0, 1.0, 0.05) var combo_speed_bonus: float = 0.35

@export_category("Placement")
## Seats the miner on the pale top stratum at the surface and character floors.
##
## Measured rather than guessed: on an authored encounter floor his sole landed
## ten pixels under the floor line the cast are placed on, so he read as standing
## in the ground while whoever he was talking to stood on it. Six puts the sole
## on that line. This is one value for the surface and for cutscene floors, so
## check the bus-stop opening if it is changed again.
@export_range(0.0, 64.0, 1.0) var intact_floor_grounding_offset_y: float = 6.0
## The same seating, for the run's own starting surface.
##
## It is separate because the two floors are not the same thing. A cutscene
## floor is a cut room he shares with a standing cast, so his sole goes on their
## line. The surface is the top of the terrain, where the shelf falls away
## toward the camera and the value that seats him on a room floor leaves him
## standing high on the lip. Six put him right in a room and too high at the bus
## stop; this is the one the opening is measured against.
@export_range(0.0, 64.0, 1.0) var surface_grounding_offset_y: float = 16.0
## Slightly overlaps the sampled dirt edge so texture filtering cannot show a gap.
@export_range(0.0, 4.0, 0.25) var grounding_overlap_y: float = 1.0
## Lifts the sole baseline slightly on each cinematic walking step.
@export_range(0.0, 12.0, 0.5) var cinematic_walk_step_height: float = 4.0
## Controls how many visible walking steps fit along a traversal segment.
@export_range(8.0, 96.0, 1.0) var cinematic_walk_stride_pixels: float = 24.0
## Whether digging steps him along on the same stride and lift as the cinematic
## walk. Clearing it puts him back to sliding flat with the view.
@export var gameplay_walk_step_enabled: bool = true
## How fast a step he has already started finishes once he stops travelling.
@export_range(4.0, 512.0, 1.0) var walk_settle_pixels_per_second: float = 90.0

@export_category("Draw Order")
## Standing on the run's untouched surface, in front of terrain layer one
## (z_index 2). He is on top of the ground there, not in it, so the foreground
## stratum must not cut his legs off during the arrival shot.
@export_range(0, 16, 1) var surface_draw_order: int = 3
## Where he stands while mining: behind the foreground stratum and in front of
## the one behind it, which is what puts him down in the dig rather than pasted
## on top of it.
##
## This was briefly raised to 3 so he drew in front of everything. The camera
## does not follow him down — the terrain scrolls past it — so he sits at the top
## of his own shaft in every frame, and the foreground stratum cut him off at the
## shins for the whole descent rather than only while he was genuinely inside the
## ground. That is the cost of this value, and it is accepted on purpose: being
## occluded by the ground he is standing in is the read, and a cutscene lifts him
## clear of it anyway through cutscene_draw_order.
##
## Kept strictly between the two frontmost strata z indices, currently 2 and 0.
## verify_cutscene_cast_draw_order.gd asserts that relationship, because this
## number and the terrain profile live in different files.
@export_range(0, 16, 1) var buried_draw_order: int = 1
## Standing in an authored cutscene room, in front of terrain layer one
## (z_index 2) again. A cutscene frames the whole cast standing on the room's
## floor and holds on it, so the foreground stratum cutting him off at the shins
## reads as a bug there even though it is exactly right while mining the same
## depth. Ordinary mining is untouched: only an active encounter asks for this.
@export_range(0, 16, 1) var cutscene_draw_order: int = 3

@export_category("References")
@export var animation_player: AnimationPlayer
@export var visual_root: Node2D
@export var drawn_miner_sprite: Sprite2D
@export var landing_foot_anchor: Marker2D
@export var idle_miner_texture: Texture2D
@export var wind_up_miner_texture: Texture2D
@export var impact_miner_texture: Texture2D
## Drawn while a cutscene drops him into its room. Null keeps the idle frame,
## which is how this behaved before the pose existed.
##
## The fall is the one moment the run shows him off his feet, and holding the
## idle stance through it reads as the whole man being slid downward rather than
## falling. The swap back is deliberately hung off the cinematic restore rather
## than off the tween finishing: a fall that is cancelled halfway must not leave
## him falling forever on solid ground.
@export var falling_miner_texture: Texture2D
## Drawn where he lands, sprawled on the room's floor, before he gets up. Null
## skips the sprawl and returns him straight to idle.
@export var landed_miner_texture: Texture2D
## How long he stays down before getting up.
@export_range(0.0, 2.0, 0.05) var landing_sprawl_seconds: float = 0.45
@export var impact_point: Marker2D
@export var stand_in_hammer_head: Line2D
@export var final_hammer_head_sprite: Sprite2D
@export var impact_audio_player: AudioStreamPlayer2D
@export var speech_reaction: SpeechReactionType

var _playing_full_swing: bool = false
var _rest_position: Vector2
var _visual_root_rest_y: float
var _cinematic_override_active: bool = false
## True while a shot is deliberately keeping him face down, so neither the
## landing sprawl's own timer nor anything else stands him back up early.
var _is_landing_held: bool = false
## The drawn sprite's authored placement, captured before anything swaps a pose.
var _base_drawn_sprite_position: Vector2
var _base_drawn_sprite_scale: Vector2
## Opaque-body measurements per pose texture. get_used_rect scans every pixel of
## a half-megapixel canvas, and poses swap on every swing, so each is measured
## once for the life of the run.
var _pose_metrics_cache: Dictionary = {}
var _cinematic_rest_position: Vector2
var _cinematic_rest_visual_scale: Vector2
var _cinematic_rest_z_as_relative: bool
## True until he lands below the surface he started on. Nothing puts it back:
## once the ground is open he is inside it for the rest of the run.
var _is_on_surface: bool = true
var _is_in_cutscene: bool = false
var _cinematic_tween: Tween
## The view's last published offset, and the walking step being spent against it.
var _screen_offset: Vector2 = Vector2.ZERO
var _walked_screen_x: float = 0.0
var _walk_stride_progress: float = 0.0
var _walk_step_lift: float = 0.0
var _audio_handler: PlayerAudioHandler


## Supplies the cross-scene audio service at the composition boundary.
func set_audio_handler(audio_handler: PlayerAudioHandler) -> void:
	_audio_handler = audio_handler


## Connects animation events and starts the idle animation.
func _ready() -> void:
	_rest_position = position
	_visual_root_rest_y = visual_root.position.y
	# The authored placement of the drawn sprite, which every mining pose is
	# measured against and which the cutscene poses are aligned back to.
	_base_drawn_sprite_position = drawn_miner_sprite.position
	_base_drawn_sprite_scale = drawn_miner_sprite.scale
	# The rig owns its own draw order from here on, so the two authored values
	# above are the only place it is decided.
	z_index = get_rest_draw_order()
	_set_miner_texture(idle_miner_texture)
	show_intact_floor_grounding()
	_ensure_ground_shadow()
	if not animation_player.animation_finished.is_connected(
		_on_animation_finished
	):
		animation_player.animation_finished.connect(
			_on_animation_finished
		)
	_play_idle()


## Puts a contact shadow under the miner, the same one the cast and the cutscene
## editor's stand-ins carry.
##
## He is the one character on screen for the whole run, so a floor he does not
## touch is the most visible version of the problem. The rig's own origin is his
## standing point, so the shadow needs no offset of its own.
func _ensure_ground_shadow() -> void:
	if get_node_or_null(NodePath("GroundShadow")) != null:
		return
	var shadow := ActorGroundShadow.new()
	shadow.name = &"GroundShadow"
	shadow.measured_sprite = drawn_miner_sprite
	add_child(shadow)


## Plays the successful strike at its combo and equipped-pickaxe speed.
func play_success(
	_combo: int,
	combo_strength: float,
	swing_speed_multiplier: float,
	path_direction: int
) -> void:
	set_facing_direction(path_direction)
	_set_miner_texture(idle_miner_texture)
	var combo_multiplier := lerpf(
		1.0,
		1.0 + combo_speed_bonus,
		combo_strength
	)
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(
		&"three_frame_success",
		-1.0,
		combo_multiplier * maxf(swing_speed_multiplier, 0.1)
	)


## Swaps to the readable anticipation pose before hammer contact.
func _show_success_wind_up() -> void:
	_set_miner_texture(wind_up_miner_texture)


## Reports the hammer-tip position when the animation reaches the ground.
func _emit_success_impact() -> void:
	_set_miner_texture(impact_miner_texture)
	if _audio_handler != null:
		_audio_handler.play_sound(AudioLibrary.IMPACT)
	impact_contact.emit(impact_point.global_position)


## Plays the missed-swing animation.
func play_miss(_combo: int) -> void:
	_set_miner_texture(idle_miner_texture)
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"mine_miss")


## Holds the miner in the raised pickaxe pose.
func play_wind_up() -> void:
	_set_miner_texture(wind_up_miner_texture)
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_up")


## Holds the miner in the downward impact pose.
func play_wind_down() -> void:
	_set_miner_texture(impact_miner_texture)
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_down")


## Previews the raised and impact poses in sequence.
func play_full_swing() -> void:
	# Authoring preview for the anticipation and contact poses.
	_set_miner_texture(wind_up_miner_texture)
	_playing_full_swing = true
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_up")
	animation_player.queue(&"wind_down")


## Sets the playback speed within the supported range.
func set_animation_speed_multiplier(value: float) -> void:
	animation_speed_multiplier = clampf(value, 0.1, 4.0)
	if is_instance_valid(animation_player):
		animation_player.speed_scale = animation_speed_multiplier


## Applies the equipped pickaxe color to every available miner art slot.
func set_hammer_head_color(color: Color) -> void:
	if is_instance_valid(stand_in_hammer_head):
		stand_in_hammer_head.default_color = color
	if is_instance_valid(final_hammer_head_sprite):
		final_hammer_head_sprite.self_modulate = color
	if (
		is_instance_valid(drawn_miner_sprite)
		and drawn_miner_sprite.material is ShaderMaterial
	):
		var drawn_material := (
			drawn_miner_sprite.material as ShaderMaterial
		)
		drawn_material.set_shader_parameter(&"tool_tint", color)


## Faces the visible miner toward the selected mining side.
func set_facing_direction(direction: int) -> void:
	if not is_instance_valid(visual_root) or direction == 0:
		return
	visual_root.scale.x = absf(visual_root.scale.x) * signi(direction)


## Reports which side currently holds the raised pickaxe.
func get_facing_direction() -> int:
	if (
		not is_instance_valid(visual_root)
		or is_zero_approx(visual_root.scale.x)
	):
		return 1
	return signi(roundi(visual_root.scale.x))


## Places the miner at its true screen offset during falls and view movement.
## It is applied on the spot, because a chunk flip publishes the offset it needs
## honoured that same frame; _process only keeps carrying the walking step on
## the frames where the view publishes nothing.
func set_screen_offset(screen_offset: Vector2) -> void:
	_screen_offset = screen_offset
	_apply_screen_position()


## Carries the walking step and writes the position it lands on.
func _process(delta: float) -> void:
	_advance_walk_step(delta)
	_apply_screen_position()


func _apply_screen_position() -> void:
	position = _rest_position + _screen_offset + Vector2.UP * _walk_step_lift


## Turns the sideways travel control gives him into the same footstep arc the
## cinematic walk plays.
##
## Digging moves him by publishing a screen offset every frame, so under the
## player he slid across the floor with his feet flat while the same rig walks
## properly in a cutscene. This spends his own travel against the authored
## stride and lifts him on the same half-sine, which makes one dig step read as
## one footstep: the horizontal step is three cells against a stride of 24 px,
## so he is back down flat exactly when the swing lands. Standing still finishes
## the step he was in rather than dropping the raised foot on the spot.
func _advance_walk_step(delta: float) -> void:
	var stride := maxf(cinematic_walk_stride_pixels, 1.0)
	var travel := absf(_screen_offset.x - _walked_screen_x)
	_walked_screen_x = _screen_offset.x
	if not gameplay_walk_step_enabled or _cinematic_override_active:
		_walk_stride_progress = 0.0
		_walk_step_lift = 0.0
		return
	if is_zero_approx(travel):
		# Nothing new to spend, so carry the raised foot to the end of its own
		# step instead of freezing it mid-air where the offset stopped coming.
		if is_zero_approx(_walk_stride_progress):
			_walk_step_lift = 0.0
			return
		travel = walk_settle_pixels_per_second * delta
	_walk_stride_progress = _walk_stride_progress + travel / stride
	if _walk_stride_progress >= 1.0:
		_walk_stride_progress = fmod(_walk_stride_progress, 1.0)
		# Land the step exactly flat rather than starting the next one on the
		# tail of this one's rounding.
		if is_zero_approx(travel - walk_settle_pixels_per_second * delta):
			_walk_stride_progress = 0.0
	_walk_step_lift = (
		sin(_walk_stride_progress * PI)
		* maxf(cinematic_walk_step_height, 0.0)
	)


## Returns how far the walking step currently holds him off his own baseline,
## so the callers that seat him on sampled dirt measure the foot he is walking
## on instead of the one he has in the air.
func _get_walk_step_lift() -> float:
	return _walk_step_lift


## Restores the visual-only speech motion before another presenter takes over.
func reset_speech_motion() -> void:
	if is_instance_valid(speech_reaction):
		speech_reaction.reset_speech_motion()


## Bounces the miner artwork without changing the gameplay rig position.
func react_to_presented_line() -> void:
	if is_instance_valid(speech_reaction):
		speech_reaction.react_to_presented_line()


## Reports the draw order the miner rests at right now, so a cutscene that
## borrows his presentation can hand back the order he actually belongs at
## instead of one captured before he moved.
func get_rest_draw_order() -> int:
	if _is_in_cutscene:
		return cutscene_draw_order
	return surface_draw_order if _is_on_surface else buried_draw_order


## Drops him into a cutscene room: falling on the way down, sprawled where he
## lands, then up on his feet.
##
## The pose is driven from the encounter's own lifecycle rather than from a
## movement tween, because he does not actually travel. The camera holds him at
## the mining face and scrolls the terrain past, so "falling" is a thing the
## world does around a stationary sprite, and there is no motion to hang a pose
## on. Cutscene entry is the only place in the run that knows a fall happened.
func show_cutscene_fall() -> void:
	if falling_miner_texture == null:
		return
	animation_player.stop()
	_set_miner_texture(falling_miner_texture)


## Puts him face down and leaves him there until somebody picks him up.
##
## show_cutscene_landing() below gets him up again after its own authored sprawl,
## which is right for arriving in a room: he hits the floor, gets up, the scene
## carries on. This is the other case - he is on the ground because something is
## happening around him, and how long that lasts is decided by the thing
## happening rather than by a duration authored here. A rat stampede runs for as
## long as the player takes to read the line that started it.
func hold_cutscene_landing() -> void:
	if landed_miner_texture == null:
		return
	_is_landing_held = true
	animation_player.stop()
	_set_miner_texture(landed_miner_texture)


## Picks him up from a held landing. Safe to call when nothing is being held, so
## a cancelled encounter can call it without knowing whether it ever floored him.
func release_cutscene_landing() -> void:
	if not _is_landing_held:
		return
	_is_landing_held = false
	if not _cinematic_override_active:
		_play_idle()


## Lands him on his face and picks him up again. Safe to call when no fall pose
## was ever shown; it simply returns him to idle.
func show_cutscene_landing() -> void:
	if landed_miner_texture == null:
		_play_idle()
		return
	animation_player.stop()
	_set_miner_texture(landed_miner_texture)
	if landing_sprawl_seconds <= 0.0:
		_play_idle()
		return
	# process_always, because the cutscene frame pauses the tree while it opens
	# and a plain timer would leave him face down for the whole conversation.
	var sprawl_timer := get_tree().create_timer(
		landing_sprawl_seconds,
		true,
		false,
		true
	)
	await sprawl_timer.timeout
	# Only if nothing else has claimed his presentation in the meantime: a
	# cancelled encounter restores its own pose and must not be overwritten, and
	# a shot that has since floored him deliberately must not be stood up by a
	# timer that started before it.
	if not _cinematic_override_active and not _is_landing_held:
		_play_idle()


## Frames him for an authored cutscene, in front of the foreground stratum.
## Every path that restores draw order already routes through
## get_rest_draw_order, so a shot that borrows his presentation mid-cutscene
## still hands him back at the cutscene order rather than the mining one.
func enter_cutscene_draw_order() -> void:
	if _is_in_cutscene:
		return
	_is_in_cutscene = true
	if not _cinematic_override_active:
		z_index = get_rest_draw_order()


## Returns him to the order his current depth calls for once the shot is over.
func exit_cutscene_draw_order() -> void:
	if not _is_in_cutscene:
		return
	_is_in_cutscene = false
	if not _cinematic_override_active:
		z_index = get_rest_draw_order()


## Reports whether he is still standing on the surface the run started from.
## The surface staging reads it to know when the road above him is clear.
func is_on_surface() -> bool:
	return _is_on_surface


## Moves him off the starting surface and into the ground. The caller owns the
## depth test; the rig owns what that means for its draw order.
func leave_surface_draw_order() -> void:
	if not _is_on_surface:
		return
	_is_on_surface = false
	# A cutscene that owns the presentation restores the new order when it ends.
	if not _cinematic_override_active:
		z_index = get_rest_draw_order()


## Places the artwork above the first layer on an authored intact floor, or on
## the run's starting surface, whichever he is standing on.
func show_intact_floor_grounding() -> void:
	_set_grounding_offset(
		surface_grounding_offset_y
		if _is_on_surface
		else intact_floor_grounding_offset_y
	)


## Seats the authored sole baseline on the renderer's sampled dirt support.
func seat_landing_foot_at_screen_y(support_screen_y: float) -> void:
	if is_nan(support_screen_y) or not is_instance_valid(landing_foot_anchor):
		return
	# Measure against his settled sole. Mid-step the rig root is riding the walk
	# lift, and seating that would push the artwork down by however high his
	# foot happened to be and keep it there.
	var grounding_delta: float = (
		support_screen_y
		+ grounding_overlap_y
		- (landing_foot_anchor.global_position.y + _get_walk_step_lift())
	)
	var current_grounding_offset: float = (
		visual_root.position.y - _visual_root_rest_y
	)
	_set_grounding_offset(current_grounding_offset + grounding_delta)


## Returns the horizontal sole position used to sample organic terrain.
func get_landing_foot_screen_x() -> float:
	if not is_instance_valid(landing_foot_anchor):
		return global_position.x
	return landing_foot_anchor.global_position.x


## Returns the authored sole position, so landing feedback spawns at his feet
## rather than at the rig origin somewhere up his body. It reports the floor he
## is walking on, not the height of a foot caught mid-step.
func get_landing_foot_screen_position() -> Vector2:
	if not is_instance_valid(landing_foot_anchor):
		return global_position
	return landing_foot_anchor.global_position + Vector2(
		0.0,
		_get_walk_step_lift()
	)


## Reserves the visual root for a cutscene without moving gameplay position.
func begin_cinematic_visual_override() -> bool:
	if _cinematic_override_active or not is_instance_valid(visual_root):
		return false
	reset_speech_motion()
	_cinematic_override_active = true
	_cinematic_rest_position = visual_root.position
	_cinematic_rest_visual_scale = visual_root.scale
	_cinematic_rest_z_as_relative = z_as_relative
	if _cinematic_tween != null and _cinematic_tween.is_valid():
		_cinematic_tween.kill()
	_cinematic_tween = null
	_play_idle()
	return true


## Places the reserved presentation after gameplay has already landed.
func place_cinematic_foot_at(
	screen_position: Vector2,
	draw_order: int
) -> bool:
	if (
		not _cinematic_override_active
		or not is_instance_valid(visual_root)
		or not is_instance_valid(landing_foot_anchor)
		or is_nan(screen_position.x)
		or is_nan(screen_position.y)
	):
		return false
	if _cinematic_tween != null and _cinematic_tween.is_valid():
		_cinematic_tween.kill()
	_cinematic_tween = null
	z_as_relative = false
	z_index = draw_order
	visual_root.position += (
		screen_position - landing_foot_anchor.global_position
	)
	return true


## Reports the authored sole point used to place the miner between strata.
func get_cinematic_foot_screen_position() -> Vector2:
	if not is_instance_valid(landing_foot_anchor):
		return global_position
	return landing_foot_anchor.global_position


## Walks the presentation sole to an exact terrain point with a light step arc.
func glide_cinematic_foot_to(
	screen_position: Vector2,
	duration: float,
	draw_order: int,
	floor_sampler: Callable = Callable()
) -> Tween:
	if not _cinematic_override_active or not is_instance_valid(visual_root):
		return null
	reset_speech_motion()
	if _cinematic_tween != null and _cinematic_tween.is_valid():
		_cinematic_tween.kill()
	var foot_path := GroundWalkType.build_path(
		get_cinematic_foot_screen_position(),
		screen_position,
		floor_sampler,
		cinematic_walk_stride_pixels
	)
	# This second packed array is sampled-path sized and exists only for this
	# visual override; it translates sole coordinates to the movable root.
	var root_path := foot_path.duplicate()
	var root_to_foot_offset := (
		visual_root.global_position
		- get_cinematic_foot_screen_position()
	)
	for point_index in range(root_path.size()):
		root_path[point_index] += root_to_foot_offset
	z_as_relative = false
	z_index = draw_order
	_cinematic_tween = GroundWalkType.walk_along(
		visual_root,
		root_path,
		duration,
		cinematic_walk_step_height
	)
	return _cinematic_tween


## Falls presentation state with acceleration while gameplay position stays put.
func fall_cinematic_foot_to(
	screen_position: Vector2,
	duration: float,
	draw_order: int
) -> Tween:
	if not _cinematic_override_active or not is_instance_valid(visual_root):
		return null
	reset_speech_motion()
	if _cinematic_tween != null and _cinematic_tween.is_valid():
		_cinematic_tween.kill()
	var foot_delta: Vector2 = (
		screen_position - get_cinematic_foot_screen_position()
	)
	z_as_relative = false
	z_index = draw_order
	_cinematic_tween = create_tween()
	_cinematic_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_cinematic_tween.tween_property(
		visual_root,
		"position",
		visual_root.position + foot_delta,
		maxf(duration, 0.01)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return _cinematic_tween


## Restores the exact presentation transform captured before the cutscene.
func restore_cinematic_visual(duration: float = 0.0) -> Tween:
	if not _cinematic_override_active or not is_instance_valid(visual_root):
		return null
	reset_speech_motion()
	if _cinematic_tween != null and _cinematic_tween.is_valid():
		_cinematic_tween.kill()
	_cinematic_tween = create_tween()
	_cinematic_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_cinematic_tween.tween_property(
		visual_root,
		"position",
		_cinematic_rest_position,
		maxf(duration, 0.01)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cinematic_tween.tween_callback(_finish_cinematic_visual_restore)
	return _cinematic_tween


## Immediately releases an override for interruption and teardown paths.
func cancel_cinematic_visual_override() -> void:
	if not _cinematic_override_active:
		return
	reset_speech_motion()
	if _cinematic_tween != null and _cinematic_tween.is_valid():
		_cinematic_tween.kill()
	visual_root.position = _cinematic_rest_position
	_finish_cinematic_visual_restore()


## Reports whether a coordinator currently owns the visual presentation.
func is_cinematic_visual_override_active() -> bool:
	return _cinematic_override_active


## Changes visual grounding without moving the rig's gameplay position.
func _set_grounding_offset(offset_y: float) -> void:
	visual_root.position.y = _visual_root_rest_y + offset_y


## Releases presentation ownership after a completed or cancelled restore.
func _finish_cinematic_visual_restore() -> void:
	visual_root.scale = _cinematic_rest_visual_scale
	# Deliberately the live rest order, not one captured when the cutscene
	# started: a shot can end at a depth the miner was not standing at when it
	# began, and he must come back at the order that depth calls for.
	z_index = get_rest_draw_order()
	z_as_relative = _cinematic_rest_z_as_relative
	_cinematic_override_active = false
	_cinematic_tween = null
	_play_idle()


## Swaps authored full-frame poses without changing gameplay coordinates.
func _set_miner_texture(texture: Texture2D) -> void:
	if texture == null or not is_instance_valid(drawn_miner_sprite):
		return
	drawn_miner_sprite.texture = texture
	_align_cutscene_pose(texture)


## Puts a cutscene pose at the size and on the ground line the mining poses use.
##
## Every pose shares one sprite, one position and one scale, which is only right
## while they all share a canvas and put the body in the same place inside it.
## They do not. The landed pose is drawn 343 opaque pixels wide against the idle
## pose's 243 - forty per cent larger - and its lowest opaque row sits about 39
## units higher, so swapped as-is he lies oversized and floating clear of the
## floor he is supposed to be lying on.
##
## Only the two cutscene poses are touched. The mining poses are left exactly as
## authored, because their placement is what the swing animations key against and
## nothing about ordinary digging is being fixed here.
##
## Derived from the images rather than authored as two magic numbers, because an
## authored offset is right until somebody redraws the art and then silently
## wrong. CharacterPresenter measures its own bodies the same way for the same
## reason.
func _align_cutscene_pose(texture: Texture2D) -> void:
	var is_cutscene_pose := (
		texture == falling_miner_texture
		or texture == landed_miner_texture
	)
	if not is_cutscene_pose or idle_miner_texture == null:
		drawn_miner_sprite.position = _base_drawn_sprite_position
		drawn_miner_sprite.scale = _base_drawn_sprite_scale
		return
	var reference := _get_pose_metrics(idle_miner_texture)
	var pose := _get_pose_metrics(texture)
	if reference.is_empty() or pose.is_empty() or float(pose["width"]) <= 0.0:
		return

	# Match the drawing scale of the standing art, so the man lying down is the
	# same man. Width is the measure because the two mining poses already agree
	# on it exactly; height cannot be, since a sprawled figure is legitimately
	# shorter than a standing one.
	var scale_multiplier: float = (
		float(reference["width"]) / float(pose["width"])
	)
	drawn_miner_sprite.scale = _base_drawn_sprite_scale * scale_multiplier
	# Then drop it so this pose's lowest drawn row sits exactly where the idle
	# pose's does. That row is his soles standing up and his side lying down, and
	# it is the line the floor is under either way.
	drawn_miner_sprite.position = Vector2(
		_base_drawn_sprite_position.x,
		_get_body_bottom_y(
			reference,
			_base_drawn_sprite_scale.y,
			_base_drawn_sprite_position.y
		)
		- _get_body_bottom_y(
			pose,
			_base_drawn_sprite_scale.y * scale_multiplier,
			0.0
		)
	)


## Returns where a pose's lowest opaque row is drawn, for a sprite scale and a
## node y. A centred Sprite2D draws its canvas centre on the node position, so
## the canvas top is half the scaled canvas above it.
func _get_body_bottom_y(
	metrics: Dictionary,
	scale_y: float,
	node_y: float
) -> float:
	return (
		node_y
		- float(metrics["canvas_height"]) * scale_y * 0.5
		+ float(metrics["bottom"]) * scale_y
	)


## Measures one pose's opaque body inside its canvas, once per texture.
func _get_pose_metrics(texture: Texture2D) -> Dictionary:
	var cache_key := texture.resource_path
	if _pose_metrics_cache.has(cache_key):
		return _pose_metrics_cache[cache_key]
	var image := texture.get_image()
	if image == null:
		return {}
	var opaque := image.get_used_rect()
	var metrics := {
		"width": float(opaque.size.x),
		"bottom": float(opaque.end.y),
		"canvas_height": float(image.get_height()),
	}
	_pose_metrics_cache[cache_key] = metrics
	return metrics


## Returns finished actions to idle after any queued strike plays.
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"wind_up" and _playing_full_swing:
		_set_miner_texture(impact_miner_texture)
		return
	if animation_name == &"three_frame_success":
		_playing_full_swing = false
		_play_idle()
		swing_finished.emit()
		return
	if animation_name != &"idle" and animation_name != &"wind_up":
		_playing_full_swing = false
		_play_idle()


## Plays idle at the current speed setting.
func _play_idle() -> void:
	_set_miner_texture(idle_miner_texture)
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"idle")
