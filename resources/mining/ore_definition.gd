class_name OreDefinition
extends Resource

## Defines one deterministic ore type that can appear in solid terrain.

@export var ore_id: StringName = &"placeholder_ore"
@export var display_name: String = "Placeholder Ore"
@export var color: Color = Color("d7c15d")
@export_range(0.0, 100.0, 0.01) var spawn_chance_percent: float = 2.0
@export_range(0, 1_000_000, 1) var minimum_depth: int = 0
@export_range(0, 1_000_000, 1) var maximum_depth: int = 100_000


## Reports whether this ore is allowed at the supplied descent.
func can_spawn_at_depth(depth: int) -> bool:
	return (
		depth >= minimum_depth
		and depth <= maximum_depth
	)
