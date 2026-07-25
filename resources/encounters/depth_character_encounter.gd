class_name DepthCharacterEncounter
extends Resource

## How it works:
## - depth_from_surface places this encounter's mineable tunnel floor.
## - Terrain generation opens the chamber above that floor.
## - Landing in the opened tunnel starts the authored conversation and stage.
## - stage_scene optionally adds actor movement, props, and line-driven cues.
## - occurs_at_run_bottom pins the final encounter to any configured run length.
## - The invariant is that encounter order follows strictly increasing depth.

@export var encounter_id: StringName
## Stable story identity; repeated visits reuse the same presenter.
@export var actor_id: StringName
@export_range(1, 1_000_000, 1) var depth_from_surface: int = 1_000
## Gathers the stable cast roster when this depth-authored chamber is entered.
@export var is_farewell: bool = false
## Resolves this encounter to zero remaining depth for any run length.
@export var occurs_at_run_bottom: bool = false
@export var appearance: CharacterAppearance
@export var conversation: DialogueConversation
## Optional inherited CharacterEncounterStage scene for actor/prop choreography.
@export var stage_scene: PackedScene
## Used only when story text should remain encrypted in source control.
@export var encrypted_conversation: EncryptedDialogueConversation
@export var speaker_slot: StringName
## Adds this pickaxe to the cumulative stack after dialogue.
@export var pickaxe_reward: PickaxeDefinition
## Opens the chamber through its right wall for an authored departure.
@export var opens_right_exit: bool = false


## Returns the gameplay depth where this character waits.
func resolve_depth(total_run_depth: int) -> int:
	if occurs_at_run_bottom:
		return total_run_depth
	return depth_from_surface
