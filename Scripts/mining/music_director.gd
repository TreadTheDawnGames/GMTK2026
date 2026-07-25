class_name MusicDirector
extends Node

## How it works:
## - Input: the ComboDirector's intensity step and its combo tier crossings.
## - Every intensity layer is its own looping player, all started on the same
##   frame and never stopped, so the stems stay phase-locked for the whole run
##   and only their gains move. Stopping and restarting a layer would drop it
##   out of phase with the others, which is the one thing that must never break.
## - Layer i is audible whenever intensity >= i, crossfaded in linear gain.
## - A tier climb fires a one-shot fill over the top; a lost streak drops back to
##   the reward floor at the faster loss rate.

@export_category("Streams")
## One looping stem per intensity step, quietest first. Their lengths must stay
## whole multiples of each other or the layers drift apart over a long run.
@export var layer_streams: Array[AudioStream] = []
## One transition stinger per tier climb, indexed by the tier being entered.
@export var fill_streams: Array[AudioStream] = []

@export_category("Mix")
@export var music_bus: StringName = &"Music"
## Gain each audible layer settles at, before the bus volume.
@export_range(0.0, 1.0, 0.05) var layer_gain: float = 1.0
@export_range(0.0, 1.0, 0.05) var fill_gain: float = 0.8

@export_category("Timing")
## How fast a newly audible layer arrives.
@export_range(0.1, 10.0, 0.1) var fade_in_per_second: float = 2.0
## How fast a layer leaves when the run simply cools off.
@export_range(0.1, 10.0, 0.1) var fade_out_per_second: float = 1.0
## How fast layers leave when a streak is actually lost, so the drop lands.
@export_range(0.1, 20.0, 0.1) var streak_loss_fade_per_second: float = 5.0

# Below this the layer is inaudible and gets pinned to silence, because
# linear_to_db() of zero is negative infinity.
const _SILENCE_GAIN := 0.001
const _SILENCE_DB := -60.0

var _layer_players: Array[AudioStreamPlayer] = []
var _fill_player: AudioStreamPlayer
var _current_gains: Array[float] = []
var _target_gains: Array[float] = []
var _fade_rate: float = 1.0
var _intensity: int = 0


## Builds one player per authored stem and starts them together.
func _ready() -> void:
	for layer_index in layer_streams.size():
		var stream: AudioStream = layer_streams[layer_index]
		if stream == null:
			push_warning(
				"MusicDirector layer %d has no stream." % layer_index
			)
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = music_bus
		player.volume_db = _SILENCE_DB
		add_child(player)
		_layer_players.append(player)
		_current_gains.append(0.0)
		_target_gains.append(0.0)
	_fill_player = AudioStreamPlayer.new()
	_fill_player.bus = music_bus
	_fill_player.volume_db = linear_to_db(maxf(fill_gain, _SILENCE_GAIN))
	add_child(_fill_player)
	# One pass over every player before any of them advances keeps the stems
	# sample-aligned; a per-layer start spread across frames would not.
	for player: AudioStreamPlayer in _layer_players:
		if player.stream != null:
			player.play()
	_apply_intensity(0, fade_in_per_second)


## Adopts the shared intensity step at the ordinary cool-off rate.
func _on_intensity_changed(intensity: int, previous_intensity: int) -> void:
	_apply_intensity(
		intensity,
		fade_in_per_second
		if intensity > previous_intensity
		else fade_out_per_second
	)


## Lays a fill over a climb into a new tier.
func _on_combo_tier_changed(tier: int, previous_tier: int) -> void:
	if tier <= previous_tier or fill_streams.is_empty():
		return
	var fill_index := clampi(tier - 1, 0, fill_streams.size() - 1)
	var fill: AudioStream = fill_streams[fill_index]
	if fill == null:
		return
	_fill_player.stream = fill
	_fill_player.play()


## Collapses to the reward floor faster than an unfed streak would.
func _on_streak_lost(_previous_combo: int, _previous_tier: int) -> void:
	_fade_rate = streak_loss_fade_per_second
	set_process(true)


## Returns the mix to its opening layer for a fresh run.
func _on_run_reset() -> void:
	_apply_intensity(0, streak_loss_fade_per_second)


## Crossfades every layer toward its target and sleeps once they all arrive.
func _process(delta: float) -> void:
	var is_settled := true
	for layer_index in _layer_players.size():
		var current: float = _current_gains[layer_index]
		var target: float = _target_gains[layer_index]
		if is_equal_approx(current, target):
			continue
		current = move_toward(current, target, _fade_rate * delta)
		_current_gains[layer_index] = current
		var player: AudioStreamPlayer = _layer_players[layer_index]
		player.volume_db = (
			_SILENCE_DB
			if current <= _SILENCE_GAIN
			else linear_to_db(current)
		)
		if not is_equal_approx(current, target):
			is_settled = false
	if is_settled:
		set_process(false)


## Points every layer at the gain the requested step asks for.
func _apply_intensity(intensity: int, fade_rate: float) -> void:
	_intensity = maxi(intensity, 0)
	_fade_rate = fade_rate
	for layer_index in _target_gains.size():
		_target_gains[layer_index] = (
			layer_gain
			if layer_index <= _intensity
			else 0.0
		)
	set_process(true)
