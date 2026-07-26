class_name CharacterPresenter
extends Node2D

## Displays CharacterAppearance unchanged unless an optional pose can play.
## Speech motion remains independent from the visible texture and sheet frame.

const SpeechReactionType = preload(
	"res://Scripts/dialogue/speech_reaction.gd"
)
const GroundWalkType = preload(
	"res://Scripts/cinematics/ground_walk.gd"
)

@export_category("References")
@export var character_sprite: Sprite2D
@export var actor_sprite_view: ActorSpriteView
@export var speech_reaction: SpeechReactionType

var _base_sprite_position: Vector2
var _departure_tween: Tween
var _art_faces_left: bool = false
var _reduce_motion_enabled: bool = false
## Which way the appearance was authored, so "mirrored" means mirrored from the
## state the offset was tuned against rather than from flip_h being true.
var _base_flip_h: bool = false
## How far the drawn body sits from the sprite node, along x, in world pixels,
## measured in the authored orientation. Turning the character round moves the
## body to the other side of the node by this much, so twice it is the correction
## that puts it back. Zero for art drawn centred in its canvas.
var _body_offset_from_node_x: float = 0.0
## The pose this character returns to between spoken lines.
##
## Every presented dialogue line resets every presenter's speech motion, and that
## reset used to hard-code "idle" as the pose to come back to. That is right for a
## pose a line puts on for the length of that line - Quibble raising his cup to
## speak - and wrong for one the shot is built on: the Treasure Hunter arrives at
## the cafe holding nothing, because he gave both pickaxes away, and his authored
## no_pickaxe pose was being wiped by the first line anybody spoke. He then said "I
## was tired of carrying things" while holding a pickaxe.
##
## Defaults to idle, so a presenter nobody has asked to hold anything behaves
## exactly as before.
var _resting_pose: StringName = &"idle"

## Opaque-body measurements, keyed by texture path. get_used_rect() scans every
## pixel of a 2224x1668 sheet, and apply_appearance runs for all thirteen encounters
## at startup and again on every visit; there are only eight distinct textures, so
## measuring each once is the difference between a boot cost and a boot stall.
static var _body_centre_cache: Dictionary = {}


## Stores the authored sprite position before an appearance is assigned.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_base_sprite_position = character_sprite.position
	speech_reaction.capture_rest_position()
	_ensure_ground_shadow()


## Removes actor bobbing while preserving poses, travel, and arrival callbacks.
func set_reduce_motion_enabled(enabled: bool) -> void:
	_reduce_motion_enabled = enabled
	speech_reaction.set_reduce_motion_enabled(enabled)


## Puts a contact shadow under this character.
##
## Built here rather than authored into the scene because it is the runtime twin
## of the one the cutscene editor draws under its stand-ins: without it the
## editor shows a cast standing on the floor and the game shows the same cast
## floating in front of it. This node's origin is the character's feet, so the
## shadow needs no offset.
func _ensure_ground_shadow() -> void:
	if get_node_or_null(NodePath("GroundShadow")) != null:
		return
	var shadow := ActorGroundShadow.new()
	shadow.name = &"GroundShadow"
	shadow.measured_sprite = character_sprite
	add_child(shadow)


## Applies the authored sprite configuration for one named character.
func apply_appearance(appearance: CharacterAppearance) -> void:
	speech_reaction.reset_speech_motion()
	if appearance == null:
		hide()
		return
	character_sprite.texture = appearance.texture
	character_sprite.hframes = appearance.horizontal_frames
	character_sprite.vframes = appearance.vertical_frames
	character_sprite.frame = appearance.frame
	character_sprite.scale = appearance.sprite_scale
	# The actor origin is its feet. Measuring the lowest opaque row keeps art
	# padding from making runtime placement disagree with the editor preview.
	character_sprite.position = Vector2(
		appearance.sprite_offset.x,
		ActorSoleMeasure.get_sprite_y(appearance)
	)
	character_sprite.modulate = appearance.tint
	character_sprite.flip_h = appearance.flip_h
	_art_faces_left = appearance.art_faces_left
	_base_flip_h = appearance.flip_h
	_base_sprite_position = character_sprite.position
	_body_offset_from_node_x = _measure_body_offset(appearance)
	speech_reaction.capture_rest_position()
	# A new appearance is a new character as far as this node is concerned, so
	# anything the last encounter asked it to hold goes with the old art. Without
	# this a presenter reused across visits would carry a held pose forward into a
	# shot that never asked for one.
	_resting_pose = &"idle"
	if actor_sprite_view != null:
		actor_sprite_view.pose_set = appearance.pose_set
		actor_sprite_view.play_pose(_resting_pose)


## Resets bounce timing before a new character conversation begins.
func reset_speech_motion() -> void:
	speech_reaction.reset_speech_motion()
	character_sprite.position = _base_sprite_position
	# Reassigning the authored baseline would put a turned character back on the
	# unturned correction, so the turn has to be re-applied on top of it.
	_apply_facing_offset(character_sprite.flip_h)
	if actor_sprite_view != null:
		actor_sprite_view.play_pose(_resting_pose)


## Bounces until another speaker or the conversation takes over.
func react_to_presented_line() -> void:
	speech_reaction.react_to_presented_line()


## Plays a timeline-authored visual reaction without moving the actor root.
##
## This boundary keeps CutsceneSequencePlayer out of the presenter's private
## sprite hierarchy while still letting the editor author exact motion.
func play_cutscene_bounce(
	offset: Vector2,
	duration: float,
	bounce_count: int,
	transition: Tween.TransitionType
) -> void:
	speech_reaction.play_bounce(
		offset,
		duration,
		bounce_count,
		transition
	)


## Reports whether this presenter can display an optional dialogue pose.
func has_pose(pose_name: StringName) -> bool:
	return (
		actor_sprite_view != null
		and actor_sprite_view.has_pose(pose_name)
	)


## Displays an optional dialogue pose without changing speech motion.
##
## `hold` decides whether the pose survives the next spoken line. Off, which is
## every existing caller, it is worn until the next line resets speech motion and
## the character drops back to idle - which is what a per-line Speaker Pose wants.
## On, it becomes the pose this character rests in for the remainder of the shot,
## for a pose the staging depends on rather than one a sentence puts on.
func play_pose(pose_name: StringName, hold: bool = false) -> bool:
	if actor_sprite_view == null:
		return false
	if not actor_sprite_view.play_pose(pose_name):
		return false
	if hold:
		_resting_pose = pose_name
	return true


## Faces the visible character along its current travel direction, mirroring
## only when the art does not already look that way.
func set_facing_direction(direction: int) -> void:
	if not is_instance_valid(character_sprite) or direction == 0:
		return
	var flipped := (direction < 0) != _art_faces_left
	character_sprite.flip_h = flipped
	_apply_facing_offset(flipped)


## Keeps the drawn body on its mark when the character turns round.
##
## Sprite2D is centred, so flip_h mirrors the texture about the SPRITE NODE, not
## about the character. Art drawn off-centre in its canvas therefore swings to the
## far side of the node the moment it is turned - by twice however far off-centre
## it was drawn. Measured on the shipped art that is 39px for the Lantern Keeper,
## 31px for the Treasure Hunter and 29px for Rotini, and it happens in whichever
## direction the art happens to lean, which is usually straight into whoever they
## are talking to.
##
## sprite_offset does not save you: it is authored against one orientation, so
## once the body mirrors the offset stops cancelling the lean and starts adding
## to it. There is no single value that is right both ways.
##
## The correction deliberately restores the body to where the AUTHORED
## orientation put it, rather than centring it on the node. Every shot in the game
## was staged against the authored orientation; centring would silently re-space
## all of them. This changes only the turned state, which was the broken one.
func _apply_facing_offset(flipped: bool) -> void:
	if not is_instance_valid(character_sprite):
		return
	var mirrored := flipped != _base_flip_h
	character_sprite.position.x = _base_sprite_position.x + (
		2.0 * _body_offset_from_node_x if mirrored else 0.0
	)


## Returns how far the drawn body sits from the sprite node along x, in world
## pixels, in the orientation the appearance was authored in.
func _measure_body_offset(appearance: CharacterAppearance) -> float:
	if appearance.texture == null:
		return 0.0
	var columns := maxi(appearance.horizontal_frames, 1)
	var rows := maxi(appearance.vertical_frames, 1)
	# Keyed on the frame, not just the texture: a sheet's frames do not all
	# carry their body in the same place, and reusing one frame's answer for
	# another would move the character by the difference.
	var cache_key := "%s#%d/%dx%d" % [
		appearance.texture.resource_path,
		appearance.frame,
		columns,
		rows,
	]
	if _body_centre_cache.has(cache_key):
		return _apply_authored_orientation(
			appearance,
			_body_centre_cache[cache_key]
		)

	var image := appearance.texture.get_image()
	if image == null:
		return 0.0
	var frame_width := image.get_width() / columns
	var frame_height := image.get_height() / rows
	if frame_width <= 0 or frame_height <= 0:
		return 0.0
	var frame_index := clampi(appearance.frame, 0, columns * rows - 1)
	var frame_region := Rect2i(
		(frame_index % columns) * frame_width,
		(frame_index / columns) * frame_height,
		frame_width,
		frame_height
	)
	# Scan only this frame. get_used_rect() over the whole sheet would report the
	# union of every pose, which is not where any single one of them is drawn.
	var frame_image := (
		image if columns * rows == 1 else image.get_region(frame_region)
	)
	var opaque := frame_image.get_used_rect()
	if opaque.size.x <= 0:
		return 0.0
	var frame_centre_px := (
		float(opaque.position.x) + float(opaque.size.x) * 0.5
		- float(frame_width) * 0.5
	)
	_body_centre_cache[cache_key] = frame_centre_px
	return _apply_authored_orientation(appearance, frame_centre_px)


## Turns a measured body centre into the offset for the authored orientation,
## in world pixels.
func _apply_authored_orientation(
	appearance: CharacterAppearance,
	frame_centre_px: float
) -> float:
	var oriented := -frame_centre_px if appearance.flip_h else frame_centre_px
	return oriented * appearance.sprite_scale.x


## Walks to one authored global position over sampled terrain.
func move_grounded_to(
	target_position: Vector2,
	duration: float,
	floor_sampler: Callable,
	hide_on_finish: bool = false,
	step_height: float = GroundWalkType.DEFAULT_STEP_HEIGHT
) -> Tween:
	reset_speech_motion()
	cancel_grounded_motion()
	var start_position := global_position
	var horizontal_direction := signf(target_position.x - start_position.x)
	if not is_zero_approx(horizontal_direction):
		set_facing_direction(1 if horizontal_direction > 0.0 else -1)
	var ground_path := GroundWalkType.build_path(
		start_position,
		target_position,
		floor_sampler,
		GroundWalkType.DEFAULT_STRIDE_PIXELS
	)
	_departure_tween = GroundWalkType.walk_along(
		self,
		ground_path,
		duration,
		0.0 if _reduce_motion_enabled else step_height
	)
	if _departure_tween != null and hide_on_finish:
		_departure_tween.tween_callback(hide)
	return _departure_tween


## Stops presentation travel without changing the actor's current position.
func cancel_grounded_motion() -> void:
	if _departure_tween != null and _departure_tween.is_valid():
		_departure_tween.kill()
	_departure_tween = null


## Walks right and returns the pause-safe tween used to await the exit.
func depart_right(
	distance: float,
	duration: float,
	floor_sampler: Callable
) -> Tween:
	return move_grounded_to(
		global_position + Vector2.RIGHT * maxf(distance, 0.0),
		duration,
		floor_sampler,
		true
	)
