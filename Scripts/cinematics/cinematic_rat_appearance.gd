class_name CinematicRatAppearance
extends Resource

## How it works:
## - One resource keeps a mouse's resting and impact art paired.
## - The procession assigns appearances by spawn index.
## - The actor swaps to strike_texture only during its strike clip.
## - Both textures must share the same canvas and registration.
## - Art may show one rat or a clump of several; depicted_rat_count says which,
##   so a crowd gets denser by drawing rather than by adding actors.

@export var idle_texture: Texture2D
@export var strike_texture: Texture2D
## How many rats this artwork shows.
##
## One actor carrying a clump of five costs one node, one animation and one
## strike, which is the only way the colony gets genuinely dense on web. Leave it
## at one for single-rat art. It changes nothing about how the actor behaves: it
## is what lets the colony report an honest rat count, and lets a designer see at
## a glance which slots hold clumps.
@export_range(1, 12, 1) var depicted_rat_count: int = 1
