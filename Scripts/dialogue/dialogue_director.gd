class_name DialogueDirector
extends CanvasLayer

## Presents and advances one conversation through the in-universe dialogue box.

const CinematicFrameType = preload(
	"res://Scripts/dialogue/cinematic_frame.gd"
)
signal conversation_started(conversation_id: StringName)
signal line_presented(
	conversation_id: StringName,
	line_index: int,
	speaker_slot: StringName,
	speaker_pose: StringName
)
signal conversation_finished(conversation_id: StringName)
signal cinematic_frame_opened
signal cinematic_frame_closed

@export_category("Behavior")
@export var pause_gameplay: bool = true
@export var auto_frame_conversations: bool = true

@export_category("References")
@export var dialogue_root: Control
@export var bottom_panel: Control
@export var speaker_label: Label
@export var body_label: RichTextLabel
@export var continue_label: Label
@export var cinematic_frame: CinematicFrameType

@export_category("Typewriter")
@export_range(0.001, 0.2, 0.001) var character_display_speed: float = 0.03
@export var characters_for_slowest_time: Array[String] = ["."]
@export var characters_for_slower: Array[String] = [","]

var _active_conversation: DialogueConversation
var _current_line_index: int = -1
var _presentation_token: int = 0
var _tree_was_paused: bool = false
var _keep_frame_open_after_conversation: bool = false
var _references_valid: bool = false
var _advance_input_enabled: bool = true


## Starts hidden and owns the internal presentation signal connections.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_references_valid = _validate_references()
	if not _references_valid:
		push_error("DialogueDirector references are incomplete.")
		return
	dialogue_root.hide()
	# CinematicFrame owns its own opening state so a scene handed over from a
	# faded-to-black menu can start fully covered.
	_connect_once(
		cinematic_frame.frame_opened,
		_on_cinematic_frame_opened
	)
	_connect_once(
		cinematic_frame.frame_closed,
		_on_cinematic_frame_closed
	)


## Advances active dialogue from keyboard or mouse input.
func _unhandled_input(event: InputEvent) -> void:
	var is_continue_press := event.is_action_pressed(&"ui_accept")
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		is_continue_press = (
			mouse_event.button_index == MOUSE_BUTTON_LEFT
			and mouse_event.pressed
		)
	if (
		not is_conversation_active()
		or not _advance_input_enabled
		or not is_continue_press
		or event.is_echo()
	):
		return
	get_viewport().set_input_as_handled()
	if _get_visible_character_count() >= _get_current_text_length():
		advance()
	else:
		_set_visible_character_count(_get_current_text_length())


## Validates and starts a conversation. Returns whether it started.
## The optional hold keeps the frame open for a linked action or conversation.
func start_conversation(
	conversation: DialogueConversation,
	keep_frame_open_after_finish: bool = false
) -> bool:
	if (
		not _references_valid
		or conversation == null
		or is_conversation_active()
	):
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
	_advance_input_enabled = true
	_keep_frame_open_after_conversation = keep_frame_open_after_finish
	dialogue_root.show()
	if auto_frame_conversations:
		open_cinematic_frame()
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
	var keep_frame_open := _keep_frame_open_after_conversation
	_presentation_token += 1
	_active_conversation = null
	_current_line_index = -1
	_advance_input_enabled = true
	_keep_frame_open_after_conversation = false
	dialogue_root.hide()
	if auto_frame_conversations and not keep_frame_open:
		close_cinematic_frame()
	if pause_gameplay:
		get_tree().paused = _tree_was_paused
	conversation_finished.emit(finished_id)


## Returns whether a conversation is playing.
func is_conversation_active() -> bool:
	return _active_conversation != null


## Leaves the current line visible but hands Space back to live gameplay.
## The final Thief beat uses this to turn dialogue into a real mining target.
func begin_gameplay_handoff() -> bool:
	if not is_conversation_active():
		return false
	_advance_input_enabled = false
	if pause_gameplay:
		get_tree().paused = _tree_was_paused
	return true


## Slides the authored letterbox bars into view.
func open_cinematic_frame(instant: bool = false) -> void:
	if cinematic_frame != null:
		cinematic_frame.open_frame(instant)


## Slides the authored letterbox bars out of view.
func close_cinematic_frame(instant: bool = false) -> void:
	if cinematic_frame != null:
		cinematic_frame.close_frame(instant)


## Splits an opening blackout apart into the authored letterbox.
func reveal_cinematic_frame_from_blackout(instant: bool = false) -> void:
	if cinematic_frame != null:
		cinematic_frame.reveal_from_blackout(instant)


## Suspends until an opening blackout has finished splitting apart.
func wait_until_blackout_revealed() -> void:
	if cinematic_frame == null:
		return
	await cinematic_frame.wait_until_blackout_revealed()


## Suspends until framing has finished, or returns immediately if already open.
func wait_until_frame_open() -> void:
	await _wait_until_frame_state(true)


## Suspends until framing has cleared, or returns immediately if already closed.
func wait_until_frame_closed() -> void:
	await _wait_until_frame_state(false)


## Suspends until the letterbox has reached the requested state.
##
## This watches the frame's own state instead of awaiting its finished signal,
## because that signal is an edge and the caller is waiting on a condition.
##
## The bars announce arrival from a tween callback, and anything that kills that
## tween takes the announcement with it: a second open_frame, a close_frame, or
## apply_blackout, which sets the bars fully covered and emits nothing at all.
## Miss the edge and the awaiting coroutine is stranded for the rest of the run
## while the bars sit there looking perfectly open. That stranded an encounter
## before it could take its actor, so the letterbox opened over a cutscene that
## then never started, with the HUD already gated off behind it.
##
## Polling per frame is cheap next to that: this runs once per cutscene
## transition, not per frame of one.
func _wait_until_frame_state(wants_open: bool) -> void:
	if cinematic_frame == null:
		return
	while is_instance_valid(cinematic_frame) and (
		cinematic_frame.is_open() if wants_open else cinematic_frame.is_closed()
	) == false:
		await get_tree().process_frame


## Reveals one more character if this line is still current.
func _show_next_character(token: int) -> void:
	if not is_conversation_active() or token != _presentation_token:
		return
	var visible_count := _get_visible_character_count()
	var text_length := _get_current_text_length()
	if visible_count >= text_length:
		return
	visible_count += 1
	_set_visible_character_count(visible_count)
	var current_text := body_label.text
	var delay := character_delay(current_text[visible_count - 1])
	await get_tree().create_timer(delay, true).timeout
	_show_next_character(token)


## Returns the typewriter delay for a revealed character.
##
## The base speed comes from the line being presented when that line overrides
## it, so a line authored to land slowly keeps its pace here rather than only in
## the editor's estimate of it.
func character_delay(letter: String) -> float:
	var display_speed := _get_active_character_display_speed()
	if letter.length() > 1:
		return display_speed
	if characters_for_slowest_time.has(letter):
		display_speed *= 5.0
	elif characters_for_slower.has(letter):
		display_speed *= 3.0
	return display_speed


## Returns the per-character speed in force right now: the current line's
## override, or this director's own speed when the line does not set one.
func _get_active_character_display_speed() -> float:
	if (
		_active_conversation == null
		or _current_line_index < 0
		or _current_line_index >= _active_conversation.lines.size()
	):
		return character_display_speed
	var line := _active_conversation.lines[_current_line_index]
	if line == null or line.character_display_speed_override <= 0.0:
		return character_display_speed
	return line.character_display_speed_override


## Displays the current speaker and line through the bottom dialogue box.
func _present_current_line() -> void:
	var line := _active_conversation.lines[_current_line_index]
	var display_name := (
		_active_conversation.get_participant_display_name(line.speaker_slot)
	)
	var continue_text := (
		"Continuing..."
		if line.auto_advance_delay_seconds > 0.0
		else "Space / Enter / Left Click"
	)
	speaker_label.text = display_name
	body_label.text = line.text
	continue_label.text = continue_text
	_set_visible_character_count(0)
	_show_next_character(_presentation_token)

	line_presented.emit(
		_active_conversation.conversation_id,
		_current_line_index,
		line.speaker_slot,
		line.speaker_pose
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


func _set_visible_character_count(value: int) -> void:
	body_label.visible_characters = value


func _get_visible_character_count() -> int:
	return body_label.visible_characters


func _get_current_text_length() -> int:
	return body_label.text.length()


func _connect_once(source_signal: Signal, callback: Callable) -> void:
	if not source_signal.is_connected(callback):
		source_signal.connect(callback)


func _validate_references() -> bool:
	return (
		dialogue_root != null
		and bottom_panel != null
		and speaker_label != null
		and body_label != null
		and continue_label != null
		and cinematic_frame != null
	)


func _on_cinematic_frame_opened() -> void:
	cinematic_frame_opened.emit()


func _on_cinematic_frame_closed() -> void:
	cinematic_frame_closed.emit()
