class_name TerrainDepthBand
extends Resource

## Assigns one terrain art profile to a depth range selected per chunk.

@export var display_name: String = "Topsoil"
@export_range(0, 1_000_000, 1) var start_depth_px: int = 0
@export_range(0, 1_000_000, 1) var end_depth_px: int = 100_000
@export var art_profile: TerrainArtProfile


## Includes the start depth and excludes the next band's boundary.
func contains_depth(depth_px: int) -> bool:
	return (
		depth_px >= start_depth_px
		and depth_px < end_depth_px
	)
