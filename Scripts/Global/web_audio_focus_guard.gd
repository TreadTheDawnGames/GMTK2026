extends Node

## How it works:
## - Browser hide, blur, and page-lifecycle events suspend gameplay and audio.
## - Startup and return both wait for a real input gesture before resuming.
## - This satisfies browser autoplay rules before any game clock can advance.
## - Weak references resume only the 1D, 2D, and 3D players paused here.
## - The invariant is that gameplay and audible time resume on the same input.

# Growth is bounded by the active AudioStreamPlayer nodes in the scene tree at
# the instant the page hides. The array is cleared on every visible transition.
var _paused_players: Array[WeakRef] = []
var _document: JavaScriptObject
var _window: JavaScriptObject
var _page_state_callback: JavaScriptObject
var _is_background_paused: bool = false
var _is_page_hidden: bool = false
var _window_has_focus: bool = true
var _awaiting_resume_gesture: bool = false
var _owns_tree_pause: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		return
	_document = JavaScriptBridge.get_interface("document")
	_window = JavaScriptBridge.get_interface("window")
	if _document == null or _window == null:
		push_warning("WebAudioFocusGuard could not observe page visibility.")
		return
	_page_state_callback = JavaScriptBridge.create_callback(
		_on_web_page_state_changed
	)
	_document.addEventListener("visibilitychange", _page_state_callback)
	_window.addEventListener("blur", _page_state_callback)
	_window.addEventListener("focus", _page_state_callback)
	_window.addEventListener("pagehide", _page_state_callback)
	_window.addEventListener("pageshow", _page_state_callback)
	_is_page_hidden = bool(_document.hidden)
	_window_has_focus = bool(_document.hasFocus())
	# Even a visible page begins under browser autoplay policy. Holding gameplay
	# until its first gesture makes the conductor and the game start together.
	_suspend_for_background()
	_awaiting_resume_gesture = (
		not _is_page_hidden and _window_has_focus
	)


func _exit_tree() -> void:
	if _document != null and _page_state_callback != null:
		_document.removeEventListener(
			"visibilitychange",
			_page_state_callback
		)
	if _window != null and _page_state_callback != null:
		_window.removeEventListener("blur", _page_state_callback)
		_window.removeEventListener("focus", _page_state_callback)
		_window.removeEventListener("pagehide", _page_state_callback)
		_window.removeEventListener("pageshow", _page_state_callback)
	_page_state_callback = null
	_document = null
	_window = null


func _input(event: InputEvent) -> void:
	if (
		not _awaiting_resume_gesture
		or _is_page_hidden
		or not _window_has_focus
	):
		return
	var is_resume_gesture: bool = false
	if event is InputEventKey:
		var key_event := event as InputEventKey
		is_resume_gesture = key_event.pressed and not key_event.echo
	elif event is InputEventMouseButton:
		is_resume_gesture = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		is_resume_gesture = (event as InputEventScreenTouch).pressed
	elif event is InputEventJoypadButton:
		is_resume_gesture = (event as InputEventJoypadButton).pressed
	if is_resume_gesture:
		_resume_after_gesture()


func _on_web_page_state_changed(arguments: Array) -> void:
	if _document == null or arguments.is_empty():
		return
	var event: JavaScriptObject = arguments[0]
	var event_type := String(event.type)
	match event_type:
		"visibilitychange":
			_is_page_hidden = bool(_document.hidden)
		"blur":
			_window_has_focus = false
		"focus":
			_window_has_focus = true
		"pagehide":
			_is_page_hidden = true
		"pageshow":
			_is_page_hidden = bool(_document.hidden)
			_window_has_focus = bool(_document.hasFocus())
	if _is_page_hidden or not _window_has_focus:
		_awaiting_resume_gesture = false
		_suspend_for_background()
	else:
		# Some browsers leave Web Audio suspended after returning. The next
		# canvas gesture is the only cross-browser-safe point to resume it.
		_awaiting_resume_gesture = true


## Freezes gameplay and every live player under one ownership decision.
func _suspend_for_background() -> void:
	if _is_background_paused:
		return
	_is_background_paused = true
	if not get_tree().paused:
		get_tree().paused = true
		_owns_tree_pause = true
	_pause_active_players()


## Resumes inside the user gesture browsers require for Web Audio activation.
func _resume_after_gesture() -> void:
	if not _is_background_paused:
		return
	_resume_guarded_players()
	if _owns_tree_pause:
		get_tree().paused = false
	_owns_tree_pause = false
	_is_background_paused = false
	_awaiting_resume_gesture = false


## Traverses once per page hide; no tree scan runs per frame or per audio event.
func _pause_active_players() -> void:
	_paused_players.clear()
	var pending_nodes: Array[Node] = [get_tree().root]
	while not pending_nodes.is_empty():
		var node: Node = pending_nodes.pop_back()
		for child: Node in node.get_children():
			pending_nodes.append(child)
		if _has_active_unpaused_playback(node):
			_set_player_paused(node, true)
			_paused_players.append(weakref(node))


func _resume_guarded_players() -> void:
	for player_reference: WeakRef in _paused_players:
		var player := player_reference.get_ref() as Node
		if is_instance_valid(player):
			_set_player_paused(player, false)
	_paused_players.clear()


func _has_active_unpaused_playback(player: Node) -> bool:
	if player is AudioStreamPlayer:
		var plain_player := player as AudioStreamPlayer
		return plain_player.playing and not plain_player.stream_paused
	if player is AudioStreamPlayer2D:
		var player_2d := player as AudioStreamPlayer2D
		return player_2d.playing and not player_2d.stream_paused
	if player is AudioStreamPlayer3D:
		var player_3d := player as AudioStreamPlayer3D
		return player_3d.playing and not player_3d.stream_paused
	return false


func _set_player_paused(player: Node, is_paused: bool) -> void:
	if player is AudioStreamPlayer:
		(player as AudioStreamPlayer).stream_paused = is_paused
	elif player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).stream_paused = is_paused
	elif player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).stream_paused = is_paused
