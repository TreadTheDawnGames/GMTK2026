class_name CinematicRatEntryPoint
extends Marker2D

## How it works:
## - This marker authors one reusable follower entrance into the rat cave.
## - Behind Start Offset places the hidden actor on the backing side.
## - Requires Breach opens this marker once through the production terrain mask,
##   then the mouse pops out of that hole and falls to the floor under gravity.
## - A marker that needs no breach is a floor-level route the mouse runs in on.
## - Emergence Travel X is how far out of the hole it carries while falling.
## - The sequence owns actors, terrain calls, draw order, and cleanup.

@export var requires_breach: bool = true
@export var behind_start_offset: Vector2 = Vector2(-48.0, -18.0)
## Breaching entries: horizontal travel out of the hole during the fall.
## Open entries: horizontal travel from the offscreen start to the run's end.
@export var emergence_travel_x: float = 32.0
