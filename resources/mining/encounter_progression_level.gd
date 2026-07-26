class_name EncounterProgressionLevel
extends Resource

## How it works:
## - One resource describes the complete mining and timing rules for one level.
## - Encounter completion replaces the active level instead of stacking deltas.
## - Mining reads impact, double-hit, and animation values.
## - Timing reads speed, baseline count, and combo bonuses.
## - Timing also caps combo groups at the highest group this level unlocked.
## - MiningConfig owns each group's target types and combo threshold.
## - The invariant is that a level is self-contained and never depends on an
##   earlier level having been applied.
## Pickaxe/progression checklist: res://resources/pickaxes/pickaxe_authoring.md

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
## Complete base width/depth tier; this replaces the previous level's value.
@export var impact_size: ImpactSize = ImpactSize.SMALL
## Queues one additional swing for each successful timing result.
@export var double_hit: bool = false
## Complete successful-swing speed tier; it does not stack with older levels.
@export var mine_animation_speed: MineAnimationSpeed = (
	MineAnimationSpeed.NORMAL
)
## Multiplies only the impact added by combo steps, not the base hit.
@export_range(0.1, 5.0, 0.05) var combo_impact_scale: float = 1.1

@export_category("Timing")
## Main timing-bar travel speed in pixels per second.
@export_range(1.0, 5_000.0, 1.0) var slider_speed: float = 500.0
## Baseline targets restored after a lost streak; must be at least one.
@export_range(1, 16, 1) var starting_target_count: int = 1
## Positive combo thresholds in strictly increasing order.
@export var bonus_target_combos: PackedInt32Array = PackedInt32Array()
## Highest inclusive MiningConfig combo-target group available at this level.
@export_range(0, 16, 1) var highest_unlocked_combo_target_group_index: int = 0


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
	var previous_combo := 0
	for bonus_combo: int in bonus_target_combos:
		if bonus_combo <= previous_combo:
			return false
		previous_combo = bonus_combo
	return true
