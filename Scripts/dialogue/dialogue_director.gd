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
@export var textbox_art: TextureRect
@export var fallback_panel: Control
@export var dialogue_margin: MarginContainer
@export var speaker_label: Label
@export var body_label: RichTextLabel
@export var cinematic_frame: CinematicFrameType

@export_category("Textbox Art")
@export var mr_sitts_textbox_texture: Texture2D
@export var quibble_textbox_texture: Texture2D
@export var rotini_textbox_texture: Texture2D
@export var sparky_textbox_texture: Texture2D
@export var zeb_textbox_texture: Texture2D
@export var ayden_textbox_texture: Texture2D
@export var coco_textbox_texture: Texture2D
@export var art_margin_left: int = 147
@export var art_margin_top: int = 44
@export var art_margin_right: int = 16
@export var art_margin_bottom: int = 34
@export var art_body_minimum_height: float = 64.0
@export var art_body_font_size: int = 14
@export var fallback_panel_horizontal_margin: float = 90.0
@export var fallback_margin_left: int = 22
@export var fallback_margin_top: int = 16
@export var fallback_margin_right: int = 22
@export var fallback_margin_bottom: int = 14
@export var fallback_body_minimum_height: float = 72.0
@export var fallback_body_font_size: int = 20

@export_category("Typewriter")
@export_range(0.001, 0.2, 0.001) var character_display_speed: float = 0.03
@export var characters_for_slowest_time: Array[String] = ["."]
@export var characters_for_slower: Array[String] = [","]

# The lifetime record, resolved once, so a line can name the player's own totals.
#
# It is looked up by node path rather than by the PlayerHistory identifier
# because that identifier does not exist at compile time: the autoload's script
# carries a class_name, and GDScript does not also publish a global variable for
# an autoload whose script is already a global class.
#
# Null is a supported state. The cutscene preview and the headless checks run
# without the autoload, and a line with no tokens in it - which is every line in
# the game except the finale's - does not care either way.
const _PLAYER_HISTORY_PATH: NodePath = ^"/root/PlayerHistory"

var _player_history: PlayerHistoryRecord
var _active_conversation: DialogueConversation
var _current_line_index: int = -1
## Inclusive final line for the active presentation. Whole conversations set
## this to their last line; timeline dialogue beats may select a smaller range.
var _active_last_line_index: int = -1
var _presentation_token: int = 0
var _tree_was_paused: bool = false
var _keep_frame_open_after_conversation: bool = false
var _references_valid: bool = false
var _advance_input_enabled: bool = true
var _current_line_word_count: int = 0


## Starts hidden and owns the internal presentation signal connections.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player_history = get_node_or_null(
		_PLAYER_HISTORY_PATH
	) as PlayerHistoryRecord
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
## An inclusive line range lets a timeline place parts of one conversation
## around animation beats; (-1, -1) preserves whole-conversation playback.
func start_conversation(
	conversation: DialogueConversation,
	keep_frame_open_after_finish: bool = false,
	line_range: Vector2i = Vector2i(-1, -1)
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

	var first_line := 0
	var last_line := conversation.lines.size() - 1
	if line_range != Vector2i(-1, -1):
		if (
			line_range.x < 0
			or line_range.y < line_range.x
			or line_range.y >= conversation.lines.size()
		):
			push_error(
				"Dialogue '%s' requested invalid inclusive line range %s."
				% [conversation.conversation_id, line_range]
			)
			return false
		first_line = line_range.x
		last_line = line_range.y

	_active_conversation = conversation
	_current_line_index = first_line
	_active_last_line_index = last_line
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
	if _current_line_index > _active_last_line_index:
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
	_active_last_line_index = -1
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
	var revealed_character := current_text[visible_count - 1]
	var next_character := (
		current_text[visible_count]
		if visible_count < current_text.length()
		else ""
	)
	var revealed_word_end := (
		not [" ", "\n", "\t"].has(revealed_character)
		and (
			next_character.is_empty()
			or [" ", "\n", "\t"].has(next_character)
		)
	)
	if revealed_word_end:
		_current_line_word_count += 1
		var line := _active_conversation.lines[_current_line_index]
		if line.typing_pause_after_word_counts.has(
			_current_line_word_count
		):
			delay += line.typing_pause_seconds
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
	var textbox_texture: Texture2D = null
	match line.speaker_slot:
		&"miner":
			textbox_texture = sparky_textbox_texture
		&"treasure_hunter":
			textbox_texture = zeb_textbox_texture
		&"rutini":
			textbox_texture = rotini_textbox_texture
		&"coffee_cat":
			textbox_texture = quibble_textbox_texture
		&"cheese_girl":
			textbox_texture = coco_textbox_texture
		&"moody_teen":
			textbox_texture = ayden_textbox_texture
		&"mr_sitts", &"newspaper_reader":
			textbox_texture = mr_sitts_textbox_texture
	var uses_authored_textbox := textbox_texture != null
	textbox_art.texture = textbox_texture
	textbox_art.visible = uses_authored_textbox
	fallback_panel.visible = not uses_authored_textbox
	speaker_label.visible = not uses_authored_textbox
	if uses_authored_textbox:
		var texture_size := textbox_texture.get_size()
		if texture_size.y > 0.0:
			var art_width := (
				bottom_panel.size.y * texture_size.x / texture_size.y
			)
			var art_horizontal_margin := maxf(
				(dialogue_root.size.x - art_width) * 0.5,
				0.0
			)
			bottom_panel.offset_left = art_horizontal_margin
			bottom_panel.offset_right = -art_horizontal_margin
	else:
		bottom_panel.offset_left = fallback_panel_horizontal_margin
		bottom_panel.offset_right = -fallback_panel_horizontal_margin
	dialogue_margin.add_theme_constant_override(
		"margin_left",
		art_margin_left if uses_authored_textbox else fallback_margin_left
	)
	dialogue_margin.add_theme_constant_override(
		"margin_top",
		art_margin_top if uses_authored_textbox else fallback_margin_top
	)
	dialogue_margin.add_theme_constant_override(
		"margin_right",
		art_margin_right if uses_authored_textbox else fallback_margin_right
	)
	dialogue_margin.add_theme_constant_override(
		"margin_bottom",
		art_margin_bottom if uses_authored_textbox else fallback_margin_bottom
	)
	body_label.custom_minimum_size.y = (
		art_body_minimum_height
		if uses_authored_textbox
		else fallback_body_minimum_height
	)
	body_label.add_theme_font_size_override(
		"normal_font_size",
		art_body_font_size
		if uses_authored_textbox
		else fallback_body_font_size
	)
	speaker_label.text = display_name
	# Resolved here, at the last possible moment, because a line that names the
	# player's own hours has to be read when it is shown rather than when the
	# conversation was built. Every reader downstream - the typewriter, its
	# punctuation delays, the length check - already works from the label, so
	# they all see the resolved text without knowing this happened.
	body_label.text = DialogueTokens.resolve(line.text, _player_history)
	_current_line_word_count = 0
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
		and textbox_art != null
		and fallback_panel != null
		and dialogue_margin != null
		and speaker_label != null
		and body_label != null
		and cinematic_frame != null
	)


func _on_cinematic_frame_opened() -> void:
	cinematic_frame_opened.emit()


func _on_cinematic_frame_closed() -> void:
	cinematic_frame_closed.emit()
