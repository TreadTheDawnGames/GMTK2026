class_name RatColonyFollowers
extends Node2D

## How it works:
## - Fixed left/right lanes blanket the floor while preserving the miner column.
## - Four shader-lit ranks recede by draw order, haze, and ground shadow.
## - Shipped ranks use normal-size individual mouse art, never miniature clumps.
## - Every successful player hit makes every visible mouse swing at its own lane.
## - Every contact requests the miner's full-width tunnel through the same depth.
## - A deterministic side bias steers future targets through Caspian's public API.
## - Reset cancels every action, pending hop, target bias, and visible mouse.
## Invariant: active mice share the miner's ground face; inactive mice are hidden.

const RatAppearanceType = preload(
	"res://Scripts/cinematics/cinematic_rat_appearance.gd"
)

signal presentation_strike_requested(screen_position: Vector2)
signal terrain_dig_requested(
	screen_position: Vector2,
	start_row: int,
	depth_rows: int,
	half_width_cells: int,
	miner_cell_x: int,
	miner_target_cell_x: int
)
signal preferred_mining_side_requested(side: int)

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
## Keeps wide clump art out of the protected player column.
@export_range(0.0, 576.0, 4.0) var clump_minimum_distance_pixels: float = 192.0

@export_category("Depth Ranks")
## How many ranks the colony recedes into. The terrain draws four strata, so
## four ranks is one rat layer per layer of rock they are digging through.
@export_range(1, 4, 1) var rank_count: int = 4
## Size of a rat in each rank, front rank first. Keep every rank near the normal
## large mouse size; lane height and lighting carry most of the depth read.
@export var rank_scales: PackedFloat32Array = PackedFloat32Array(
	[1.0, 0.82, 0.66, 0.54]
)
## Absolute draw order per rank. The front row shares the cast's second-stratum
## order and each later row recedes behind one more terrain stratum.
@export var rank_draw_orders: PackedInt32Array = PackedInt32Array(
	[1, 0, -1, -2]
)
## Tint per rank, darkening the way the terrain's own strata do with depth. This
## sells distance harder than scale does.
@export var rank_tints: PackedColorArray = PackedColorArray([
	Color(1.0, 1.0, 1.0, 1.0),
	Color(0.82, 0.79, 0.76, 1.0),
	Color(0.64, 0.61, 0.59, 1.0),
	Color(0.48, 0.46, 0.45, 1.0),
])
## Ground offset per rank. Gameplay gives every rank the same value so each
## pickaxe reaches the miner's current face; other presentations may vary it.
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
## Each live actor performs one real contact per resolved player hit and copies
## the miner's prepared width and depth, so every mouse removes the same area.
## Dirt, sparks, and shake are pooled presentation, not terrain authority. Limit
## those emitters while all visible mice still animate and remove real cells.
@export_range(1, 16, 1) var presentation_contacts_per_impact: int = 8
@export_range(1, 16, 1) var web_presentation_contacts_per_impact: int = 4
## Matches MinerRig.combo_speed_bonus so their wind-up and contact frames align.
@export_range(0.0, 1.0, 0.05) var combo_speed_bonus: float = 0.35

@export_category("Arrival")
## How far off each side a rat starts its run in from.
@export_range(128.0, 1536.0, 8.0) var arrival_offscreen_pixels: float = 720.0
@export_range(0.2, 4.0, 0.05) var arrival_run_seconds: float = 1.1
## Delay added per rat so the colony trickles in instead of marching as a block.
@export_range(0.0, 1.0, 0.01) var arrival_stagger_seconds: float = 0.09

@export_category("Idle Motion")
## One back-rank mouse hops in place this often while mining continues.
@export_range(1, 12, 1) var impacts_per_idle_hop: int = 2
@export_range(0.1, 1.2, 0.05) var idle_hop_seconds: float = 0.38
@export_range(4.0, 96.0, 1.0) var idle_hop_height_pixels: float = 30.0

var _is_active: bool = false
var _live_follower_count: int = 0
## Rotates through the live rats so each impact hands the strike to a different
## few. Without it the same front rats would swing every time.
var _reduce_motion_enabled: bool = false
var _hop_cursor: int = 0
var _resolved_impact_count: int = 0
var _remaining_presentation_contacts: int = 0
## MiningController publishes these before the shared swing starts. They remain
## stable through every mouse contact so camera descent cannot move a tunnel's
## logical start into a wall. One pending swing is retained; no per-hit arrays.
var _pending_dig_start_row: int = 0
var _pending_dig_depth_rows: int = 1
var _pending_dig_half_width_cells: int = 0
var _pending_dig_miner_cell_x: int = 0
var _pending_dig_miner_target_cell_x: int = 0
## Built exactly once from the fixed scene pool; no slot vectors allocate per hit.
var _slot_positions := PackedVector2Array()
## At most one already-authored mouse is queued to hop after its strike recovers.
var _pending_hop_follower: CinematicRatMiner


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rebuild_formation_cache()
	for follower_index in range(followers.size()):
		var follower := followers[follower_index]
		if not is_instance_valid(follower):
			continue
		var contact_handler := _on_follower_strike_contact.bind(follower)
		if not follower.strike_contact.is_connected(contact_handler):
			follower.strike_contact.connect(contact_handler)
		var breach_finished_handler := (
			_on_follower_entry_breach_finished.bind(follower)
		)
		if not follower.entry_breach_finished.is_connected(
			breach_finished_handler
		):
			follower.entry_breach_finished.connect(breach_finished_handler)
		var appearance := _get_appearance_for_index(follower_index)
		if appearance != null:
			follower.set_appearance(appearance)
	deactivate_followers()


## Snaps the formation into place and removes repeated decorative strikes.
func set_reduce_motion_enabled(enabled: bool) -> void:
	_reduce_motion_enabled = enabled
	for follower in followers:
		if is_instance_valid(follower):
			follower.set_reduce_motion_enabled(enabled)
	if not enabled or not _is_active:
		return
	for follower_index in range(_live_follower_count):
		var follower := followers[follower_index]
		if not is_instance_valid(follower):
			continue
		follower.prepare_for_sequence(
			to_global(get_slot_position(follower_index)),
			follower_index
		)
		_apply_rank_look(follower, get_rank_for_index(follower_index))


## Returns the art one pool slot wears: clump art for the ranks at the back,
## single-rat art for the ranks in front, and single-rat art everywhere while no
## clump art has been authored yet.
func _get_appearance_for_index(follower_index: int) -> RatAppearanceType:
	var rank := get_rank_for_index(follower_index)
	var slot_position := get_slot_position(follower_index)
	if (
		rank >= clump_first_rank
		and absf(slot_position.x) >= clump_minimum_distance_pixels
		and not clump_appearances.is_empty()
	):
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
		var target_position := follow_target.global_position
		var is_walking := (
			target_position.distance_squared_to(global_position) > 0.0001
		)
		global_position = target_position
		for follower_index in range(_live_follower_count):
			var follower := followers[follower_index]
			if is_instance_valid(follower) and follower.visible:
				follower.set_ground_travel_active(is_walking)


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
	if follower_index >= 0 and follower_index < _slot_positions.size():
		return _slot_positions[follower_index]
	return _calculate_slot_position(follower_index)


func _calculate_slot_position(follower_index: int) -> Vector2:
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


## Precalculates the immutable formation once.
func _rebuild_formation_cache() -> void:
	_slot_positions.clear()
	for follower_index in range(followers.size()):
		_slot_positions.append(_calculate_slot_position(follower_index))


## Makes the bounded formation persist beside the player after Rotini's beat.
func activate_followers() -> void:
	_is_active = true
	_hop_cursor = 0
	_resolved_impact_count = 0
	_remaining_presentation_contacts = 0
	_pending_dig_start_row = 0
	_pending_dig_depth_rows = 1
	_pending_dig_half_width_cells = 0
	_pending_dig_miner_cell_x = 0
	_pending_dig_miner_target_cell_x = 0
	_pending_hop_follower = null
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
	preferred_mining_side_requested.emit(-1)


## Clears all persistent presentation when a run restarts.
func deactivate_followers() -> void:
	_is_active = false
	_live_follower_count = 0
	_hop_cursor = 0
	_resolved_impact_count = 0
	_remaining_presentation_contacts = 0
	_pending_dig_start_row = 0
	_pending_dig_depth_rows = 1
	_pending_dig_half_width_cells = 0
	_pending_dig_miner_cell_x = 0
	_pending_dig_miner_target_cell_x = 0
	_pending_hop_follower = null
	for follower in followers:
		if not is_instance_valid(follower):
			continue
		follower.cancel_action()
		follower.hide()
	preferred_mining_side_requested.emit(0)


## Dresses one rat for the rank it belongs to. The scale variation stays subtle;
## tint, lane height, shadow, and draw order carry the distance read.
func _apply_rank_look(follower: CinematicRatMiner, rank: int) -> void:
	follower.scale = Vector2.ONE * _get_rank_scale(rank)
	follower.modulate = _get_rank_tint(rank)
	follower.set_plane_draw_order(_get_rank_draw_order(rank))
	follower.set_visual_depth_ratio(
		float(rank) / float(maxi(rank_count - 1, 1))
	)


## Runs one rat in from whichever side its slot sits on, after its share of the
## stagger.
func _begin_arrival(follower: CinematicRatMiner, follower_index: int) -> void:
	var slot_local := get_slot_position(follower_index)
	if _reduce_motion_enabled:
		follower.prepare_for_sequence(
			to_global(slot_local),
			follower_index
		)
		_apply_rank_look(follower, get_rank_for_index(follower_index))
		return
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


## Captures the same immutable terrain interval that the miner will dig.
func _on_player_dig_prepared(
	start_cell: Vector2i,
	depth_rows: int,
	player_half_width_cells: int,
	_player_target_cell_x: int,
	_combo: int
) -> void:
	if not _is_active:
		return
	_pending_dig_start_row = start_cell.y
	_pending_dig_depth_rows = maxi(depth_rows, 1)
	_pending_dig_half_width_cells = maxi(player_half_width_cells, 0)
	_pending_dig_miner_cell_x = start_cell.x
	_pending_dig_miner_target_cell_x = _player_target_cell_x


## Starts every mouse from the same successful swing request as MinerRig.
func _on_player_swing_requested(
	_combo: int,
	combo_strength: float,
	swing_speed_multiplier: float,
	path_direction: int
) -> void:
	if not _is_active or _live_follower_count <= 0:
		return
	var facing := signi(path_direction) if path_direction != 0 else 1
	var playback_speed := (
		lerpf(1.0, 1.0 + combo_speed_bonus, combo_strength)
		* maxf(swing_speed_multiplier, 0.1)
	)
	_remaining_presentation_contacts = (
		mini(
			presentation_contacts_per_impact,
			web_presentation_contacts_per_impact
		)
		if OS.has_feature("web")
		else presentation_contacts_per_impact
	)
	for follower_index in range(_live_follower_count):
		_start_follower_strike(
			follower_index,
			facing,
			playback_speed
		)


## Lets production wiring route resolved player impacts without terrain coupling.
##
## Terrain contacts already came from the shared swing-start timeline. Resolution
## only advances deterministic steering and schedules between-hit idle motion.
func _on_player_impact_resolved(
	_screen_position: Vector2,
	cells_removed: int,
	_combo_strength: float,
	_debris_multiplier: float,
	_swing_side: int
) -> void:
	if (
		_reduce_motion_enabled
		or not _is_active
		or cells_removed <= 0
		or _live_follower_count <= 0
	):
		return
	_resolved_impact_count += 1
	preferred_mining_side_requested.emit(
		-1 if _resolved_impact_count % 2 == 0 else 1
	)
	if _resolved_impact_count % maxi(impacts_per_idle_hop, 1) == 0:
		_schedule_next_idle_hop()


func _start_follower_strike(
	follower_index: int,
	facing: int,
	playback_speed: float
) -> bool:
	if follower_index < 0 or follower_index >= _live_follower_count:
		return false
	var follower := followers[follower_index]
	if not is_instance_valid(follower) or not follower.visible:
		return false
	follower.cancel_action()
	follower.set_facing_direction(facing)
	if not follower.start_entry_breach(
		follower.strike_anchor.global_position,
		playback_speed
	):
		return false
	return true


## Selects one mouse to hop after its current miner-mirrored strike finishes.
func _schedule_next_idle_hop() -> void:
	for offset in range(_live_follower_count):
		var follower_index := (
			(_hop_cursor + offset) % _live_follower_count
		)
		if get_rank_for_index(follower_index) == 0:
			continue
		var follower := followers[follower_index]
		if (
			not is_instance_valid(follower)
			or not follower.visible
		):
			continue
		_pending_hop_follower = follower
		_hop_cursor = (
			(follower_index + 1) % maxi(_live_follower_count, 1)
		)
		return


func _on_follower_entry_breach_finished(
	_rat: CinematicRatMiner,
	follower: CinematicRatMiner
) -> void:
	if (
		not _is_active
		or follower != _pending_hop_follower
		or not is_instance_valid(follower)
	):
		return
	_pending_hop_follower = null
	follower.jump_to(
		follower.global_position,
		idle_hop_seconds,
		idle_hop_height_pixels
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


func _on_follower_strike_contact(
	screen_position: Vector2,
	follower: CinematicRatMiner
) -> void:
	if not _is_active:
		return
	if not is_instance_valid(follower) or not follower.visible:
		return
	if _remaining_presentation_contacts > 0:
		_remaining_presentation_contacts -= 1
		presentation_strike_requested.emit(screen_position)
	terrain_dig_requested.emit(
		screen_position,
		_pending_dig_start_row,
		_pending_dig_depth_rows,
		_pending_dig_half_width_cells,
		_pending_dig_miner_cell_x,
		_pending_dig_miner_target_cell_x
	)


## Returns the live sole positions sampled by the composition root after a
## shared landing. The packed result is bounded by the fixed 32-actor pool and
## is discarded once that landing has been seated.
func get_live_ground_sample_screen_xs() -> PackedFloat32Array:
	var sample_xs := PackedFloat32Array()
	sample_xs.resize(_live_follower_count)
	for follower_index in range(_live_follower_count):
		var follower := followers[follower_index]
		sample_xs[follower_index] = (
			follower.global_position.x
			if is_instance_valid(follower)
			else NAN
		)
	return sample_xs


## Seats each mouse's sole on its own organic tunnel floor. An invalid renderer
## sample preserves the last supported position instead of snapping into rock.
func seat_live_followers_on_ground(
	support_screen_ys: PackedFloat32Array
) -> void:
	var supported_count := mini(
		_live_follower_count,
		support_screen_ys.size()
	)
	for follower_index in range(supported_count):
		var follower := followers[follower_index]
		var support_screen_y := support_screen_ys[follower_index]
		if (
			not is_instance_valid(follower)
			or not follower.visible
			or is_nan(support_screen_y)
			or is_inf(support_screen_y)
		):
			continue
		follower.global_position.y = support_screen_y


func _get_visible_follower_cap() -> int:
	return (
		mini(max_visible_followers, web_max_visible_followers)
		if OS.has_feature("web")
		else max_visible_followers
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
