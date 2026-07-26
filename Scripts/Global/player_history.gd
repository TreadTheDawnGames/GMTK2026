class_name PlayerHistoryRecord
extends Node

## How it works:
## - One lifetime record of what this game has cost the player, kept across every
##   run and every session, because the Thief finale reads it back to them.
## - The class is named apart from its `PlayerHistory` autoload so both names can
##   exist: the autoload is the running record, and the type is what a caller
##   declares when it takes one, so nothing has to hold it untyped.
## - Wall-clock seconds accumulate only while the window has focus, so a game
##   left open overnight does not claim the night.
## - Presses are polled the way the timing windows poll them rather than counted
##   at a swing, because the finale's line is about the space bar, not about
##   swings: a press that missed, or that only advanced a dialogue box, still
##   happened and still counts.
## - Every completed hour stamps the wall-clock moment it finished, so the shot
##   can say when an hour happened rather than only how many there were.
## - It writes its own small file and never touches savegame.tres. Lifetime
##   totals must outlive New Run, which clears the saved run, and the save
##   resource carries the whole gem map, which is far too heavy to rewrite on a
##   timer.
## - The invariant is that nothing recorded here ever decreases.

## The record's own file, deliberately separate from user://savegame.tres.
const STORAGE_PATH: String = "user://player_history.cfg"
const _SECTION: String = "lifetime"
## How often accumulated time and presses reach disk. The finale is the only
## reader, so losing the last few seconds to a crash costs nothing, while
## writing every frame would cost a file write every frame.
const _AUTOSAVE_SECONDS: float = 30.0
## A single frame may never contribute more than this. A stalled web tab resumes
## with one enormous delta, and without this the record would swallow it whole.
const _MAX_FRAME_SECONDS: float = 1.0
const SECONDS_PER_HOUR: int = 3600
## Hour stamps past this are not kept. Ninety-nine hours is far beyond any run
## the finale describes, and the cap is what bounds the file's growth.
const _MAX_HOUR_MARKS: int = 99

## Total seconds the player has had this game in front of them, all sessions.
var total_play_seconds: float = 0.0
## Every primary_action press since the record began.
var primary_action_presses: int = 0
## Unix timestamps, one per completed hour: index 0 is when hour 1 finished.
var hour_completion_unix_times: PackedInt64Array = PackedInt64Array()

var _storage_path: String = STORAGE_PATH
var _seconds_since_write: float = 0.0
var _is_focused: bool = true
var _is_dirty: bool = false


## Loads the record and starts accumulating against it.
func _ready() -> void:
	# ALWAYS because a cutscene pauses the tree, and the eight hours a player
	# spends reading the Thief's lines are still eight hours of their life.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()


## Accumulates focused time and presses, and flushes on the autosave interval.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"primary_action"):
		primary_action_presses += 1
		_is_dirty = true
	if _is_focused:
		var elapsed := minf(delta, _MAX_FRAME_SECONDS)
		var completed_hours_before := get_completed_hours()
		total_play_seconds += elapsed
		_is_dirty = true
		if get_completed_hours() > completed_hours_before:
			_stamp_completed_hour()
	_seconds_since_write += delta
	if _seconds_since_write >= _AUTOSAVE_SECONDS:
		_seconds_since_write = 0.0
		flush()


## Stops the clock when the game is not in front of the player, and flushes on
## the way out so a closed tab keeps the session it just had.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_is_focused = true
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_is_focused = false
			flush()
		NOTIFICATION_APPLICATION_PAUSED:
			_is_focused = false
			flush()
		NOTIFICATION_APPLICATION_RESUMED:
			_is_focused = true
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE:
			flush()


## Returns whole hours of accumulated play.
func get_completed_hours() -> int:
	return int(total_play_seconds) / SECONDS_PER_HOUR


## Returns the hour, minute, and second parts the finale reads out.
func get_play_time_parts() -> Vector3i:
	var whole_seconds := int(total_play_seconds)
	return Vector3i(
		whole_seconds / SECONDS_PER_HOUR,
		(whole_seconds / 60) % 60,
		whole_seconds % 60
	)


## Returns when the given one-based hour finished, or 0 if it never did.
func get_hour_completion_unix_time(hour: int) -> int:
	var mark_index := hour - 1
	if mark_index < 0 or mark_index >= hour_completion_unix_times.size():
		return 0
	return hour_completion_unix_times[mark_index]


## Reports whether the player is on a touch device rather than at a desk.
##
## The finale asks this to choose between "your phone" and "your computer", so a
## wrong answer is a wrong line rather than a broken shot. Touch availability is
## the question that actually matters — the web export is the primary target and
## it is the same binary on both — and the mobile feature covers a native build
## on a device that happens to report no touchscreen yet.
func is_touch_device() -> bool:
	return (
		DisplayServer.is_touchscreen_available()
		or OS.has_feature("mobile")
	)


## Writes the record, skipping the write when nothing has changed.
##
## `force` writes regardless, for a caller that has set the totals itself and so
## cannot have gone through the accumulators that mark the record dirty.
func flush(force: bool = false) -> void:
	if not _is_dirty and not force:
		return
	var config := ConfigFile.new()
	config.set_value(_SECTION, "total_play_seconds", total_play_seconds)
	config.set_value(
		_SECTION,
		"primary_action_presses",
		primary_action_presses
	)
	config.set_value(
		_SECTION,
		"hour_completion_unix_times",
		hour_completion_unix_times
	)
	var save_error := config.save(_storage_path)
	if save_error != OK:
		push_warning(
			"Could not write the player history to %s: %s"
			% [_storage_path, error_string(save_error)]
		)
		return
	_is_dirty = false


## Points the record at another file. Tests use this; the game never does.
func use_storage_path(storage_path: String) -> void:
	_storage_path = storage_path
	_load()


## Clears the lifetime record. Nothing in the game calls this — the whole point
## is that the total survives New Run — so it exists for tests and for a player
## support case, and it is deliberately the only thing here that can decrease.
func reset_history() -> void:
	total_play_seconds = 0.0
	primary_action_presses = 0
	hour_completion_unix_times = PackedInt64Array()
	_is_dirty = true
	flush()


## Reads the record, treating any missing or malformed file as a fresh start.
func _load() -> void:
	total_play_seconds = 0.0
	primary_action_presses = 0
	hour_completion_unix_times = PackedInt64Array()
	_is_dirty = false
	var config := ConfigFile.new()
	if config.load(_storage_path) != OK:
		return
	total_play_seconds = maxf(
		float(config.get_value(_SECTION, "total_play_seconds", 0.0)),
		0.0
	)
	primary_action_presses = maxi(
		int(config.get_value(_SECTION, "primary_action_presses", 0)),
		0
	)
	var stored_marks = config.get_value(
		_SECTION,
		"hour_completion_unix_times",
		PackedInt64Array()
	)
	if stored_marks is PackedInt64Array:
		hour_completion_unix_times = stored_marks
	elif stored_marks is Array:
		for stored_mark in stored_marks:
			hour_completion_unix_times.append(int(stored_mark))


## Records the wall-clock moment an hour finished.
##
## It appends one stamp per call rather than filling in to the current hour: the
## only way to skip an hour is an edited file, and inventing a timestamp for an
## hour nobody watched pass would put a lie in the one shot built on these being
## true.
func _stamp_completed_hour() -> void:
	if hour_completion_unix_times.size() >= _MAX_HOUR_MARKS:
		return
	hour_completion_unix_times.append(
		Time.get_unix_time_from_system() as int
	)
	_is_dirty = true
