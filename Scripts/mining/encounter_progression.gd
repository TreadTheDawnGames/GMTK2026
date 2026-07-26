class_name EncounterProgression
extends Node

## How it works:
## - Level zero is applied when the scene starts and whenever the run resets.
## - Completing encounter N applies level N + 1 when that level exists.
## - Mining and timing receive the same complete authored level atomically.
## - Levels unlock combo groups; combo selects within the unlocked range.
## - Encounter ten has no level entry, so it intentionally changes nothing.
## - The invariant is that both consumers always reference the same level.

signal level_changed(
	level_index: int,
	definition: EncounterProgressionLevel
)

@export var config: MiningConfig
@export var mining_controller: MiningController
@export var timing_window: TimingWindowTask

var current_level_index: int = -1


## Validates the authored table and starts the run at level zero.
func _ready() -> void:
	if (
		config == null
		or mining_controller == null
		or timing_window == null
	):
		push_error("EncounterProgression references are incomplete.")
		return
	if config.progression_levels.size() != 10:
		push_error("Encounter progression requires levels zero through nine.")
		return
	if not config.has_valid_combo_target_groups():
		push_error("MiningConfig combo target groups are incomplete.")
		return
	for level_index in range(config.progression_levels.size()):
		var definition := config.progression_levels[level_index]
		if (
			definition == null
			or not definition.is_valid()
			or definition.highest_unlocked_combo_target_group_index
				>= config.combo_target_groups.size()
		):
			push_error(
				"Encounter progression level %d is incomplete."
				% level_index
			)
			return
	# The HUD is authored after Systems in the scene, so its @onready timing
	# references finish binding later in this same tree-entry pass.
	apply_level.call_deferred(0)


## Advances after one completed story encounter when a next level is authored.
func _on_encounter_completed(encounter_index: int) -> void:
	var requested_level := encounter_index + 1
	if requested_level >= config.progression_levels.size():
		return
	apply_level(requested_level)


## Restores the complete starting rules for a fresh run.
func _on_run_reset() -> void:
	apply_level(0)


## Replaces both gameplay consumers with one self-contained authored level.
## Add new production pickaxe-era rules here as explicit typed handoffs; never
## make a consumer search PickaxeProgression or the scene tree for current state.
func apply_level(level_index: int) -> bool:
	if (
		config == null
		or level_index < 0
		or level_index >= config.progression_levels.size()
	):
		return false
	var definition := config.progression_levels[level_index]
	if (
		definition == null
		or not definition.is_valid()
		or definition.highest_unlocked_combo_target_group_index
			>= config.combo_target_groups.size()
	):
		return false
	current_level_index = level_index
	mining_controller.set_progression_level(definition)
	timing_window.set_progression_target_rules(
		definition.slider_speed,
		definition.starting_target_count,
		definition.bonus_target_combos,
		definition.highest_unlocked_combo_target_group_index
	)
	level_changed.emit(level_index, definition)
	return true
