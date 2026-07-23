class_name PickaxeGiftEncounter
extends Resource

## Pairs one depth conversation with the pickaxe granted when it finishes.

@export var conversation: DialogueConversation
@export var pickaxe: PickaxeDefinition


## Reports authoring errors that would prevent this gift from completing.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if conversation == null:
		errors.append("A conversation is required.")
	else:
		errors.append_array(conversation.validate())
	if pickaxe == null:
		errors.append("A pickaxe is required.")
	elif pickaxe.id.is_empty():
		errors.append("The pickaxe needs a non-empty id.")
	return errors
