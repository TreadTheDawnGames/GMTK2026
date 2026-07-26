class_name ComboTargetGroup
extends Resource

## How it works:
## - One group owns the timing-target pool starting at minimum_combo.
## - MiningConfig keeps groups ordered and selects the last reached group.
## - TimingWindow replaces its pool after the current target set is completed.
## - Target count remains owned by encounter progression and combo bonuses.
## - The invariant is that every group has at least one valid target scene.

## Inclusive combo at which this group replaces the previous target pool.
@export_range(0, 100, 1) var minimum_combo: int = 0
## Complete target pool while this group is active.
@export var target_scenes: Array[PackedScene] = []


## Rejects incomplete target groups before gameplay begins.
func is_valid() -> bool:
	if target_scenes.is_empty():
		return false
	for target_scene: PackedScene in target_scenes:
		if target_scene == null:
			return false
	return true
