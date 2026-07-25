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
var _missing_warning: Polygon2D
var _missing_warning_cross_a: Line2D
var _missing_warning_cross_b: Line2D
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


func _ensure_missing_warning() -> void:
	if is_instance_valid(_missing_warning):
		return
	_missing_warning = Polygon2D.new()
	_missing_warning.name = &"MissingAppearanceWarning"
	_missing_warning.position = Vector2(0.0, -36.0)
	_missing_warning.polygon = PackedVector2Array([
		Vector2(-20.0, -20.0),
		Vector2(20.0, -20.0),
		Vector2(20.0, 20.0),
		Vector2(-20.0, 20.0),
	])
	_missing_warning.color = Color(1.0, 0.0, 0.8, 0.85)
	add_child(_missing_warning)
	_missing_warning_cross_a = _make_warning_cross(&"MissingAppearanceCrossA")
	_missing_warning_cross_a.position = _missing_warning.position
	_missing_warning_cross_a.points = PackedVector2Array([
		Vector2(-15.0, -15.0),
		Vector2(15.0, 15.0),
	])
	add_child(_missing_warning_cross_a)
	_missing_warning_cross_b = _make_warning_cross(&"MissingAppearanceCrossB")
	_missing_warning_cross_b.position = _missing_warning.position
	_missing_warning_cross_b.points = PackedVector2Array([
		Vector2(-15.0, 15.0),
		Vector2(15.0, -15.0),
	])
	add_child(_missing_warning_cross_b)
	_sync_generated_child_owners()


func _make_warning_cross(cross_name: StringName) -> Line2D:
	var cross := Line2D.new()
	cross.name = cross_name
	cross.width = 5.0
	cross.default_color = Color(0.05, 0.0, 0.05, 1.0)
	return cross


func _sync_sprite_owner() -> void:
	if is_instance_valid(_sprite) and owner != null:
		_sprite.owner = owner
	_sync_generated_child_owners()


func _sync_generated_child_owners() -> void:
	for generated_child: Node in get_children():
		if generated_child != self and owner != null:
			generated_child.owner = owner


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
	_ensure_missing_warning()
	var is_drawable := _is_drawable_appearance()
	_missing_warning.visible = not is_drawable
	_missing_warning_cross_a.visible = not is_drawable
	_missing_warning_cross_b.visible = not is_drawable
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

	if not is_drawable:
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


func _is_drawable_appearance() -> bool:
	if appearance == null or appearance.texture == null:
		return false
	if appearance.horizontal_frames < 1 or appearance.vertical_frames < 1:
		return false
	var available_frames := (
		appearance.horizontal_frames * appearance.vertical_frames
	)
	return appearance.frame >= 0 and appearance.frame < available_frames
