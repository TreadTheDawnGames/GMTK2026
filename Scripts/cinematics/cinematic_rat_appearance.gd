class_name CinematicRatAppearance
extends Resource

## How it works:
## - One resource keeps a mouse's resting and impact art paired.
## - The procession assigns appearances by spawn index.
## - The actor swaps to strike_texture only during its strike clip.
## - Both textures must share the same canvas and registration.
## - Art may show one rat or a clump of several; depicted_rat_count says which,
##   so a crowd gets denser by drawing rather than by adding actors.
##
## Registration is baked into the PNG, because nothing assigning an appearance
## touches the sprite's offset: CinematicRatMiner.set_appearance swaps the
## texture and applies the shared appearance_scale, and the authored offset on
## rat_miner.tscn's ActorSprite is what puts a mouse's soles on the actor root
## and its body centre on the root's x. Any new drawing has to land on the same
## two marks by how its canvas is padded:
##
## - The single mice are the source art cropped to one shared 938x648 content
##   box, imported with process/size_limit 256. In that imported texture the
##   content's bottom edge sits 88.5 px below the canvas centre and its
##   horizontal centre 38.35 px right of it, and the sprite offset cancels
##   exactly those two numbers.
## - A drawing of another shape keeps those offsets by padding its canvas, not
##   by moving anything in the scene, and then by raising its own size_limit in
##   the same proportion as its canvas so the drawn rats stay the size the
##   single mice are. mouse_clump.png is 2264x1252 at size_limit 618 for that
##   reason - 618/2264 is 256/938. Change one of that pair without the other and
##   the crowd silently renders at the wrong scale or floating off the floor,
##   with no error anywhere.

@export var idle_texture: Texture2D
## Contact art. A clump may point this at its idle drawing: the actor still
## squashes, rotates and reports its strike, and only the pickaxes stop moving.
## A single rat near the camera should always have its own drawn contact frame.
@export var strike_texture: Texture2D
## How many rats this artwork shows.
##
## One actor carrying a clump of five costs one node, one animation and one
## strike, which is the only way the colony gets genuinely dense on web. Leave it
## at one for single-rat art. It changes nothing about how the actor behaves: it
## is what lets the colony report an honest rat count, and lets a designer see at
## a glance which slots hold clumps.
##
## The range reaches the follower pool's own 32-actor bound because a drawing can
## legitimately hold more rats than the old cap of twelve: mouse_clump.png draws
## two dozen.
@export_range(1, 32, 1) var depicted_rat_count: int = 1
