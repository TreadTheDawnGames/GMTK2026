@tool
class_name MiningConfig
extends Resource

## Shared, inspector-editable tuning for terrain, descent, and hit feedback.
## One descended terrain row equals one gameplay depth.
## @tool so the editor terrain preview can call get_bottom_surface_row(): a
## non-tool resource loads as a placeholder inside a tool script and throws on
## any method call.

enum MiningCameraStyle {
	SMOOTH_FOLLOW,
	CHUNK_SNAP,
}

## Godot stores depth in a signed integer, so literal infinity is unavailable.
## This ceiling is intentionally unreachable in normal play (well over a
## century at ten rows per second) and exists only to keep terrain coordinates
## inside a stable numeric range.
const MAX_PLAYABLE_DEPTH: int = 2_000_000_000

@export_category("Terrain")
## Covers the 1152px canvas while the autonomous path pans 24 cells sideways.
## Gameplay needs about 192. The rest is headroom for the opening's wide title
## framing, which pulls the camera back until it can see roughly 2880 px of
## world: anything narrower puts the terrain's own left and right edges in shot
## as hard cuts against the sky. Every streamed chunk's mask is this wide, so
## lowering it back toward 192 is the first thing to try if the web export runs
## short of per-hit budget.
@export_range(16, 512, 1) var terrain_width_cells: int = 384
# Twenty-two rows keep active sculpt expansion and high-density uploads below
# the atomic web limit. Publication is queued by immutable layer group, so the
# smaller streaming unit does not lower the 16-pixel world-space fidelity.
@export_range(16, 256, 1) var chunk_height_cells: int = 22
## Sets the world-space size of one gameplay terrain cell.
@export_range(1, 32, 1) var terrain_cell_world_size: int = 8
@export_range(1, 512, 1) var initial_surface_row: int = 38
## Story milestone where the player reaches the Thief. Mining continues below.
@export_range(1, 1_000_000, 1) var total_run_depth: int = 100_000
## Terrain rows cleared by a normal starting hit.
@export_range(1, 64, 1) var base_mine_depth_rows: int = 6
@export_range(0, 16, 1) var combo_mine_depth_rows_per_step: int = 1
## Three cells on each side make a seven-cell-wide starting tunnel.
@export_range(0, 32, 1) var base_tunnel_half_width_cells: int = 3
@export_range(0, 8, 1) var combo_tunnel_half_width_cells_per_step: int = 1

@export_category("Autonomous Path")
## Moves the landing column after each earned strike.
@export_range(1, 16, 1) var snake_horizontal_step_cells: int = 3
## Reverses direction at this distance from the terrain center.
@export_range(1, 64, 1) var snake_half_span_cells: int = 24

@export_category("View")
@export var terrain_screen_center_x: float = 576.0
@export var mining_face_screen_y: float = 260.0
## Keeps upward review from exposing a chunk while its masks are still queued.
@export_range(0, 4, 1) var preload_chunks_above: int = 1
@export_range(0, 4, 1) var preload_chunks_below: int = 1
## Accelerates the miner through newly opened terrain, in rows per second squared.
@export_range(10.0, 1_000.0, 10.0) var mining_fall_gravity: float = 300.0
## Caps long falls without changing the distance the miner traverses.
@export_range(10.0, 1_000.0, 10.0) var mining_max_fall_speed: float = 240.0
## Chooses continuous camera tracking or half-chunk page flips.
@export var mining_camera_style: MiningCameraStyle = (
	MiningCameraStyle.SMOOTH_FOLLOW
)
## Controls how quickly the camera eases after the airborne miner.
@export_range(1.0, 30.0, 0.5) var mining_camera_follow_speed: float = 5.0
## Prevents a large blast from carrying the miner below the visible follow area.
@export_range(1.0, 64.0, 1.0) var mining_camera_max_lag_rows: float = 12.0
## Recenters the view after landing, in terrain rows per second.
@export_range(10.0, 2_000.0, 10.0) var landing_recenter_speed: float = 60.0
## Viewport pixels queued by one mouse-wheel step. Fractional wheel factors keep
## high-precision devices sub-pixel accurate instead of rounding to terrain rows.
@export_range(8.0, 256.0, 1.0) var review_scroll_pixels_per_step: float = 96.0
## Maximum presentation speed after wheel input, measured in viewport pixels.
@export_range(120.0, 4_000.0, 10.0) var review_scroll_speed_pixels_per_second: float = 1_200.0
## An idle upward review may settle onto an already-visited encounter this close.
@export_range(0.0, 512.0, 1.0) var review_cutscene_snap_distance_pixels: float = 144.0
## Continuous input always wins; the magnetic encounter stop waits for this gap.
@export_range(0.0, 1.0, 0.01) var review_cutscene_snap_delay_seconds: float = 0.14
@export_range(100.0, 50_000.0, 100.0) var return_fall_gravity: float = 8_000.0
@export_range(100.0, 50_000.0, 100.0) var return_max_fall_speed: float = 20_000.0

@export_category("Timing")
## Opens the recovery challenge after a miss at or above this combo.
@export_range(1, 100, 1) var recovery_combo_threshold: int = 5
## Adds one mining target after each completed block of combo hits.
@export_range(1, 100, 1) var combo_hits_for_additional_target: int = 10
## Sets the target baseline restored after a failed streak.
@export_range(1, 16, 1) var starting_mining_target_count: int = 1
## Sets the main timing slider's unmodified horizontal speed.
@export_range(1.0, 5_000.0, 1.0) var mining_bar_speed: float = 500.0
## Sets the recovery slider's unmodified horizontal speed.
@export_range(1.0, 5_000.0, 1.0) var recovery_bar_speed: float = 1_250.0
## Sets the secondary recovery slider's unmodified horizontal speed.
@export_range(1.0, 5_000.0, 1.0) var second_recovery_bar_speed: float = 1_500.0
## Applies a fixed speed multiplier while the mining combo is active.
@export_range(0.1, 5.0, 0.05) var combo_speed_multiplier: float = 1.5
## Multiplies recovery speed after each successfully saved streak.
@export_range(0.1, 5.0, 0.05) var recovery_speed_multiplier: float = 1.2

@export_category("Encounter Progression")
## Complete production rules in order: level zero starts the run, and encounter
## index N applies level N + 1. Keep levels zero through nine populated. See
## res://resources/pickaxes/pickaxe_authoring.md before adding a pickaxe reward.
@export var progression_levels: Array[EncounterProgressionLevel] = []

@export_category("Combo Targets")
## Ordered target unlocks selected by combo. The first group must start at zero;
## later groups add their scenes at their inclusive minimum_combo.
@export var combo_target_groups: Array[ComboTargetGroup] = []

@export_category("Effects")
## Treats this combo as full strength for animation and hit feedback.
@export_range(1, 100, 1) var maximum_effect_combo: int = 20
## Combos that promote the run into its next escalation step. One music layer,
## one camera punch, and one gauge division exist per entry, so this array's
## length is how many steps the whole run escalates through. Kept here beside
## maximum_effect_combo and recovery_combo_threshold so the presentation systems
## and the timing bar read the same thresholds instead of each authoring a set.
@export var combo_tier_thresholds: Array[int] = [5, 10, 16]
## Caps cumulative pickaxe deltas so ten collected tools remain tunable.
@export_range(1.0, 10.0, 0.1) var maximum_stack_power_multiplier: float = 2.0
@export_range(1.0, 10.0, 0.1) var maximum_stack_width_multiplier: float = 2.0
@export_range(1.0, 10.0, 0.1) var maximum_stack_swing_speed_multiplier: float = 2.5
@export_range(1.0, 10.0, 0.1) var maximum_stack_debris_multiplier: float = 3.0
@export var use_secondary_recovery : bool = false

## Returns the practical coordinate ceiling for the otherwise endless mine.
func get_bottom_surface_row() -> int:
	return initial_surface_row + MAX_PLAYABLE_DEPTH


## Returns whether the authored combo-target ladder is complete and ordered.
func has_valid_combo_target_groups() -> bool:
	if (
		combo_target_groups.is_empty()
		or combo_target_groups[0] == null
		or combo_target_groups[0].minimum_combo != 0
	):
		return false
	var previous_minimum := -1
	for group: ComboTargetGroup in combo_target_groups:
		if (
			group == null
			or not group.is_valid()
			or group.minimum_combo <= previous_minimum
		):
			return false
		previous_minimum = group.minimum_combo
	return true


## Selects the last target group whose inclusive threshold has been reached.
func get_combo_target_group_index(combo: int) -> int:
	if not has_valid_combo_target_groups():
		return -1
	var selected_index := 0
	for group_index in range(1, combo_target_groups.size()):
		if combo < combo_target_groups[group_index].minimum_combo:
			break
		selected_index = group_index
	return selected_index


## Builds the deduplicated target pool unlocked through one group.
func get_combo_target_pool_through_group(
	group_index: int
) -> Array[PackedScene]:
	var target_pool: Array[PackedScene] = []
	if not has_valid_combo_target_groups() or group_index < 0:
		return target_pool
	var final_group_index := mini(
		group_index,
		combo_target_groups.size() - 1
	)
	for unlocked_group_index in range(final_group_index + 1):
		for target_scene: PackedScene in (
			combo_target_groups[unlocked_group_index].target_scenes
		):
			if target_scene not in target_pool:
				target_pool.append(target_scene)
	return target_pool
