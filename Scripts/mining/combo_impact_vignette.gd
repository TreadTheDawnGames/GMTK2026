class_name ComboImpactVignette
extends CanvasLayer

## How it works:
## - Every successful impact raises a sustained edge darkness from that hit's
##   combo strength and adds a short punch on top of it.
## - Both values decay every frame, so a streak that simply stops being fed
##   releases the frame without this node subscribing to a streak signal; a
##   real miss calls release() for the immediate snap-off.
## - Only combos past engage_combo_strength darken anything, so ordinary early
##   hits look exactly as they did before.
## - The rect and its processing switch off the moment both values reach zero.
## The invariant is that this layer costs nothing while no combo is running,
## and that it never reads or writes gameplay state.

@export_category("References")
@export var vignette_rect: ColorRect

@export_category("Response")
## Combo strength a hit must reach before the frame reacts at all. Combo
## strength is combo / MiningConfig.maximum_effect_combo, already clamped.
@export_range(0.0, 1.0, 0.05) var engage_combo_strength: float = 0.3
## Darkness a fully-maxed combo sustains between hits.
@export_range(0.0, 1.0, 0.05) var maximum_darkness: float = 0.7
## Extra darkness and inward push a single impact adds on top of the sustain.
@export_range(0.0, 1.0, 0.05) var maximum_punch: float = 1.0

@export_category("Timing")
## How fast the visible darkness chases the level the last hit asked for.
@export_range(0.5, 30.0, 0.5) var sustain_attack_per_second: float = 5.0
## How fast an unfed streak gives the frame back.
@export_range(0.05, 8.0, 0.05) var sustain_decay_per_second: float = 0.85
## How fast a single hit's punch collapses.
@export_range(0.5, 30.0, 0.5) var punch_decay_per_second: float = 6.5
## How fast release() drains a lost streak's remaining frame.
@export_range(0.5, 30.0, 0.5) var release_decay_per_second: float = 4.5

var _requested_darkness: float = 0.0
var _current_darkness: float = 0.0
var _punch: float = 0.0
var _is_releasing: bool = false


## Sleeps the layer until the first combo large enough to darken the frame.
func _ready() -> void:
	set_process(false)
	if vignette_rect != null:
		vignette_rect.visible = false
	_apply_shader_values()
	if not get_viewport().size_changed.is_connected(_update_viewport_aspect):
		get_viewport().size_changed.connect(_update_viewport_aspect)
	_update_viewport_aspect()


## Reacts to one landed hit. Shares the impact presentation signature so the
## scene wiring routes it exactly like the shake, dust, and debris do.
func play_at_impact(
	_impact_screen_position: Vector2,
	cells_removed: int,
	combo_strength: float,
	_debris_multiplier: float = 1.0,
	_swing_side: int = 1
) -> void:
	if cells_removed <= 0 or vignette_rect == null:
		return
	# Below the engagement point a hit contributes nothing, and the range above
	# it is renormalised so the first darkening hit still starts from zero.
	var engaged_strength := inverse_lerp(
		clampf(engage_combo_strength, 0.0, 0.99),
		1.0,
		clampf(combo_strength, 0.0, 1.0)
	)
	if engaged_strength <= 0.0:
		return
	_is_releasing = false
	_requested_darkness = maxf(
		_requested_darkness,
		engaged_strength * maximum_darkness
	)
	_punch = maxf(_punch, engaged_strength * maximum_punch)
	vignette_rect.visible = true
	set_process(true)


## Gives the frame straight back when a streak is actually lost.
func release(_combo: int = 0) -> void:
	if _current_darkness <= 0.0 and _punch <= 0.0:
		return
	_is_releasing = true
	_requested_darkness = 0.0


## Eases the sustained frame, collapses the punch, and sleeps when both rest.
func _process(delta: float) -> void:
	var decay_rate := (
		release_decay_per_second
		if _is_releasing
		else sustain_decay_per_second
	)
	_requested_darkness = move_toward(
		_requested_darkness,
		0.0,
		decay_rate * delta
	)
	var chase_rate := (
		release_decay_per_second
		if _is_releasing
		else sustain_attack_per_second
	)
	_current_darkness = move_toward(
		_current_darkness,
		_requested_darkness,
		chase_rate * delta
	)
	_punch = move_toward(_punch, 0.0, punch_decay_per_second * delta)
	_apply_shader_values()
	if _current_darkness <= 0.0 and _punch <= 0.0:
		_is_releasing = false
		if vignette_rect != null:
			vignette_rect.visible = false
		set_process(false)


## Pushes the two driven values into the frame material.
func _apply_shader_values() -> void:
	if vignette_rect == null:
		return
	var frame_material := vignette_rect.material as ShaderMaterial
	if frame_material == null:
		return
	frame_material.set_shader_parameter(&"strength", _current_darkness)
	frame_material.set_shader_parameter(&"pulse", _punch)


## Keeps the frame elliptical against the current window rather than the
## authored one, because the export stretches with an expanding aspect.
func _update_viewport_aspect() -> void:
	if vignette_rect == null:
		return
	var frame_material := vignette_rect.material as ShaderMaterial
	if frame_material == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	frame_material.set_shader_parameter(
		&"viewport_aspect",
		viewport_size.x / maxf(viewport_size.y, 1.0)
	)
