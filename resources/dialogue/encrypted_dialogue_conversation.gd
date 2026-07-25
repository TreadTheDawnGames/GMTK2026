class_name EncryptedDialogueConversation
extends Resource

## Stores a conversation without keeping its story text readable in the repo.

@export_multiline var ciphertext_base64: String
@export var iv_base64: String


## Reports whether encrypted story data has been authored.
func has_payload() -> bool:
	return (
		not ciphertext_base64.is_empty()
		and not iv_base64.is_empty()
	)


## Builds the normal dialogue resource consumed by DialogueDirector.
func decrypt_conversation() -> DialogueConversation:
	if not has_payload():
		return null
	var plain_json := DialogueCipher.decrypt_text(
		ciphertext_base64,
		iv_base64
	)
	if plain_json.is_empty():
		return null
	var payload = JSON.parse_string(plain_json)
	if payload is not Dictionary:
		push_error("Encrypted dialogue did not contain an object.")
		return null

	var conversation := DialogueConversation.new()
	conversation.conversation_id = StringName(
		str(payload.get("conversation_id", ""))
	)
	for participant_data in payload.get("participants", []):
		if participant_data is not Dictionary:
			continue
		var participant := DialogueParticipant.new()
		participant.slot = StringName(
			str(participant_data.get("slot", ""))
		)
		participant.display_name = str(
			participant_data.get("display_name", "")
		)
		conversation.participants.append(participant)
	for line_data in payload.get("lines", []):
		if line_data is not Dictionary:
			continue
		var line := DialogueLine.new()
		line.speaker_slot = StringName(
			str(line_data.get("speaker_slot", ""))
		)
		line.text = str(line_data.get("text", ""))
		line.auto_advance_delay_seconds = float(
			line_data.get("auto_advance_delay_seconds", 0.0)
		)
		conversation.lines.append(line)

	if not conversation.validate().is_empty():
		push_error("Decrypted dialogue is incomplete.")
		return null
	return conversation
