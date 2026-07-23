class_name DialogueConversation
extends Resource

## Stores an Inspector-authored conversation and validates its lines.

@export var conversation_id: StringName
@export var participants: Array[DialogueParticipant] = []
@export var lines: Array[DialogueLine] = []


## Returns all participant and line authoring errors.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if conversation_id.is_empty():
		errors.append("Conversation ID is required.")
	if participants.is_empty():
		errors.append("At least one participant is required.")
	if lines.is_empty():
		errors.append("At least one dialogue line is required.")

	var known_slots: Dictionary = {}
	for participant_index in range(participants.size()):
		var participant := participants[participant_index]
		if participant == null:
			errors.append(
				"Participant %d is empty." % (participant_index + 1)
			)
			continue
		if participant.slot.is_empty():
			errors.append(
				"Participant %d needs a slot." % (participant_index + 1)
			)
			continue
		if known_slots.has(participant.slot):
			errors.append(
				"Participant slot '%s' is duplicated." % participant.slot
			)
			continue
		known_slots[participant.slot] = true
		if participant.display_name.strip_edges().is_empty():
			errors.append(
				"Participant '%s' needs a display name." % participant.slot
			)

	for line_index in range(lines.size()):
		var line := lines[line_index]
		if line == null:
			errors.append("Line %d is empty." % (line_index + 1))
			continue
		if not known_slots.has(line.speaker_slot):
			errors.append(
				"Line %d references unknown speaker slot '%s'."
				% [line_index + 1, line.speaker_slot]
			)
		if line.text.strip_edges().is_empty():
			errors.append("Line %d has no text." % (line_index + 1))
	return errors


## Returns the display name for a speaker slot.
func get_participant_display_name(slot: StringName) -> String:
	for participant in participants:
		if participant != null and participant.slot == slot:
			return participant.display_name
	return str(slot)
