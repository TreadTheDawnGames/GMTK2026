class_name ComboTargetGroup
extends Resource

## How it works:
## - One group adds target types starting at minimum_combo.
## - MiningConfig accumulates every group reached up to progression's cap.
## - TimingWindow expands its pool after the current target set is completed.
## - Target count remains owned by encounter progression and combo bonuses.
## - The invariant is that every group has at least one valid target scene.

## Inclusive combo at which this group's target types become available.
@export_range(0, 100, 1) var minimum_combo: int = 0
## New target types added to the cumulative pool at this threshold.
@export var target_scenes: Array[PackedScene] = []


## Rejects incomplete target groups before gameplay begins.
func is_valid() -> bool:
	if target_scenes.is_empty():
		return false
	for target_scene: PackedScene in target_scenes:
		if target_scene == null:
			return false
	return true
