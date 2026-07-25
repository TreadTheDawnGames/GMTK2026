class_name CinematicRatAppearance
extends Resource

## How it works:
## - One resource keeps a mouse's resting and impact art paired.
## - The procession assigns appearances by spawn index.
## - The actor swaps to strike_texture only during its strike clip.
## - Both textures must share the same canvas and registration.

@export var idle_texture: Texture2D
@export var strike_texture: Texture2D
