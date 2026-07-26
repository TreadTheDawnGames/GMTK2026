extends SceneTree

## Writes console-provided dialogue as ciphertext without a plaintext file.


## Parses generic conversation arguments, encrypts them, and saves a resource.
func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() >= 1 and arguments[0] == "--payload":
		_encrypt_payload_file(arguments)
		return
	var lines_separator := arguments.find("--lines")
	if arguments.size() < 5 or lines_separator < 3:
		_print_usage()
		quit(1)
		return

	var output_path := arguments[0]
	var conversation_id := arguments[1].strip_edges()
	if (
		not output_path.begins_with("res://")
		or not output_path.ends_with(".tres")
		or conversation_id.is_empty()
	):
		push_error("Output must be a res:// .tres path and ID cannot be empty.")
		quit(1)
		return

	var participants: Array[Dictionary] = []
	var known_slots: Dictionary[String, bool] = {}
	for argument_index in range(2, lines_separator):
		var participant_argument := arguments[argument_index]
		var separator_index := participant_argument.find("=")
		if separator_index <= 0:
			push_error("Participants must use slot=Display Name.")
			quit(1)
			return
		var slot := participant_argument.left(separator_index).strip_edges()
		var display_name := participant_argument.substr(
			separator_index + 1
		).strip_edges()
		if (
			slot.is_empty()
			or display_name.is_empty()
			or known_slots.has(slot)
		):
			push_error("Participant slots and names must be unique and nonempty.")
			quit(1)
			return
		known_slots[slot] = true
		participants.append({
			"slot": slot,
			"display_name": display_name,
		})

	var lines: Array[Dictionary] = []
	for argument_index in range(lines_separator + 1, arguments.size()):
		var line_argument := arguments[argument_index]
		var separator_index := line_argument.find(":")
		if separator_index <= 0:
			push_error("Dialogue lines must use slot:Text.")
			quit(1)
			return
		var speaker_slot := line_argument.left(
			separator_index
		).strip_edges()
		var text := line_argument.substr(separator_index + 1).strip_edges()
		if not known_slots.has(speaker_slot) or text.is_empty():
			push_error("Each line needs a known speaker slot and nonempty text.")
			quit(1)
			return
		lines.append({
			"speaker_slot": speaker_slot,
			"text": text,
			"auto_advance_delay_seconds": 0.0,
		})
	if lines.is_empty():
		push_error("At least one dialogue line is required.")
		quit(1)
		return

	var payload := {
		"conversation_id": conversation_id,
		"participants": participants,
		"lines": lines,
	}
	if not _save_encrypted(payload, output_path):
		quit(1)
		return
	print("Encrypted %d dialogue line(s)." % lines.size())
	print("Saved ciphertext to %s" % output_path)
	quit()


## Encrypts a conversation read from a JSON file outside the repository.
##
## The argument form above cannot carry the punctuation the game actually uses -
## curly quotes and apostrophes do not survive a shell reliably - and a long
## conversation is unreadable as one command line anyway. This takes the same
## payload from a file instead, which is expected to live outside `Source\` and
## to be deleted afterwards, so the plaintext still never enters the repository.
func _encrypt_payload_file(arguments: PackedStringArray) -> void:
	if arguments.size() != 3:
		_print_usage()
		quit(1)
		return
	var payload_path := arguments[1]
	var output_path := arguments[2]
	if not output_path.begins_with("res://") or not output_path.ends_with(".tres"):
		push_error("Output must be a res:// .tres path.")
		quit(1)
		return
	if not FileAccess.file_exists(payload_path):
		push_error("No payload file at %s." % payload_path)
		quit(1)
		return
	var payload_text := FileAccess.get_file_as_string(payload_path)
	var payload = JSON.parse_string(payload_text)
	if payload is not Dictionary:
		push_error("Payload must be a JSON object.")
		quit(1)
		return
	var conversation_id := str(payload.get("conversation_id", "")).strip_edges()
	var participants = payload.get("participants", [])
	var lines = payload.get("lines", [])
	if (
		conversation_id.is_empty()
		or participants is not Array
		or lines is not Array
		or participants.is_empty()
		or lines.is_empty()
	):
		push_error("Payload needs an id, participants, and lines.")
		quit(1)
		return
	var known_slots: Dictionary[String, bool] = {}
	for participant in participants:
		if participant is not Dictionary:
			push_error("Each participant must be an object.")
			quit(1)
			return
		var slot := str(participant.get("slot", "")).strip_edges()
		var display_name := str(participant.get("display_name", "")).strip_edges()
		if slot.is_empty() or display_name.is_empty() or known_slots.has(slot):
			push_error("Participant slots and names must be unique and nonempty.")
			quit(1)
			return
		known_slots[slot] = true
	for line in lines:
		if line is not Dictionary:
			push_error("Each line must be an object.")
			quit(1)
			return
		var speaker_slot := str(line.get("speaker_slot", "")).strip_edges()
		if not known_slots.has(speaker_slot):
			push_error("Line speaker '%s' is not a participant." % speaker_slot)
			quit(1)
			return
		if str(line.get("text", "")).strip_edges().is_empty():
			push_error("Every line needs nonempty text.")
			quit(1)
			return
	if not _save_encrypted(payload, output_path):
		quit(1)
		return
	print("Encrypted %d dialogue line(s)." % lines.size())
	print("Saved ciphertext to %s" % output_path)
	quit()


## Encrypts one payload dictionary and writes the resource.
func _save_encrypted(payload: Dictionary, output_path: String) -> bool:
	var iv := Crypto.new().generate_random_bytes(DialogueCipher.BLOCK_SIZE)
	var encrypted_text := DialogueCipher.encrypt_text(
		JSON.stringify(payload),
		iv
	)
	if encrypted_text.is_empty():
		return false
	var encrypted_conversation := EncryptedDialogueConversation.new()
	encrypted_conversation.ciphertext_base64 = encrypted_text
	encrypted_conversation.iv_base64 = Marshalls.raw_to_base64(iv)
	if ResourceSaver.save(encrypted_conversation, output_path) != OK:
		push_error("Could not save encrypted dialogue.")
		return false
	return true


## Shows generic console syntax without supplying any story text.
func _print_usage() -> void:
	print(
		"Usage: godot --headless --path . --script "
		+ "res://tools/encrypt_dialogue.gd -- "
		+ "<res://output.tres> <conversation_id> "
		+ "\"<slot>=<Display Name>\" --lines \"<slot>:<line>\""
	)
	print(
		"   or: godot --headless --path . --script "
		+ "res://tools/encrypt_dialogue.gd -- "
		+ "--payload <payload.json outside the repo> <res://output.tres>"
	)
