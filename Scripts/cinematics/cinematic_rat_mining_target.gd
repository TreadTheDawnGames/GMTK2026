class_name CinematicRatMiningTarget
extends Marker2D

## How it works:
## - Each authored marker is one mouse root destination.
## - Floor Offset moves that destination above or below sampled layer five.
## - Jump Height makes the incoming mouse arc across the miner.
## - Front Of Miner selects the destination's depth plane.
## - Strike Count controls how many reversible terrain indents it requests.

@export_category("Placement")
@export_range(-160.0, 80.0, 1.0) var floor_offset_y: float = 0.0
@export_range(0.0, 180.0, 1.0) var jump_height: float = 0.0
@export var front_of_miner: bool = true

@export_category("Mining")
@export_range(1, 8, 1) var strike_count: int = 3
