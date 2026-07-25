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
@export_range(0.0, 64.0, 1.0) var intact_floor_grounding_offset_y: float = 16.0
## Slightly overlaps the sampled dirt edge so texture filtering cannot show a gap.
@export_range(0.0, 4.0, 0.25) var grounding_overlap_y: float = 1.0
## Lifts the sole baseline slightly on each cinematic walking step.
@export_range(0.0, 12.0, 0.5) var cinematic_walk_step_height: float = 4.0
## Controls how many visible walking steps fit along a traversal segment.
@export_range(8.0, 96.0, 1.0) var cinematic_walk_stride_pixels: float = 24.0

@export_category("References")
@export var animation_player: AnimationPlayer
@export var visual_root: Node2D
@export var drawn_miner_sprite: Sprite2D
@export var landing_foot_anchor: Marker2D
@export var idle_miner_texture: Texture2D
@export var wind_up_miner_texture: Texture2D
@export var impact_miner_texture: Texture2D
@export var impact_point: Marker2D
@export var stand_in_hammer_head: Line2D
@export var final_hammer_head_sprite: Sprite2D
@export var impact_audio_player: AudioStreamPlayer2D
@export var speech_reaction: SpeechReactionType

var _playing_full_swing: bool = false
var _rest_position: Vector2
var _visual_root_rest_y: float
var _cinematic_override_active: bool = false
var _cinematic_rest_position: Vector2
var _cinematic_rest_visual_scale: Vector2
var _cinematic_rest_z_index: int
var _cinematic_rest_z_as_relative: bool
var _cinematic_tween: Tween
@onready var _audio_handler: PlayerAudioHandler = (
	PlayerAudioHandler.get_global(self)
)


## Connects animation events and starts the idle animation.
func _ready() -> void:
	_rest_position = position
	_visual_root_rest_y = visual_root.position.y
	_set_miner_texture(idle_miner_texture)
	show_intact_floor_grounding()
	if not animation_player.animation_finished.is_connected(
		_on_animation_finished
	):
		animation_player.animation_finished.connect(
			_on_animation_finished
		)
	_play_idle()


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
func set_screen_offset(screen_offset: Vector2) -> void:
	position = _rest_position + screen_offset


## Restores the visual-only speech motion before another presenter takes over.
func reset_speech_motion() -> void:
	if is_instance_valid(speech_reaction):
		speech_reaction.reset_speech_motion()


## Bounces the miner artwork without changing the gameplay rig position.
func react_to_presented_line() -> void:
	if is_instance_valid(speech_reaction):
		speech_reaction.react_to_presented_line()


## Places the artwork above the first layer on an authored intact floor.
func show_intact_floor_grounding() -> void:
	_set_grounding_offset(intact_floor_grounding_offset_y)


## Seats the authored sole baseline on the renderer's sampled dirt support.
func seat_landing_foot_at_screen_y(support_screen_y: float) -> void:
	if is_nan(support_screen_y) or not is_instance_valid(landing_foot_anchor):
		return
	var grounding_delta: float = (
		support_screen_y
		+ grounding_overlap_y
		- landing_foot_anchor.global_position.y
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
## rather than at the rig origin somewhere up his body.
func get_landing_foot_screen_position() -> Vector2:
	if not is_instance_valid(landing_foot_anchor):
		return global_position
	return landing_foot_anchor.global_position


## Reserves the visual root for a cutscene without moving gameplay position.
func begin_cinematic_visual_override() -> bool:
	if _cinematic_override_active or not is_instance_valid(visual_root):
		return false
	reset_speech_motion()
	_cinematic_override_active = true
	_cinematic_rest_position = visual_root.position
	_cinematic_rest_visual_scale = visual_root.scale
	_cinematic_rest_z_index = z_index
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
	z_index = _cinematic_rest_z_index
	z_as_relative = _cinematic_rest_z_as_relative
	_cinematic_override_active = false
	_cinematic_tween = null
	_play_idle()


## Swaps authored full-frame poses without changing gameplay coordinates.
func _set_miner_texture(texture: Texture2D) -> void:
	if texture != null and is_instance_valid(drawn_miner_sprite):
		drawn_miner_sprite.texture = texture


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
