extends CharacterEncounterStage

## How it works:
## - The shared stage still owns actors, camera cues, and timeline playback.
## - Dialogue speaker notifications only toggle the cafe's local shader material.
## - Cheese Girl's painted window glows while her line is the active line.
## - A fixed eight-actor rat crowd is visible before the miner enters the room.
## - A new speaker or cancellation clears the effect immediately.
## - The invariant is that cancelled staging leaves no highlight or duplicate rats.

const _CHEESE_GIRL_SPEAKER := &"cheese_girl"
const _SPEAKING_PARAMETER := &"coco_speaking"

@onready var _cafe_sprite: Sprite2D = $PropMarkers/DasQuesoCafe
@onready var _rat_crowd: Node2D = $PropMarkers/RatCrowd


func _ready() -> void:
	super._ready()
	_set_coco_speaking(false)
	# RatMiner instances hide themselves during their own readiness. The stage
	# runs after its children and restores this authored, bounded set now so the
	# occupied cafe is already present while the miner falls into the room.
	_set_rat_crowd_visible(true)


func prepare(
	presenter: CharacterPresenter,
	floor_sampler: Callable
) -> bool:
	_set_coco_speaking(false)
	if not super.prepare(presenter, floor_sampler):
		return false
	return true


func on_dialogue_line_presented(
	speaker_slot: StringName,
	_line_index: int
) -> void:
	_set_coco_speaking(speaker_slot == _CHEESE_GIRL_SPEAKER)


func cancel_and_restore() -> void:
	_set_coco_speaking(false)
	super.cancel_and_restore()


func _set_coco_speaking(is_speaking: bool) -> void:
	if not is_instance_valid(_cafe_sprite):
		return
	var cafe_material := _cafe_sprite.material as ShaderMaterial
	if cafe_material == null:
		return
	cafe_material.set_shader_parameter(
		_SPEAKING_PARAMETER,
		1.0 if is_speaking else 0.0
	)


## Shows the bounded cafe crowd without activating the persistent mining colony.
func _set_rat_crowd_visible(is_visible: bool) -> void:
	if not is_instance_valid(_rat_crowd):
		return
	for crowd_actor in _rat_crowd.get_children():
		if crowd_actor is not CanvasItem:
			continue
		(crowd_actor as CanvasItem).visible = is_visible
