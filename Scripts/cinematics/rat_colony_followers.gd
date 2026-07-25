class_name RatColonyFollowers
extends Node2D

## How it works:
## - Four ranks of rats dig alongside the miner, receding into the tunnel: each
##   rank further back is smaller, darker, and drawn behind the one in front, so
##   the colony reads as a crowd with depth rather than a row of stickers.
## - Rank membership is index modulo rank count, so trimming the live count for a
##   weaker platform thins every rank evenly and keeps the depth readable instead
##   of deleting the back of the crowd.
## - Rats arrive by running in from both edges on a stagger, alternating sides,
##   rather than appearing in place.
## - The back ranks can wear clump art: one texture showing several rats, costing
##   one actor. That is how the colony gets dense without the node count, the
##   animation count or the per-hit work going up with it.
## - Every real terrain impact restarts a bounded number of strikes, chosen round
##   robin, so the animation cost of one hit does not grow with the crowd. Most
##   rats are idle at any instant; the ones that swing rotate.
## - Owned actors never grow: the scene authors the whole pool and this only ever
##   shows, hides, places and animates what is already there.
## - Run reset cancels every action and hides the complete formation.
## The invariant is that an inactive or reset colony has no visible rat, and that
## the work one impact causes is capped whatever the crowd size.

const RatAppearanceType = preload(
	"res://Scripts/cinematics/cinematic_rat_appearance.gd"
)

signal presentation_strike_requested(screen_position: Vector2)

@export_category("References")
@export var follow_target: Node2D
@export var followers: Array[CinematicRatMiner] = []
## Single-rat art, assigned to the ranks near the front where one rat reads as
## one rat.
@export var rat_appearances: Array[RatAppearanceType] = []
## Clump art: one texture showing several rats at once.
##
## Assigned to the ranks from clump_first_rank back. A clump costs exactly what a
## single rat costs - one node, one animation, one strike - so the depth of the
## crowd is bought by the artist rather than by the frame budget, which is what
## makes a dense colony affordable on web at all.
##
## Leave this empty and every rank falls back to single-rat art, so the colony
## works unchanged until the clump art exists.
@export var clump_appearances: Array[RatAppearanceType] = []
## First rank that uses clump art. Ranks in front of it stay single rats: a clump
## near the camera reads as a smear, while at the back it reads as more colony.
@export_range(0, 3, 1) var clump_first_rank: int = 2

@export_category("Depth Ranks")
## How many ranks the colony recedes into. The terrain draws four strata, so
## four ranks is one rat layer per layer of rock they are digging through.
@export_range(1, 4, 1) var rank_count: int = 4
## Size of a rat in each rank, front rank first. A rat further back is smaller
## because it is further away, not because it is a smaller rat.
@export var rank_scales: PackedFloat32Array = PackedFloat32Array(
	[1.0, 0.82, 0.66, 0.54]
)
## Draw order per rank. The front rank sits below the miner's cutscene order so
## it never covers him, and each rank behind that goes further back.
@export var rank_draw_orders: PackedInt32Array = PackedInt32Array(
	[2, 1, 0, -1]
)
## Tint per rank, darkening the way the terrain's own strata do with depth. This
## sells distance harder than scale does.
@export var rank_tints: PackedColorArray = PackedColorArray([
	Color(1.0, 1.0, 1.0, 1.0),
	Color(0.82, 0.79, 0.76, 1.0),
	Color(0.64, 0.61, 0.59, 1.0),
	Color(0.48, 0.46, 0.45, 1.0),
])
## Vertical offset per rank. Further ranks sit higher, which is what reads as
## standing further back along the tunnel floor.
@export var rank_vertical_offsets: PackedFloat32Array = PackedFloat32Array(
	[64.0, 40.0, 20.0, 4.0]
)
## Horizontal gap between neighbouring rats within one rank. Six rats a rank at
## this spacing reach roughly a third of the way off each side of a 1152-wide
## window, which is what makes the colony read as filling the tunnel rather than
## huddling around the miner.
@export_range(32.0, 256.0, 1.0) var rank_spacing_pixels: float = 132.0
## Clearance kept either side of the miner's own column. The colony draws around
## him, and a rat parked on his origin covers the character being controlled.
@export_range(0.0, 256.0, 1.0) var miner_clearance_pixels: float = 76.0

@export_category("Runtime Caps")
## Rats made live on desktop, and on web. Both are trimmed to whatever the scene
## actually authored; neither ever instantiates anything.
@export_range(1, 32, 1) var max_visible_followers: int = 24
@export_range(1, 32, 1) var web_max_visible_followers: int = 12
## How many rats restart a strike on one impact. This is the cap that keeps a
## hit costing the same whether eight rats are on screen or sixteen.
@export_range(1, 16, 1) var strikes_per_impact: int = 4
@export_range(1, 16, 1) var web_strikes_per_impact: int = 2

@export_category("Arrival")
## How far off each side a rat starts its run in from.
@export_range(128.0, 1536.0, 8.0) var arrival_offscreen_pixels: float = 720.0
@export_range(0.2, 4.0, 0.05) var arrival_run_seconds: float = 1.1
## Delay added per rat so the colony trickles in instead of marching as a block.
@export_range(0.0, 1.0, 0.01) var arrival_stagger_seconds: float = 0.09

var _is_active: bool = false
var _live_follower_count: int = 0
## Rotates through the live rats so each impact hands the strike to a different
## few. Without it the same front rats would swing every time.
var _strike_cursor: int = 0


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
		var appearance := _get_appearance_for_index(follower_index)
		if appearance != null:
			follower.set_appearance(appearance)
	deactivate_followers()


## Returns the art one pool slot wears: clump art for the ranks at the back,
## single-rat art for the ranks in front, and single-rat art everywhere while no
## clump art has been authored yet.
func _get_appearance_for_index(follower_index: int) -> RatAppearanceType:
	var rank := get_rank_for_index(follower_index)
	if rank >= clump_first_rank and not clump_appearances.is_empty():
		return clump_appearances[follower_index % clump_appearances.size()]
	if rat_appearances.is_empty():
		return null
	return rat_appearances[follower_index % rat_appearances.size()]


## Returns how many rats the colony actually depicts, counting a clump as the
## number of rats drawn in it rather than as one actor.
##
## The live actor count stopped being the rat count the moment clump art existed,
## and this is the number worth quoting when deciding whether the colony reads as
## a swarm.
func get_depicted_rat_count() -> int:
	var total := 0
	for follower_index in range(_live_follower_count):
		var appearance := _get_appearance_for_index(follower_index)
		total += (
			1 if appearance == null else maxi(appearance.depicted_rat_count, 1)
		)
	return total


func _process(_delta: float) -> void:
	if _is_active and is_instance_valid(follow_target):
		global_position = follow_target.global_position


## Returns which rank a pool index belongs to. Modulo rather than division, so a
## trimmed pool keeps one rat in every rank instead of losing the back ones.
func get_rank_for_index(follower_index: int) -> int:
	return follower_index % maxi(rank_count, 1)


## Returns where a rat stands once it has arrived, in this node's local space.
##
## Rats alternate sides as the slot number climbs, so the crowd builds outward
## from the miner in both directions and stays balanced at any live count. The
## clearance is added rather than blended in, so the nearest rat on each side is
## clear of him however tight the spacing is set.
func get_slot_position(follower_index: int) -> Vector2:
	var resolved_rank_count := maxi(rank_count, 1)
	var rank := get_rank_for_index(follower_index)
	var slot_in_rank := follower_index / resolved_rank_count
	var side := -1.0 if slot_in_rank % 2 == 0 else 1.0
	var distance_index := float(slot_in_rank / 2)
	# Each rank is nudged along by half a space so the ranks do not line up into
	# columns, which would read as a grid rather than a crowd.
	var rank_stagger := float(rank) * rank_spacing_pixels * 0.5
	var horizontal := side * (
		miner_clearance_pixels
		+ distance_index * rank_spacing_pixels
		+ rank_stagger
	)
	return Vector2(horizontal, _get_rank_vertical_offset(rank))


## Makes the bounded formation persist beside the player after Rotini's beat.
func activate_followers() -> void:
	_is_active = true
	_strike_cursor = 0
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
		if follower_index >= _live_follower_count:
			follower.hide()
			continue
		_apply_rank_look(follower, get_rank_for_index(follower_index))
		_begin_arrival(follower, follower_index)


## Clears all persistent presentation when a run restarts.
func deactivate_followers() -> void:
	_is_active = false
	_live_follower_count = 0
	_strike_cursor = 0
	for follower in followers:
		if not is_instance_valid(follower):
			continue
		follower.cancel_action()
		follower.hide()


## Dresses one rat for the rank it belongs to. Scale, tint and draw order move
## together; changing one alone makes a rat read as the wrong size rather than
## as further away.
func _apply_rank_look(follower: CinematicRatMiner, rank: int) -> void:
	follower.scale = Vector2.ONE * _get_rank_scale(rank)
	follower.modulate = _get_rank_tint(rank)
	follower.set_plane_draw_order(_get_rank_draw_order(rank))


## Runs one rat in from whichever side its slot sits on, after its share of the
## stagger.
func _begin_arrival(follower: CinematicRatMiner, follower_index: int) -> void:
	var slot_local := get_slot_position(follower_index)
	var entry_local := Vector2(
		(
			-arrival_offscreen_pixels
			if slot_local.x < 0.0
			else arrival_offscreen_pixels
		),
		slot_local.y
	)
	follower.prepare_for_sequence(to_global(entry_local), follower_index)
	# prepare_for_sequence resets scale, so the rank look is reapplied after it
	# rather than before, or every rat arrives at full size.
	_apply_rank_look(follower, get_rank_for_index(follower_index))
	var delay := float(follower_index) * arrival_stagger_seconds
	if delay <= 0.0:
		follower.start_run_to_target(
			to_global(slot_local),
			arrival_run_seconds
		)
		return
	# A timer rather than a tween chain: the rat owns its own run, and this only
	# decides when that run is allowed to begin.
	var timer := get_tree().create_timer(delay, true)
	timer.timeout.connect(
		_on_arrival_delay_elapsed.bind(follower, follower_index)
	)


func _on_arrival_delay_elapsed(
	follower: CinematicRatMiner,
	follower_index: int
) -> void:
	if not _is_active or not is_instance_valid(follower):
		return
	if follower_index >= _live_follower_count:
		return
	follower.start_run_to_target(
		to_global(get_slot_position(follower_index)),
		arrival_run_seconds
	)


## Lets production wiring route resolved player impacts without terrain coupling.
##
## Only a bounded slice of the colony swings per hit, taken round robin from the
## live rats. The crowd can grow without the cost of a hit growing with it, and a
## rotating few swinging reads better than every rat striking in unison.
func _on_player_impact_resolved(
	_screen_position: Vector2,
	cells_removed: int,
	_combo_strength: float,
	_debris_multiplier: float,
	swing_side: int
) -> void:
	if not _is_active or cells_removed <= 0 or _live_follower_count <= 0:
		return
	var facing := signi(swing_side) if swing_side != 0 else 1
	var budget := mini(_get_strike_budget(), _live_follower_count)
	var started := 0
	var examined := 0
	while started < budget and examined < _live_follower_count:
		var follower_index := (
			(_strike_cursor + examined) % _live_follower_count
		)
		examined += 1
		var follower := followers[follower_index]
		if not is_instance_valid(follower) or not follower.visible:
			continue
		follower.cancel_action()
		follower.set_facing_direction(facing)
		if follower.start_entry_breach(
			follower.strike_anchor.global_position
		):
			started += 1
	_strike_cursor = (_strike_cursor + examined) % maxi(
		_live_follower_count, 1
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
	if rank_scales.size() < rank_count:
		return "Rat colony ranks need one scale per rank."
	if rank_draw_orders.size() < rank_count:
		return "Rat colony ranks need one draw order per rank."
	if rank_tints.size() < rank_count:
		return "Rat colony ranks need one tint per rank."
	if rank_vertical_offsets.size() < rank_count:
		return "Rat colony ranks need one vertical offset per rank."
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


func _get_strike_budget() -> int:
	return (
		mini(strikes_per_impact, web_strikes_per_impact)
		if OS.has_feature("web")
		else strikes_per_impact
	)


func _get_rank_scale(rank: int) -> float:
	if rank < 0 or rank >= rank_scales.size():
		return 1.0
	return rank_scales[rank]


func _get_rank_draw_order(rank: int) -> int:
	if rank < 0 or rank >= rank_draw_orders.size():
		return 0
	return rank_draw_orders[rank]


func _get_rank_tint(rank: int) -> Color:
	if rank < 0 or rank >= rank_tints.size():
		return Color.WHITE
	return rank_tints[rank]


func _get_rank_vertical_offset(rank: int) -> float:
	if rank < 0 or rank >= rank_vertical_offsets.size():
		return 0.0
	return rank_vertical_offsets[rank]
