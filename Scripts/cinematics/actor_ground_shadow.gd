@tool
class_name ActorGroundShadow
extends Node2D

## How it works:
## - Draws one soft contact shadow on the ground beneath whatever it is a child
##   of, using actor_ground_shadow.gdshader on a plain quad.
## - It owns no art and reads nothing about the scene: the shader makes the
##   ellipse, and the only thing this node decides is how big it is and where
##   the ground under the actor is.
## - Size follows the actor's own width, so a rat's shadow is a rat's shadow and
##   the miner's is his, without either being authored twice.
## - Drawn behind its actor and in front of the walkway, which is the only order
##   in which it reads as being on the floor rather than on the character.
## The invariant is that it never moves its parent and never reads terrain; it
## is presentation laid under an actor and nothing else.

const _SHADOW_SHADER := preload("res://Shaders/actor_ground_shadow.gdshader")
## Alpha a pixel needs before it counts as drawn. Well above zero, so erased
## leftovers in a frame do not widen the shadow to cover the whole canvas.
const _MEASURE_ALPHA_THRESHOLD: float = 0.12
## Grid the frame is sampled on. A character is never one pixel wide, so this
## keeps a one-off measurement cheap enough to run on load and in the editor.
const _MEASURE_SAMPLE_STEP: int = 4

## Drawn width per texture, so the same frame is only ever measured once.
static var _drawn_widths: Dictionary = {}

## Width of the shadow as a fraction of the actor's drawn width. Wider than the
## body, because a shadow that stops at the silhouette reads as a dark outline
## rather than as light being blocked.
@export_range(0.5, 3.0, 0.05) var width_scale: float = 1.35:
	set(value):
		width_scale = value
		_rebuild()
## Height of the shadow relative to its width.
@export_range(0.05, 1.0, 0.01) var height_ratio: float = 0.3:
	set(value):
		height_ratio = value
		_rebuild()
## Fallback width used before an actor's art can be measured.
@export_range(8.0, 512.0, 1.0) var fallback_width: float = 64.0:
	set(value):
		fallback_width = value
		_rebuild()
## The sprite to take the actor's width from, when it is not a plain sibling.
##
## The editor's stand-in keeps its sprite right beside this node, but the
## runtime cast nests theirs under animation roots, and the miner's lives under
## his visual root. Naming it outright is what lets one shadow serve all three
## rather than each growing its own.
@export var measured_sprite: Sprite2D:
	set(value):
		measured_sprite = value
		_rebuild()
## Draw order relative to the actor. Negative keeps it underneath.
@export_range(-16, 0, 1) var relative_draw_order: int = -1:
	set(value):
		relative_draw_order = value
		z_index = value

var _quad: Sprite2D


func _ready() -> void:
	z_as_relative = true
	z_index = relative_draw_order
	_rebuild()


## Rebuilds the quad the shader draws on, sized from the actor above it.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	var width := _measure_actor_width()
	var shadow_size := Vector2(width * width_scale, width * width_scale * height_ratio)
	if not is_instance_valid(_quad):
		_quad = Sprite2D.new()
		_quad.name = &"ShadowQuad"
		# A one-pixel white texture stretched to size: the shader paints every
		# pixel, so the texture exists only to give it an area to run over.
		var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		image.set_pixel(0, 0, Color.WHITE)
		_quad.texture = ImageTexture.create_from_image(image)
		var material := ShaderMaterial.new()
		material.shader = _SHADOW_SHADER
		_quad.material = material
		add_child(_quad)
	_quad.scale = shadow_size
	_quad.owner = null


## Returns how wide the actor above this shadow is drawn, in this node's space.
##
## Measured from the sibling sprite rather than authored, so changing a
## character's art or scale moves their shadow with it. Falls back to a stated
## width when there is nothing to measure yet, which is the case for one frame
## while an appearance is still being applied.
func _measure_actor_width() -> float:
	if is_instance_valid(measured_sprite) and measured_sprite.texture != null:
		# Global scale, because the sprite may sit under animation roots that
		# carry a scale of their own between it and this node.
		var named_width := (
			_measure_drawn_width(measured_sprite)
			* absf(measured_sprite.global_scale.x)
		)
		if named_width > 1.0:
			return named_width
	var actor := get_parent() as Node2D
	if actor == null:
		return fallback_width
	for sibling in actor.get_children():
		var sprite := sibling as Sprite2D
		if sprite == null or sprite == _quad or sprite.texture == null:
			continue
		var measured := (
			_measure_drawn_width(sprite)
			* absf(sprite.scale.x)
		)
		if measured > 1.0:
			return measured
	return fallback_width


## Returns how wide the character is actually drawn inside its own frame, in
## texture pixels.
##
## The canvas is not the character. The miner's frames are an 1112 px sheet with
## about a quarter of that drawn on, so a shadow sized to the canvas came out
## four times too wide and pooled over his own boots instead of sitting under
## them. Faint erased leftovers are ignored on purpose: they are invisible in
## the shot but they are not transparent, so a plain used-rect measures them.
##
## Sampled on a grid and cached per texture. It is a one-off measurement of art
## that does not change while the game runs, and it also runs in the editor.
static func _measure_drawn_width(sprite: Sprite2D) -> float:
	var frame_width := float(sprite.texture.get_width())
	if sprite.hframes > 1:
		frame_width /= float(sprite.hframes)
	var texture_id := sprite.texture.get_rid().get_id()
	if _drawn_widths.has(texture_id):
		return minf(float(_drawn_widths[texture_id]), frame_width)
	var image := sprite.texture.get_image()
	if image == null:
		return frame_width
	var left := image.get_width()
	var right := -1
	for x in range(0, image.get_width(), _MEASURE_SAMPLE_STEP):
		for y in range(0, image.get_height(), _MEASURE_SAMPLE_STEP):
			if image.get_pixel(x, y).a < _MEASURE_ALPHA_THRESHOLD:
				continue
			left = mini(left, x)
			right = maxi(right, x)
			break
	var drawn_width := float(right - left + _MEASURE_SAMPLE_STEP)
	if right < 0 or drawn_width <= 1.0:
		drawn_width = frame_width
	_drawn_widths[texture_id] = drawn_width
	return minf(drawn_width, frame_width)


## Weakens the shadow as an actor leaves the ground, so it does not travel with
## a character through the air as though painted to their feet.
func set_contact_strength(strength: float) -> void:
	if not is_instance_valid(_quad):
		return
	var material := _quad.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter(
		&"contact_strength", clampf(strength, 0.0, 1.0)
	)
