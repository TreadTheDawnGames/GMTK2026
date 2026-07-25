class_name SpeechReaction
extends Node

## How it works:
## - An actor assigns its presentation-only Node2D as visual_root.
## - Each presented line starts one short up-and-down motion.
## - A replacement line first restores the exact captured rest position.
## - The tween continues while dialogue pauses the scene tree.
## - Gameplay and actor root transforms are never changed.

@export_category("References")
@export var visual_root: Node2D

@export_category("Motion")
@export_range(1.0, 30.0, 1.0) var bounce_height: float = 7.0
@export_range(0.04, 0.5, 0.01) var bounce_duration: float = 0.14

var _rest_position: Vector2
var _reaction_tween: Tween
var _has_rest_position: bool = false
var _is_reacting: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not is_instance_valid(visual_root):
		push_error("SpeechReaction requires a presentation-only visual root.")
		return
	capture_rest_position()


## Records a newly authored or staged neutral position.
func capture_rest_position() -> void:
	reset_speech_motion()
	if not is_instance_valid(visual_root):
		return
	_rest_position = visual_root.position
	_has_rest_position = true


## Restores the visual immediately and rejects any stale tween completion.
func reset_speech_motion() -> void:
	if _reaction_tween != null and _reaction_tween.is_valid():
		_reaction_tween.kill()
	_reaction_tween = null
	if (
		_is_reacting
		and _has_rest_position
		and is_instance_valid(visual_root)
	):
		visual_root.position = _rest_position
	_is_reacting = false


## Plays one readable bounce without moving the actor's authoritative root.
func react_to_presented_line() -> void:
	reset_speech_motion()
	if not is_instance_valid(visual_root):
		return
	_rest_position = visual_root.position
	_has_rest_position = true
	_is_reacting = true
	var half_duration := bounce_duration * 0.5
	_reaction_tween = create_tween()
	_reaction_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_reaction_tween.tween_property(
		visual_root,
		"position",
		_rest_position + Vector2.UP * bounce_height,
		half_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_reaction_tween.tween_property(
		visual_root,
		"position",
		_rest_position,
		half_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_reaction_tween.tween_callback(_finish_reaction)


func _finish_reaction() -> void:
	if is_instance_valid(visual_root):
		visual_root.position = _rest_position
	_is_reacting = false
	_reaction_tween = null
