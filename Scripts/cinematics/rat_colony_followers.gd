class_name RatColonyFollowers
extends Node2D

## How it works:
## - A fixed authored formation follows the miner's screen-space root.
## - The completed Rotini encounter activates the formation for normal gameplay.
## - Every real terrain impact restarts every visible rat's matching strike.
## - Rat contacts request shared feedback but never mutate logical terrain.
## - Run reset cancels every action and hides the complete formation.
## - Owned actors never grow: the scene has at most max_visible_followers.
## - Web builds show no more than web_max_visible_followers.
## - The invariant is that inactive or reset colonies have no visible rat.

const RatAppearanceType = preload(
	"res://Scripts/cinematics/cinematic_rat_appearance.gd"
)

signal presentation_strike_requested(screen_position: Vector2)

@export_category("References")
@export var follow_target: Node2D
@export var followers: Array[CinematicRatMiner] = []
@export var rat_appearances: Array[RatAppearanceType] = []

@export_category("Runtime Caps")
@export_range(1, 8, 1) var max_visible_followers: int = 5
@export_range(1, 8, 1) var web_max_visible_followers: int = 3

var _is_active: bool = false
var _live_follower_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for follower_index in range(followers.size()):
		var follower := followers[follower_index]
		if not is_instance_valid(follower):
			continue
		if not follower.strike_contact.is_connected(
			_on_follower_strike_contact
		):
			follower.strike_contact.connect(_on_follower_strike_contact)
		if not rat_appearances.is_empty():
			follower.set_appearance(
				rat_appearances[
					follower_index % rat_appearances.size()
				]
			)
	deactivate_followers()


func _process(_delta: float) -> void:
	if _is_active and is_instance_valid(follow_target):
		global_position = follow_target.global_position


## Makes the bounded formation persist beside the player after Rotini's beat.
func activate_followers() -> void:
	_is_active = true
	_live_follower_count = mini(
		followers.size(),
		_get_visible_follower_cap()
	)
	if is_instance_valid(follow_target):
		global_position = follow_target.global_position
	for follower_index in range(followers.size()):
		var follower := followers[follower_index]
		if not is_instance_valid(follower):
			continue
		follower.cancel_action()
		if follower_index < _live_follower_count:
			follower.prepare_for_sequence(
				follower.global_position,
				follower_index
			)
		else:
			follower.hide()


## Clears all persistent presentation when a run restarts.
func deactivate_followers() -> void:
	_is_active = false
	_live_follower_count = 0
	for follower in followers:
		if not is_instance_valid(follower):
			continue
		follower.cancel_action()
		follower.hide()


## Lets production wiring route resolved player impacts without terrain coupling.
func _on_player_impact_resolved(
	_screen_position: Vector2,
	cells_removed: int,
	_combo_strength: float,
	_debris_multiplier: float,
	swing_side: int
) -> void:
	if not _is_active or cells_removed <= 0 or _live_follower_count <= 0:
		return
	for follower_index in range(_live_follower_count):
		var follower := followers[follower_index]
		if not is_instance_valid(follower):
			continue
		follower.cancel_action()
		follower.set_facing_direction(
			signi(swing_side) if swing_side != 0 else 1
		)
		follower.start_entry_breach(
			follower.strike_anchor.global_position
		)


func _on_run_reset() -> void:
	deactivate_followers()


func is_active() -> bool:
	return _is_active


func get_visible_follower_count() -> int:
	return _live_follower_count


func validate_followers() -> String:
	if not is_instance_valid(follow_target):
		return "Rat colony followers require a miner follow target."
	if followers.is_empty():
		return "Rat colony followers require authored rat actors."
	if rat_appearances.is_empty():
		return "Rat colony followers require at least one rat appearance."
	for follower in followers:
		if not is_instance_valid(follower):
			return "Rat colony followers contain an unassigned rat actor."
	return ""


func _on_follower_strike_contact(screen_position: Vector2) -> void:
	if _is_active:
		presentation_strike_requested.emit(screen_position)


func _get_visible_follower_cap() -> int:
	return (
		mini(max_visible_followers, web_max_visible_followers)
		if OS.has_feature("web")
		else max_visible_followers
	)
