@tool
class_name CutsceneActorPreview
extends Node2D

## How it works:
## - Reads one CharacterAppearance and mirrors CharacterPresenter's Sprite2D.
## - An optional named pose replaces only the texture, sheet grid, and frame.
## - A resource change rebuilds the owned Sprite2D immediately in the editor.
## - In a running game it frees itself in _enter_tree before children ready.
## - The node's origin is the character's feet, because stage markers are on
##   the authored floor line.
## The invariant is that its visible sprite uses the same authored fields and
## pose resolution as the character that will play the cutscene.

@export var actor_id: StringName
@export var appearance: CharacterAppearance:
	set(value):
		if appearance == value:
			return
		_disconnect_appearance_resources()
		appearance = value
		_connect_appearance_resources()
		_rebuild_sprite()
@export var pose: StringName:
	set(value):
		pose = value
		_rebuild_sprite()
@export var remove_in_running_game: bool = true

var _sprite: Sprite2D
var _watched_appearance: CharacterAppearance
var _watched_pose_set: ActorPoseSet


## Stops the editor-only stand-in before a game can ready its sprite child.
## This matches CinematicTerrainPreview: editor nodes never reach gameplay.
func _enter_tree() -> void:
	if Engine.is_editor_hint() or not remove_in_running_game:
		return
	for child in get_children():
		remove_child(child)
		child.free()
	queue_free()


## Ensures the editor has a real child sprite to inspect and position.
func _ready() -> void:
	if not Engine.is_editor_hint() and remove_in_running_game:
		return
	_ensure_sprite()
	_sync_sprite_owner()
	_connect_appearance_resources()
	_rebuild_sprite()


## Returns the one actionable reason this preview cannot draw, or an empty
## string when the authored appearance is drawable.
func get_preview_error() -> String:
	if appearance == null:
		return "Actor preview needs a CharacterAppearance."
	if appearance.texture == null:
		return "CharacterAppearance needs a texture."
	if (
		appearance.horizontal_frames < 1
		or appearance.vertical_frames < 1
	):
		return "CharacterAppearance needs positive sheet frame counts."
	var available_frames := (
		appearance.horizontal_frames * appearance.vertical_frames
	)
	if appearance.frame < 0 or appearance.frame >= available_frames:
		return "CharacterAppearance frame is outside its sprite sheet."
	if not is_instance_valid(_ensure_sprite()):
		return "Actor preview needs its Sprite2D child."
	return ""


func _ensure_sprite() -> Sprite2D:
	if is_instance_valid(_sprite):
		return _sprite
	_sprite = Sprite2D.new()
	_sprite.name = &"PreviewSprite"
	add_child(_sprite)
	_sync_sprite_owner()
	return _sprite


func _sync_sprite_owner() -> void:
	if is_instance_valid(_sprite) and owner != null:
		_sprite.owner = owner


func _connect_appearance_resources() -> void:
	if appearance == null:
		return
	_watched_appearance = appearance
	if not appearance.changed.is_connected(_on_appearance_changed):
		appearance.changed.connect(_on_appearance_changed)
	_watch_pose_set()


func _disconnect_appearance_resources() -> void:
	if (
		_watched_appearance != null
		and _watched_appearance.changed.is_connected(_on_appearance_changed)
	):
		_watched_appearance.changed.disconnect(_on_appearance_changed)
	if (
		_watched_pose_set != null
		and _watched_pose_set.changed.is_connected(_on_pose_set_changed)
	):
		_watched_pose_set.changed.disconnect(_on_pose_set_changed)
	_watched_appearance = null
	_watched_pose_set = null


func _watch_pose_set() -> void:
	var next_pose_set: ActorPoseSet = (
		appearance.pose_set if appearance != null else null
	)
	if _watched_pose_set == next_pose_set:
		return
	if (
		_watched_pose_set != null
		and _watched_pose_set.changed.is_connected(_on_pose_set_changed)
	):
		_watched_pose_set.changed.disconnect(_on_pose_set_changed)
	_watched_pose_set = next_pose_set
	if (
		_watched_pose_set != null
		and not _watched_pose_set.changed.is_connected(_on_pose_set_changed)
	):
		_watched_pose_set.changed.connect(_on_pose_set_changed)


func _on_appearance_changed() -> void:
	_watch_pose_set()
	_rebuild_sprite()


func _on_pose_set_changed() -> void:
	_rebuild_sprite()


func _get_active_pose() -> ActorPose:
	if appearance == null or pose.is_empty() or appearance.pose_set == null:
		return null
	return appearance.pose_set.get_pose(pose)


func _rebuild_sprite() -> void:
	var target := _ensure_sprite()
	_sync_sprite_owner()
	if appearance == null:
		target.texture = null
		target.hframes = 1
		target.vframes = 1
		target.frame = 0
		target.scale = Vector2.ONE
		target.position = Vector2.ZERO
		target.modulate = Color.WHITE
		target.flip_h = false
		return

	target.texture = appearance.texture
	target.hframes = appearance.horizontal_frames
	target.vframes = appearance.vertical_frames
	target.frame = appearance.frame
	target.scale = appearance.sprite_scale
	target.position = appearance.sprite_offset
	target.modulate = appearance.tint
	target.flip_h = appearance.flip_h

	var active_pose := _get_active_pose()
	if active_pose == null:
		return
	target.texture = active_pose.texture
	target.hframes = active_pose.horizontal_frames
	target.vframes = active_pose.vertical_frames
	target.frame = active_pose.first_frame
