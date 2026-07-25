class_name EncounterProgressionLevel
extends Resource

## How it works:
## - One resource describes the complete mining and timing rules for one level.
## - Encounter completion replaces the active level instead of stacking deltas.
## - Mining reads impact, double-hit, and animation values.
## - Timing reads its target pool, speed, baseline count, and combo bonuses.
## - The invariant is that a level is self-contained and never depends on an
##   earlier level having been applied.

enum ImpactSize {
	SMALL,
	MEDIUM,
	LARGE,
}

enum MineAnimationSpeed {
	NORMAL,
	FASTER,
	MUCH_FASTER,
}

# Small begins below the legacy base impact so the three authored tiers have
# room to escalate instead of making level zero feel upgraded already.
const _IMPACT_SIZE_MULTIPLIERS: Array[float] = [0.5, 1.0, 1.5]
const _ANIMATION_SPEED_MULTIPLIERS: Array[float] = [1.0, 1.25, 1.5]

@export_category("Mining")
@export var impact_size: ImpactSize = ImpactSize.SMALL
@export var double_hit: bool = false
@export var mine_animation_speed: MineAnimationSpeed = (
	MineAnimationSpeed.NORMAL
)
## Multiplies only the impact added by combo steps, not the base hit.
@export_range(0.1, 5.0, 0.05) var combo_impact_scale: float = 1.1

@export_category("Timing")
@export var target_scenes: Array[PackedScene] = []
@export_range(1.0, 5_000.0, 1.0) var slider_speed: float = 500.0
@export_range(1, 16, 1) var starting_target_count: int = 1
@export var bonus_target_combos: PackedInt32Array = PackedInt32Array()


## Scales one impact dimension from its base and combo-added portions.
func scale_impact(base_size: float, combo_added_size: float) -> int:
	var impact_multiplier := _IMPACT_SIZE_MULTIPLIERS[impact_size]
	return maxi(
		roundi(
			base_size * impact_multiplier
				+ combo_added_size * combo_impact_scale
		),
		1
	)


## Returns the authored playback multiplier for successful mining swings.
func get_mine_animation_speed_multiplier() -> float:
	return _ANIMATION_SPEED_MULTIPLIERS[mine_animation_speed]


## Rejects incomplete authored levels before gameplay begins.
func is_valid() -> bool:
	if target_scenes.is_empty():
		return false
	for target_scene: PackedScene in target_scenes:
		if target_scene == null:
			return false
	var previous_combo := 0
	for bonus_combo: int in bonus_target_combos:
		if bonus_combo <= previous_combo:
			return false
		previous_combo = bonus_combo
	return true
