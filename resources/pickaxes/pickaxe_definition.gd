class_name PickaxeDefinition
extends Resource

## Describes one equippable pickaxe and the mining modifiers it provides.

enum SpecialEffect {
	NONE,
	AFTERSHOCK,
	RAPID_FOLLOW_UP,
}

@export_category("Identity")
@export var id: StringName = &"basic_pickaxe"
@export var display_name: String = "Basic Pickaxe"
@export_multiline var description: String = "A dependable starting tool."

@export_category("Mining")
## Multiplies the downward rows removed by each hit.
@export_range(0.1, 5.0, 0.05) var power_multiplier: float = 1.0
## Multiplies the horizontal tunnel width removed by each hit.
@export_range(0.1, 5.0, 0.05) var width_multiplier: float = 1.0
## Multiplies the successful swing animation speed.
@export_range(0.1, 5.0, 0.05) var swing_speed_multiplier: float = 1.0
## Multiplies the dirt pieces emitted at impact.
@export_range(0.0, 5.0, 0.05) var debris_multiplier: float = 1.0

@export_category("Special Effect")
@export var special_effect: SpecialEffect = SpecialEffect.NONE
## Adds these downward rows after the primary hit for AFTERSHOCK.
@export_range(0, 32, 1) var aftershock_depth_rows: int = 0
## Multiplies mining power for RAPID_FOLLOW_UP's bonus swing.
@export_range(0.1, 2.0, 0.05) var follow_up_power_scale: float = 0.5
## Multiplies tunnel width for RAPID_FOLLOW_UP's bonus swing.
@export_range(0.1, 2.0, 0.05) var follow_up_width_scale: float = 1.0
## Multiplies animation speed for RAPID_FOLLOW_UP's bonus swing.
@export_range(0.1, 3.0, 0.05) var follow_up_speed_scale: float = 1.25
## Multiplies dirt pieces for RAPID_FOLLOW_UP's bonus swing.
@export_range(0.0, 2.0, 0.05) var follow_up_debris_scale: float = 0.5

@export_category("Appearance")
@export var hammer_head_color: Color = Color(0.94, 0.94, 0.94, 1.0)
