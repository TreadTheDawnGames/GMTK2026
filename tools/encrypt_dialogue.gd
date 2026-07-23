extends SceneTree

## Writes console-provided dialogue as ciphertext without a plaintext file.


## Parses generic conversation arguments, encrypts them, and saves a resource.
func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
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
	var iv := Crypto.new().generate_random_bytes(DialogueCipher.BLOCK_SIZE)
	var encrypted_text := DialogueCipher.encrypt_text(
		JSON.stringify(payload),
		iv
	)
	if encrypted_text.is_empty():
		quit(1)
		return

	var encrypted_conversation := EncryptedDialogueConversation.new()
	encrypted_conversation.ciphertext_base64 = encrypted_text
	encrypted_conversation.iv_base64 = Marshalls.raw_to_base64(iv)
	var save_error := ResourceSaver.save(
		encrypted_conversation,
		output_path
	)
	if save_error != OK:
		push_error("Could not save encrypted dialogue.")
		quit(1)
		return
	print("Encrypted %d dialogue line(s)." % lines.size())
	print("Saved ciphertext to %s" % output_path)
	quit()


## Shows generic console syntax without supplying any story text.
func _print_usage() -> void:
	print(
		"Usage: godot --headless --path . --script "
		+ "res://tools/encrypt_dialogue.gd -- "
		+ "<res://output.tres> <conversation_id> "
		+ "\"<slot>=<Display Name>\" --lines \"<slot>:<line>\""
	)
