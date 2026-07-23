class_name DialogueDirector
extends CanvasLayer

## Displays and advances one conversation at a time.

signal conversation_started(conversation_id: StringName)
signal line_presented(
	conversation_id: StringName,
	line_index: int,
	speaker_slot: StringName
)
signal conversation_finished(conversation_id: StringName)

@export var pause_gameplay: bool = true
@export var dialogue_root: Control
@export var speaker_label: Label
@export var body_label: RichTextLabel
@export var continue_label: Label

var _active_conversation: DialogueConversation
var _current_line_index: int = -1
var _presentation_token: int = 0
var _tree_was_paused: bool = false


## Hides the dialogue box when the scene loads.
func _ready() -> void:
	dialogue_root.hide()


## Advances dialogue when the player presses Space or Enter.
func _unhandled_input(event: InputEvent) -> void:
	if (
		not is_conversation_active()
		or not event.is_action_pressed(&"ui_accept")
		or event.is_echo()
	):
		return
	get_viewport().set_input_as_handled()
	advance()


## Validates and starts a conversation. Returns whether it started.
func start_conversation(conversation: DialogueConversation) -> bool:
	if conversation == null or is_conversation_active():
		return false

	var validation_errors := conversation.validate()
	if not validation_errors.is_empty():
		push_error(
			"Dialogue '%s' is invalid:\n- %s"
			% [conversation.conversation_id, "\n- ".join(validation_errors)]
		)
		return false

	_active_conversation = conversation
	_current_line_index = 0
	_presentation_token += 1
	_tree_was_paused = get_tree().paused
	dialogue_root.show()
	if pause_gameplay:
		get_tree().paused = true
	conversation_started.emit(conversation.conversation_id)
	_present_current_line()
	return true


## Shows the next line or finishes after the final line.
func advance() -> void:
	if not is_conversation_active():
		return
	_current_line_index += 1
	_presentation_token += 1
	if _current_line_index >= _active_conversation.lines.size():
		finish_conversation()
		return
	_present_current_line()


## Closes dialogue and resumes the previous pause state.
func finish_conversation() -> void:
	if not is_conversation_active():
		return
	var finished_id := _active_conversation.conversation_id
	_presentation_token += 1
	_active_conversation = null
	_current_line_index = -1
	dialogue_root.hide()
	if pause_gameplay:
		get_tree().paused = _tree_was_paused
	conversation_finished.emit(finished_id)


## Returns whether a conversation is playing.
func is_conversation_active() -> bool:
	return _active_conversation != null


## Displays the current speaker and line.
func _present_current_line() -> void:
	var line := _active_conversation.lines[_current_line_index]
	speaker_label.text = (
		_active_conversation.get_participant_display_name(line.speaker_slot)
	)
	body_label.text = line.text
	continue_label.text = (
		"Continuing..."
		if line.auto_advance_delay_seconds > 0.0
		else "Space / Enter"
	)
	line_presented.emit(
		_active_conversation.conversation_id,
		_current_line_index,
		line.speaker_slot
	)
	if line.auto_advance_delay_seconds > 0.0:
		_auto_advance_after_delay(
			line.auto_advance_delay_seconds,
			_presentation_token
		)


## Advances after a delay unless the line already changed.
func _auto_advance_after_delay(delay_seconds: float, token: int) -> void:
	await get_tree().create_timer(delay_seconds, true).timeout
	if is_conversation_active() and token == _presentation_token:
		advance()
