class_name PickaxeDefinition
extends Resource

## Describes one collectible pickaxe and the modifiers it adds to the run.
## EncounterProgression owns production difficulty; these modifiers preserve
## isolated legacy previews while the newest owned definition controls color.
## Authoring source of truth: res://resources/pickaxes/pickaxe_authoring.md

enum SpecialEffect {
	NONE,
	AFTERSHOCK,
	RAPID_FOLLOW_UP,
	BRANCHING_LIGHTNING,
}

@export_category("Identity")
## Unique ownership key. Use snake_case and normally match the .tres filename.
@export var id: StringName = &"basic_pickaxe"
## Player-facing name; this does not identify the resource in code.
@export var display_name: String = "Basic Pickaxe"
## Player-facing explanation; keep mechanical claims consistent with the
## matching EncounterProgressionLevel rather than these legacy modifiers.
@export_multiline var description: String = "A dependable starting tool."

@export_category("Mining")
## Legacy-preview-only while EncounterProgression is active. Leave at 1.0 for
## production rewards; progression_level_N.tres owns shipped impact behavior.
@export_range(0.1, 5.0, 0.05) var power_multiplier: float = 1.0
## Legacy-preview-only horizontal multiplier. Neutral is 1.0.
@export_range(0.1, 5.0, 0.05) var width_multiplier: float = 1.0
## Legacy-preview-only animation multiplier. Neutral is 1.0.
@export_range(0.1, 5.0, 0.05) var swing_speed_multiplier: float = 1.0
## Legacy-preview-only debris multiplier. Neutral is 1.0.
@export_range(0.0, 5.0, 0.05) var debris_multiplier: float = 1.0
## Toggles whether to use the secondary recovery bar
@export var secondary_recovery : bool = false

@export_category("Special Effect")
## Legacy-preview-only while production EncounterProgression is active.
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
## Caps the number of ground cracks reached at maximum combo.
@export_range(1, 8, 1) var lightning_max_crack_count: int = 4
## Caps each crack's lateral reach at maximum combo.
@export_range(1, 32, 1) var lightning_max_crack_length_cells: int = 18
## Caps the shallow vertical wander that makes each crack irregular.
@export_range(0, 8, 1) var lightning_max_crack_depth_cells: int = 4

@export_category("Appearance")
## The newest granted definition applies this color to the visible tool.
@export var hammer_head_color: Color = Color(0.94, 0.94, 0.94, 1.0)

@export_category("Timing Targets")
## Legacy-preview-only while production EncounterProgression is active. Zero
## reserves these scenes for that preview's starting baseline.
@export_range(0, 100, 1) var target_unlock_combo: int = 0
## Production target pools belong to progression_level_N.tres.
@export var target_scenes: Array[PackedScene] = []
