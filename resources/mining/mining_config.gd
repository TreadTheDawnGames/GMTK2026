class_name MiningConfig
extends Resource

## Shared, inspector-editable tuning for terrain, descent, and hit feedback.
## Gameplay depth is independent from terrain rendering size.
## One descended terrain row equals one gameplay depth.

@export_category("Terrain")
@export_range(16, 512, 1) var terrain_width_cells: int = 128
@export_range(16, 256, 1) var chunk_height_cells: int = 64
## Controls how large one terrain cell appears on screen.
@export_range(1, 32, 1) var terrain_cell_size_px: int = 8
@export_range(1, 512, 1) var initial_surface_row: int = 38
@export_range(1, 1_000_000, 1) var total_run_depth: int = 100_000
## Terrain rows cleared by a normal starting hit.
@export_range(1, 64, 1) var base_mine_depth_rows: int = 6
@export_range(0, 16, 1) var combo_mine_depth_rows_per_step: int = 1
## Three cells on each side make a seven-cell-wide starting tunnel.
@export_range(0, 32, 1) var base_tunnel_half_width_cells: int = 3
@export_range(0, 8, 1) var combo_tunnel_half_width_cells_per_step: int = 1
@export var global_seed: int = 2026
@export_range(16, 1_024, 1) var depth_band_height_rows: int = 128
@export var terrain_color: Color = Color("633c31")
@export var terrain_accent_color: Color = Color("75483a")
@export var ore_definitions: Array[OreDefinition] = []

@export_category("View")
@export var terrain_screen_center_x: float = 576.0
@export var mining_face_screen_y: float = 340.0
@export_range(0, 4, 1) var preload_chunks_below: int = 1
@export_range(1.0, 30.0, 0.5) var view_follow_speed: float = 12.0

@export_category("Effects")
## Treats this combo as full strength for animation and hit feedback.
@export_range(1, 100, 1) var maximum_effect_combo: int = 20


## Returns the final terrain row beneath the player's feet.
func get_bottom_surface_row() -> int:
	return initial_surface_row + total_run_depth
