class_name MinerRig
extends Node2D

## Plays animations for the miner cutout rig.

signal impact_contact(screen_position: Vector2)
signal swing_finished

@export_category("Playback")
@export_range(0.1, 4.0, 0.05) var animation_speed_multiplier: float = 1.0
@export_range(0.0, 1.0, 0.05) var combo_speed_bonus: float = 0.35

@export_category("Skin")
@export var skin: MinerSkin

@export_category("Core References")
@export var animation_player: AnimationPlayer
@export var visual_root: Node2D
@export var impact_point: Marker2D

@export_category("Artwork Slots")
@export var back_hair_sprite: Sprite2D
@export var body_sprite: Sprite2D
@export var head_sprite: Sprite2D
@export var front_hair_sprite: Sprite2D
@export var upper_arm_sprite: Sprite2D
@export var forearm_sprite: Sprite2D
@export var hand_sprite: Sprite2D
@export var pickaxe_handle_sprite: Sprite2D
@export var final_hammer_head_sprite: Sprite2D

@export_category("Placeholder References")
@export var stand_in_body_outline: CanvasItem
@export var stand_in_body_fill: CanvasItem
@export var stand_in_head_outline: CanvasItem
@export var stand_in_head_fill: CanvasItem
@export var stand_in_arm_outline: CanvasItem
@export var stand_in_arm_fill: CanvasItem
@export var stand_in_hammer_handle: CanvasItem
@export var stand_in_hammer_head: Line2D

@export_category("Audio")
@export var swing_audio_player: AudioStreamPlayer2D
@export var impact_audio_player: AudioStreamPlayer2D

var _playing_full_swing: bool = false
var _default_swing_stream: AudioStream
var _default_impact_stream: AudioStream


## Starts the idle animation when the rig loads.
func _ready() -> void:
	_default_swing_stream = swing_audio_player.stream
	_default_impact_stream = impact_audio_player.stream
	apply_skin(skin)
	_play_idle()


## Plays the successful strike at its combo and equipped-pickaxe speed.
func play_success(
	_combo: int,
	effect_strength: float,
	swing_speed_multiplier: float
) -> void:
	var combo_multiplier := lerpf(
		1.0,
		1.0 + combo_speed_bonus,
		effect_strength
	)
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	if swing_audio_player.stream != null:
		swing_audio_player.play()
	animation_player.play(
		&"mine_success",
		-1.0,
		combo_multiplier * maxf(swing_speed_multiplier, 0.1)
	)


## Reports the hammer-tip position when the animation reaches the ground.
func _emit_success_impact() -> void:
	if impact_audio_player.stream != null:
		impact_audio_player.play()
	impact_contact.emit(impact_point.global_position)


## Plays the missed-swing animation.
func play_miss(_combo: int) -> void:
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"mine_miss")


## Plays the wind-up animation.
func play_wind_up() -> void:
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_up")


## Plays the downward strike animation.
func play_wind_down() -> void:
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"wind_down")


## Plays the complete wind-up and strike sequence.
func play_full_swing() -> void:
	# Authoring preview for the three-control wind-up and wind-down clips.
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


## Plays an authored clip by name for the standalone rig preview.
func play_preview_animation(animation_name: StringName) -> bool:
	if not animation_player.has_animation(animation_name):
		return false
	_playing_full_swing = false
	animation_player.stop()
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(animation_name)
	return true


## Applies the equipped color to placeholder and final hammer-head art.
func set_hammer_head_color(color: Color) -> void:
	if is_instance_valid(stand_in_hammer_head):
		stand_in_hammer_head.default_color = color
	if is_instance_valid(final_hammer_head_sprite):
		final_hammer_head_sprite.self_modulate = color


## Applies aligned character layers while retaining placeholders for empty slots.
func apply_skin(definition: MinerSkin) -> void:
	skin = definition
	var tint := skin.skin_tint if skin != null else Color.WHITE
	var authored_scale := skin.default_scale if skin != null else 1.0
	var facing_sign := signf(visual_root.scale.x)
	if is_zero_approx(facing_sign):
		facing_sign = 1.0
	visual_root.scale = Vector2(
		authored_scale * facing_sign,
		authored_scale
	)

	_apply_texture_slot(
		body_sprite,
		skin.body_texture if skin != null else null,
		tint
	)
	_set_placeholder_pair_visible(
		stand_in_body_outline,
		stand_in_body_fill,
		body_sprite.texture == null
	)
	_apply_texture_slot(
		head_sprite,
		skin.head_texture if skin != null else null,
		tint
	)
	_set_placeholder_pair_visible(
		stand_in_head_outline,
		stand_in_head_fill,
		head_sprite.texture == null
	)
	_apply_texture_slot(
		upper_arm_sprite,
		skin.upper_arm_texture if skin != null else null,
		tint
	)
	_apply_texture_slot(
		forearm_sprite,
		skin.forearm_texture if skin != null else null,
		tint
	)
	_apply_texture_slot(
		hand_sprite,
		skin.hand_texture if skin != null else null,
		tint
	)
	var has_arm_art := (
		upper_arm_sprite.texture != null
		and forearm_sprite.texture != null
		and hand_sprite.texture != null
	)
	_set_placeholder_pair_visible(
		stand_in_arm_outline,
		stand_in_arm_fill,
		not has_arm_art
	)
	_apply_texture_slot(
		back_hair_sprite,
		skin.back_hair_texture if skin != null else null,
		tint
	)
	_apply_texture_slot(
		front_hair_sprite,
		skin.front_hair_texture if skin != null else null,
		tint
	)


## Applies equipped tool art, sound, scale, color, and impact alignment.
func apply_pickaxe_definition(definition: PickaxeDefinition) -> void:
	if definition == null:
		return
	pickaxe_handle_sprite.texture = definition.handle_texture
	pickaxe_handle_sprite.scale = Vector2.ONE * definition.visual_scale
	final_hammer_head_sprite.texture = definition.head_texture
	final_hammer_head_sprite.position = definition.head_offset
	final_hammer_head_sprite.scale = Vector2.ONE * definition.visual_scale
	impact_point.position = (
		definition.impact_offset * definition.visual_scale
	)
	stand_in_hammer_handle.visible = definition.handle_texture == null
	stand_in_hammer_head.visible = definition.head_texture == null
	swing_audio_player.stream = (
		definition.swing_sound
		if definition.swing_sound != null
		else _default_swing_stream
	)
	impact_audio_player.stream = (
		definition.impact_sound
		if definition.impact_sound != null
		else _default_impact_stream
	)
	set_hammer_head_color(definition.hammer_head_color)


## Faces the visible miner toward the selected mining side.
func set_facing_direction(direction: int) -> void:
	if not is_instance_valid(visual_root) or direction == 0:
		return
	visual_root.scale.x = absf(visual_root.scale.x) * signi(direction)


## Assigns one optional cutout texture and its shared skin tint.
func _apply_texture_slot(
	sprite: Sprite2D,
	texture: Texture2D,
	tint: Color
) -> void:
	sprite.texture = texture
	sprite.self_modulate = tint


## Shows or hides one outline-and-fill placeholder pair.
func _set_placeholder_pair_visible(
	outline: CanvasItem,
	fill: CanvasItem,
	is_visible: bool
) -> void:
	outline.visible = is_visible
	fill.visible = is_visible


## Returns finished actions to idle after any queued strike plays.
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"wind_up" and _playing_full_swing:
		return
	if animation_name == &"mine_success":
		_playing_full_swing = false
		_play_idle()
		swing_finished.emit()
		return
	if animation_name != &"idle" and animation_name != &"wind_up":
		_playing_full_swing = false
		_play_idle()


## Plays idle at the current speed setting.
func _play_idle() -> void:
	animation_player.speed_scale = animation_speed_multiplier
	animation_player.play(&"idle")
