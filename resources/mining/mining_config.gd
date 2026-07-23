class_name MiningConfig
extends Resource

## Shared, inspector-editable tuning for terrain, descent, and hit feedback.
## One descended terrain row equals one gameplay depth.

enum MiningCameraStyle {
	SMOOTH_FOLLOW,
	CHUNK_SNAP,
}

@export_category("Terrain")
@export_range(16, 512, 1) var terrain_width_cells: int = 128
@export_range(16, 256, 1) var chunk_height_cells: int = 64
## Sets the world-space size of one gameplay terrain cell.
@export_range(1, 32, 1) var terrain_cell_world_size: int = 8
@export_range(1, 512, 1) var initial_surface_row: int = 38
@export_range(1, 1_000_000, 1) var total_run_depth: int = 100_000
## Terrain rows cleared by a normal starting hit.
@export_range(1, 64, 1) var base_mine_depth_rows: int = 6
@export_range(0, 16, 1) var combo_mine_depth_rows_per_step: int = 1
## Three cells on each side make a seven-cell-wide starting tunnel.
@export_range(0, 32, 1) var base_tunnel_half_width_cells: int = 3
@export_range(0, 8, 1) var combo_tunnel_half_width_cells_per_step: int = 1

@export_category("View")
@export var terrain_screen_center_x: float = 576.0
@export var mining_face_screen_y: float = 340.0
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
## Recenters the view after landing, in terrain rows per second.
@export_range(10.0, 2_000.0, 10.0) var landing_recenter_speed: float = 60.0
## Terrain rows added to the review target by one mouse-wheel step.
@export_range(10, 10_000, 10) var review_scroll_rows_per_step: int = 1_000
## Keeps a single wheel step readable before long-distance review accelerates.
@export_range(100.0, 6_000.0, 100.0) var review_scroll_close_speed: float = 600.0
## Reaches full review speed only when several wheel steps are queued.
@export_range(1_000.0, 50_000.0, 1_000.0) var review_scroll_acceleration_distance: float = 10_000.0
@export_range(100.0, 20_000.0, 100.0) var review_scroll_speed: float = 6_000.0
@export_range(100.0, 50_000.0, 100.0) var return_fall_gravity: float = 8_000.0
@export_range(100.0, 50_000.0, 100.0) var return_max_fall_speed: float = 20_000.0

@export_category("Effects")
## Treats this combo as full strength for animation and hit feedback.
@export_range(1, 100, 1) var maximum_effect_combo: int = 20


## Returns the final terrain row beneath the player's feet.
func get_bottom_surface_row() -> int:
	return initial_surface_row + total_run_depth
