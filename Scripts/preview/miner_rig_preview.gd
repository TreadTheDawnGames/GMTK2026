class_name MinerRigPreview
extends Node2D

## Tests cutout skins, pickaxe art, and authored clips in isolation.

@export_category("Artwork")
@export var skin: MinerSkin
@export var pickaxe: PickaxeDefinition

@export_category("References")
@export var miner_rig: MinerRig
@export var combo_slider: HSlider
@export var speed_slider: HSlider
@export var guide_overlay: CanvasItem
@export var status_label: Label


## Applies Inspector-selected artwork before starting the idle preview.
func _ready() -> void:
	miner_rig.apply_skin(skin)
	miner_rig.apply_pickaxe_definition(pickaxe)
	_on_speed_changed(speed_slider.value)
	_play_named(&"idle")


## Previews a successful hit at the selected combo strength.
func _on_hit_pressed() -> void:
	var combo := roundi(combo_slider.value)
	var effect_strength := clampf(float(combo) / 20.0, 0.0, 1.0)
	miner_rig.play_success(combo, effect_strength, 1.0)
	status_label.text = "Playing hit at combo %d" % combo


## Previews the current missed-hit animation.
func _on_miss_pressed() -> void:
	miner_rig.play_miss(0)
	status_label.text = "Playing miss"


## Applies the selected speed to subsequent preview clips.
func _on_speed_changed(value: float) -> void:
	miner_rig.set_animation_speed_multiplier(value)


## Shows or hides pivot and fixed ChipOrigin markers.
func _on_guides_toggled(is_enabled: bool) -> void:
	guide_overlay.visible = is_enabled


## Plays a requested clip or identifies an art-ready missing slot.
func _play_named(animation_name: StringName) -> void:
	if miner_rig.play_preview_animation(animation_name):
		status_label.text = "Playing %s" % animation_name
		return
	status_label.text = "%s is ready to be authored" % animation_name


## Returns the preview rig to its authored idle loop.
func _on_idle_pressed() -> void:
	_play_named(&"idle")


## Previews the falling pose when that clip exists.
func _on_fall_pressed() -> void:
	_play_named(&"fall")


## Previews the landing pose when that clip exists.
func _on_land_pressed() -> void:
	_play_named(&"land")


## Previews the dialogue pose when that clip exists.
func _on_talk_pressed() -> void:
	_play_named(&"talk")
