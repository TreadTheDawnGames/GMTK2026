@tool
class_name DepthCharacterEncounter
extends Resource

## How it works:
## - depth_from_surface places this encounter's mineable tunnel floor.
## - Terrain generation opens the chamber above that floor.
## - Crossing the tunnel ceiling starts the authored conversation and stage.
## - stage_scene optionally adds actor movement, props, and line-driven cues.
## - occurs_at_run_bottom pins the final encounter to any configured run length.
## - The invariant is that large hits cannot skip an encounter threshold.
## @tool because the cutscene editor resolves encounter depth and authored room
## data in editor context; non-tool resources become placeholder instances.

@export var encounter_id: StringName
## Stable story identity; repeated visits reuse the same presenter.
@export var actor_id: StringName
@export_range(1, 1_000_000, 1) var depth_from_surface: int = 1_000
## Gathers the stable cast roster when this depth-authored chamber is entered.
@export var gathers_cast: bool = false
## Resolves this encounter to zero remaining depth for any run length.
@export var occurs_at_run_bottom: bool = false
@export var appearance: CharacterAppearance
@export var conversation: DialogueConversation
## Optional inherited CharacterEncounterStage scene for actor/prop choreography.
@export var stage_scene: PackedScene
## Optional timeline played by the stage during its opening choreography.
@export var sequence: CutsceneSequence
## Used only when story text should remain encrypted in source control.
@export var encrypted_conversation: EncryptedDialogueConversation
@export var speaker_slot: StringName
## Adds this pickaxe to the cumulative stack after dialogue.
@export var pickaxe_reward: PickaxeDefinition
## Requests the canonical persistent coffee speed reward after dialogue.
@export var grants_coffee_speed_boost: bool = false
## Starts bounded rat-colony support after dialogue.
@export var starts_rat_colony_support: bool = false
## Holds this encounter until the non-blocking credits presentation completes.
@export var requires_credits_complete: bool = false
## Opens the chamber through its right wall for authored choreography.
@export var opens_right_exit: bool = false
## Replaces this encounter's procedural chamber with an authored sculpted room.
## Leave it null and terrain generation is unchanged.
@export var terrain_sculpt: CutsceneTerrainSculpt


## Returns the gameplay depth where this character waits.
func resolve_depth(total_run_depth: int) -> int:
	if occurs_at_run_bottom:
		return total_run_depth
	return depth_from_surface
