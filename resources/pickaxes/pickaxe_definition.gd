class_name PickaxeDefinition
extends Resource

## Describes one purchasable pickaxe and the mining modifiers it provides.

enum SpecialEffect {
	NONE,
	AFTERSHOCK,
	RAPID_FOLLOW_UP,
}

@export_category("Identity")
@export var id: StringName = &"basic_pickaxe"
@export var display_name: String = "Basic Pickaxe"
@export_multiline var description: String = "A dependable starting tool."
@export_range(0, 100000, 1) var cost: int = 0

@export_category("Mining")
@export_range(0.1, 5.0, 0.05) var power_multiplier: float = 1.0
@export_range(0.1, 5.0, 0.05) var width_multiplier: float = 1.0
@export_range(0.1, 5.0, 0.05) var swing_speed_multiplier: float = 1.0
@export_range(0.0, 5.0, 0.05) var debris_multiplier: float = 1.0

@export_category("Special Effect")
@export var special_effect: SpecialEffect = SpecialEffect.NONE
@export_range(0, 32, 1) var aftershock_depth_cells: int = 0
@export_range(0.1, 2.0, 0.05) var follow_up_power_scale: float = 0.5
@export_range(0.1, 2.0, 0.05) var follow_up_width_scale: float = 1.0
@export_range(0.1, 3.0, 0.05) var follow_up_speed_scale: float = 1.25
@export_range(0.0, 2.0, 0.05) var follow_up_debris_scale: float = 0.5

@export_category("Appearance")
@export var hammer_head_color: Color = Color(0.94, 0.94, 0.94, 1.0)


## Describes the pickaxe's unique behavior in the shop.
func get_special_effect_summary() -> String:
	match special_effect:
		SpecialEffect.AFTERSHOCK:
			return "Aftershock: breaks %d extra rows" % aftershock_depth_cells
		SpecialEffect.RAPID_FOLLOW_UP:
			return "Rapid follow-up: %.0f%% power bonus strike" % (
				follow_up_power_scale * 100.0
			)
		_:
			return "Special: none"
