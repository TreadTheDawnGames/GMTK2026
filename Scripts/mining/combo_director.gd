class_name ComboDirector
extends Node

## How it works:
## - Production inputs are resolved hits and ended streaks.
## - Legacy reward callbacks remain isolated and are not connected in gameplay.
## - Output: one intensity step that music, camera, and impact presenters read
##   instead of each re-deriving combo / maximum_effect_combo on its own.
## - Owned state: the live combo, the tier it sits in, and the reward level.
## - Production intensity follows the live combo tier because reward cutscenes
##   now unlock timing-target groups instead of raising a permanent floor.
## - The invariant is that shipped wiring cannot raise intensity without combo.

signal intensity_changed(intensity: int, previous_intensity: int)
## Reports only the live combo portion, so a tier-up still reads as a moment
## even when the reward floor already covers that step.
signal combo_tier_changed(tier: int, previous_tier: int)
signal escalation_changed(level: int)
signal streak_lost(previous_combo: int, previous_tier: int)

@export_category("References")
## Owns combo_tier_thresholds. The timing bar's gauge reads the same array, so
## the bar, the music, and the camera cannot disagree about the current step.
@export var config: MiningConfig

@export_category("Escalation")
## Caps the floor rewards can raise, leaving the top step reachable only by
## combo. Without this the late run sits at maximum and combos stop mattering.
@export_range(0, 8, 1) var maximum_escalation_floor: int = 2

var combo: int = 0
var combo_tier: int = 0
var escalation_level: int = 0
var intensity: int = 0


## Reports the shared thresholds, or an empty list when no config is attached.
var combo_tier_thresholds: Array[int]:
	get:
		return (
			[] as Array[int]
			if config == null
			else config.combo_tier_thresholds
		)


## Reports the highest reachable step, which is also the last tier index.
var maximum_intensity: int:
	get:
		return combo_tier_thresholds.size()


## Reports how far the live combo sits between its tier and the next one, for
## consumers that want a smooth value rather than the step.
var tier_progress: float:
	get:
		return _progress_within_tier(combo)


## Fails loudly rather than silently resolving every combo to tier zero.
func _ready() -> void:
	if config == null:
		push_error("ComboDirector requires a MiningConfig.")


## Adopts a resolved hit's combo. Follow-up swings repeat the same combo and
## simply resolve to the same tier.
func _on_mine_resolved(
	_depth_gained: int,
	_cells_removed: int,
	resolved_combo: int,
	_combo_strength: float
) -> void:
	_set_combo(maxi(resolved_combo, 0))


## Drops the live combo the moment a streak is actually lost. A miss that opens
## the recovery window is not a loss and must not reach this.
func _on_streak_ended(previous_combo: int) -> void:
	var lost_tier := combo_tier
	_set_combo(0)
	streak_lost.emit(maxi(previous_combo, 0), lost_tier)


## Legacy isolated-preview hook; production wiring does not connect rewards.
func _on_upgrade_granted(_definition: PickaxeDefinition) -> void:
	_raise_escalation()


## Legacy isolated-preview hook; production wiring does not connect rewards.
func _on_coffee_boost_awarded(_speed_multiplier: float) -> void:
	_raise_escalation()


## Legacy isolated-preview hook; production wiring does not connect rewards.
func _on_rat_colony_support_requested() -> void:
	_raise_escalation()


## Returns the run to its opening loudness.
func _on_run_reset() -> void:
	combo = 0
	combo_tier = 0
	escalation_level = 0
	escalation_changed.emit(escalation_level)
	_publish(0, 0)


## Adopts a combo and republishes the tier and intensity it resolves to.
func _set_combo(new_combo: int) -> void:
	combo = new_combo
	var previous_tier := combo_tier
	var previous_intensity := intensity
	combo_tier = _tier_for_combo(combo)
	if combo_tier != previous_tier:
		combo_tier_changed.emit(combo_tier, previous_tier)
	_publish(previous_tier, previous_intensity)


## Adds one reward step, bounded by the floor cap.
func _raise_escalation() -> void:
	var raised_level := mini(
		escalation_level + 1,
		mini(maximum_escalation_floor, maximum_intensity)
	)
	if raised_level == escalation_level:
		return
	escalation_level = raised_level
	escalation_changed.emit(escalation_level)
	_publish(combo_tier, intensity)


## Recomputes intensity from the floor and the live tier, and reports changes.
func _publish(_previous_tier: int, previous_intensity: int) -> void:
	intensity = clampi(
		maxi(escalation_level, combo_tier),
		0,
		maximum_intensity
	)
	if intensity != previous_intensity:
		intensity_changed.emit(intensity, previous_intensity)


## Counts how many authored thresholds a combo has reached.
func _tier_for_combo(value: int) -> int:
	var tier := 0
	for threshold: int in combo_tier_thresholds:
		if value >= threshold:
			tier += 1
	return mini(tier, maximum_intensity)


## Normalizes a combo to 0..1 across the tier band it currently occupies.
func _progress_within_tier(value: int) -> float:
	if combo_tier_thresholds.is_empty():
		return 0.0
	var tier := _tier_for_combo(value)
	if tier >= combo_tier_thresholds.size():
		return 1.0
	var band_start := (
		0
		if tier == 0
		else combo_tier_thresholds[tier - 1]
	)
	var band_end: int = combo_tier_thresholds[tier]
	if band_end <= band_start:
		return 1.0
	return clampf(
		float(value - band_start) / float(band_end - band_start),
		0.0,
		1.0
	)
