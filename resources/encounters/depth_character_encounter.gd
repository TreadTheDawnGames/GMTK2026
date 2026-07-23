class_name DepthCharacterEncounter
extends Resource

## Defines one named character conversation at an authored run depth.

@export var encounter_id: StringName
@export_range(1, 1_000_000, 1) var depth_from_surface: int = 1_000
## Resolves this encounter to zero remaining depth for any run length.
@export var occurs_at_run_bottom: bool = false
@export var appearance: MerchantAppearance
@export var conversation: DialogueConversation
## Used only when story text should remain encrypted in source control.
@export var encrypted_conversation: EncryptedDialogueConversation
@export var speaker_slot: StringName
## Grants and equips this pickaxe after dialogue when one is assigned.
@export var pickaxe_reward: PickaxeDefinition


## Returns the gameplay depth where this character waits.
func resolve_depth(total_run_depth: int) -> int:
	if occurs_at_run_bottom:
		return total_run_depth
	return depth_from_surface
