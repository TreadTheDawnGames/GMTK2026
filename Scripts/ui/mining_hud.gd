class_name MiningHud
extends CanvasLayer

## Displays distance to or beyond the Thief and a pace-based arrival estimate.

const OptionsMenuType := preload("res://Scripts/ui/Options.gd")

@export var depth_label: Label
@export var bottom_eta_label: Label
@export var fps_label: Label
@export var options_scene: PackedScene
@export_range(0.1, 2.0, 0.1) var eta_refresh_seconds: float = 0.25

var _elapsed_run_seconds: int = 0
var _eta_refresh_remaining: float = 0.0
var _open_options: Control
var _save_game: SaveGame
var _depth: int = 0
var _remaining_depth: int = 0
var _distance_since_thief: int = 0
var _has_reached_thief: bool = false


## Displays the starting state before the shared run timeline begins.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_update_remaining_depth()
	_update_bottom_eta()


## Supplies the save resource passed to settings screens opened by the HUD.
func set_save_game(save_game: SaveGame) -> void:
	_save_game = save_game


## Displays one complete run-progress snapshot supplied by the composition root.
func show_run_progress(
	depth: int,
	remaining_depth: int,
	distance_since_thief: int,
	has_reached_thief: bool
) -> void:
	_depth = maxi(depth, 0)
	_remaining_depth = maxi(remaining_depth, 0)
	_distance_since_thief = maxi(distance_since_thief, 0)
	_has_reached_thief = has_reached_thief
	_update_remaining_depth()
	_update_bottom_eta()


## Refreshes the FPS display and pace estimate at a bounded cadence.
func _process(delta: float) -> void:
	_eta_refresh_remaining -= delta
	if _eta_refresh_remaining > 0.0:
		return
	_eta_refresh_remaining = eta_refresh_seconds
	_update_bottom_eta()
	fps_label.text = str("FPS: ", Engine.get_frames_per_second())


## Consumes the canonical controllable-run clock for pace projection.
func _on_run_time_changed(elapsed_seconds: int) -> void:
	_elapsed_run_seconds = maxi(elapsed_seconds, 0)
	_update_remaining_depth()
	_update_bottom_eta()


## Shows how much gameplay depth remains before the run bottom.
func _update_remaining_depth() -> void:
	if _has_reached_thief:
		depth_label.text = (
			"DISTANCE SINCE THIEF  %s"
			% _format_number(_distance_since_thief)
		)
		return
	depth_label.text = (
		"REMAINING TO THE THIEF  %s"
		% _format_number(_remaining_depth)
	)


## Projects the current average descent pace across all remaining depth.
func _update_bottom_eta() -> void:
	if _has_reached_thief:
		bottom_eta_label.text = "THIEF PASSED"
		return
	if _depth <= 0:
		bottom_eta_label.text = "THIEF ETA  --:--"
		return
	var estimated_seconds := ceili(
		_elapsed_run_seconds
			* float(_remaining_depth)
			/ float(_depth)
	)
	var estimated_hours := floori(
		float(estimated_seconds) / 3_600.0
	)
	var estimated_minutes := floori(
		float(estimated_seconds % 3_600) / 60.0
	)
	var estimated_remaining_seconds := estimated_seconds % 60
	var formatted_eta := (
		"%d:%02d:%02d"
		% [
			estimated_hours,
			estimated_minutes,
			estimated_remaining_seconds,
		]
		if estimated_hours > 0
		else "%02d:%02d"
			% [estimated_minutes, estimated_remaining_seconds]
	)
	bottom_eta_label.text = "THIEF ETA  %s" % formatted_eta


## Adds commas to a whole number.
func _format_number(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if (
		key_event.keycode == Key.KEY_ESCAPE
		and not is_instance_valid(_open_options)
	):
		var options := options_scene.instantiate() as OptionsMenuType
		if options == null:
			push_error(
				"The configured options scene must instantiate an OptionsMenu."
			)
			return
		options.set_save_game(_save_game)
		_open_options = options
		add_child(_open_options)
	elif is_instance_valid(_open_options):
		_open_options._on_back_button_pressed()
