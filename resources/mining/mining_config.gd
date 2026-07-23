class_name MiningConfig
extends Resource

## Shared, inspector-editable tuning for terrain, descent, and hit feedback.
## Values use logical terrain cells unless their names explicitly say pixels.

@export_category("Terrain")
@export_range(16, 512, 1) var terrain_width_cells: int = 128
@export_range(16, 256, 1) var chunk_height_cells: int = 64
@export_range(1, 32, 1) var logical_pixel_scale: int = 8
@export_range(1, 512, 1) var initial_surface_row: int = 38
# Six cells at the default scale gives the first hit a 48 px radius.
@export_range(1, 64, 1) var base_chip_radius_cells: int = 6
@export_range(0, 16, 1) var combo_chip_radius_cells_per_step: int = 1
@export var global_seed: int = 2026
@export_range(16, 1_024, 1) var depth_band_height_rows: int = 128
@export var terrain_color: Color = Color("633c31")
@export var terrain_accent_color: Color = Color("75483a")

@export_category("View")
@export var terrain_screen_center_x: float = 576.0
@export var mining_face_screen_y: float = 340.0
@export_range(0, 4, 1) var preload_chunks_below: int = 1
@export_range(1.0, 30.0, 0.5) var view_follow_speed: float = 12.0

@export_category("Effects")
@export_range(1, 100, 1) var maximum_effect_combo: int = 20
