# Terrain Layering Guide

`TerrainManager` owns solid cells, depth, and encounter openings.
`TerrainLayerRenderer` turns those results into streamed art. Changing artwork
does not change where the player can stand or how much depth a hit earns.

## Replace terrain art

Edit `resources/mining/default_terrain_layer_profile.tres`.

- `Layer Tints` lists strata from the foreground surface to the deepest dirt.
- `Layer Fill Textures` accepts optional seamless textures in the same order.
- `Small Hole Masks` and `Big Hole Masks` use transparent areas as the
  opening made by a strike.
- `Layer Z Indices` keeps the foreground above the miner and lower strata
  behind the miner.

All layer arrays should describe the same number of strata. Fill textures are
sampled in continuous terrain coordinates, so chunk boundaries do not restart
the pattern.

## Strata dirt texture

Every stratum adds flat mottled dirt, sparse rounded rock inclusions, and deeper
sediment lines that stay continuous between streamed chunks. The default profile
moves from broad surface variance through tighter, denser compacted rock to a
dark back wall. Tune each layer's scale, detail color, variance, rock density,
and rock strength in the `Strata Dirt Texture` section of the layer profile.
Keep every array the same size as `Layer Tints`.

The shader is one simple stack: a shared world-space dirt mottle, one rounded
and independently rotated rock candidate per detail cell, then world-aligned
sediment lines that fade in with depth. Surface and subsoil stay dirt-led, layer
three deliberately spikes to dense fine gravel, and layer four returns to sparse
coarse bedrock. The shared mottle and bedding scales make those different
textures line up across exposed rims instead of restarting at each layer.

This is presentation-only, loop-free shader work: it creates no per-hit
allocations and does not change terrain cells, depth, or collision. Disable the
profile toggle to compare against the original flat strata.

## Author hole masks

Use a square transparent PNG. Opaque pixels preserve terrain and transparent
pixels define the organic opening. Keep transparent space fully enclosed by
the image so the renderer can measure and scale it.

The foreground mask is expanded most, and each deeper mask is expanded less.
Each layer is also offset from the impact center. This reveals uneven circular
rims instead of one repeated silhouette. Overlapping impacts are combined in
the persistent chunk masks rather than drawn as separate decals.

Normal hits clear the pale and tan strata but retain orange as the decorative
tunnel backdrop. Hits large enough to select the big-hole mask family also
clear orange and reveal the solid brown back wall. This intentionally leaves
one colored backdrop over logically open cells; it never changes collision or
depth. Press F3 to overlay the logical openings when checking visual parity.

## Tuning

- `Rim Width` controls the visible distance between strata.
- `Core Hole Padding` keeps the central fall path visually open.
- `Big Hole Minimum Size` selects the large mask family and controls when the
  brown back wall may appear.
- `Keep Back Layer Solid` uses the deepest color as a back wall.
- `Mask Pixels Per Cell` controls edge detail and upload cost. The default of
  four keeps normal impacts inexpensive while retaining smooth silhouettes.
- `Resized Stamp Cache Limit` on `TerrainLayerRenderer` bounds reusable impact
  images. Repeated combo sizes avoid resizing and allocating the same masks,
  while the 12-entry default limits browser memory.

Chunks outside the camera range are released. Their impact records remain and
are replayed when the player returns to that depth.

## Mining camera styles

`MiningConfig.Mining Camera Style` provides two presentations over the same
gravity-driven miner position:

- `Smooth Follow` eases continuously behind the falling miner, then closes the
  remaining lag at the bounded landing recenter speed.
- `Chunk Snap` holds the current terrain-chunk page while the miner moves down
  it. Crossing half of a 64-row chunk flips the view to the next fixed page.

Changing camera style never changes earned depth, collision, fall gravity, or
landing events. `Chunk Height Cells` is the page size for chunk snapping, so
streaming and camera boundaries cannot drift apart.

## Branching lightning

The Stone Pickaxe adds a jagged central path and shorter randomized side
branches beneath its normal impact. Logical paths are sent to the renderer as
one batch. Each branch receives a narrow layered opening, while every affected
chunk uploads its changed masks only once.

Lightning depth, branch count, and branch length are Inspector settings on the
Stone Pickaxe resource. The terrain manager owns which cells break; the layer
renderer owns only their organic presentation.

## Impact smoke

`MiningImpactSmoke` owns one bonded field with a bounded set of internal support
volumes. Each hit adds a support where its smoke entered instead of collapsing
all smoke into one center. Neighboring supports retain useful spacing, pull
toward one another when stretched, and overlap without becoming one simulated
body.

New smoke begins around the upper edge of the latest foreground-layer opening,
then steps into the cleared core if an organic rim extends over logically solid
dirt. Each support measures the solid terrain to its left and right, shifts
toward the open side, and stretches close to both walls. One shared shader
softens and rolls the overlapping supports in a single web-safe draw call. The
effect draws above the retained tunnel backdrop but behind the two upper rim
strata, so ordinary hits cannot hide it while its outline still respects the
layered tunnel.
`Impact Smoke Color` on the terrain profile supplies a lighter earth-tone value,
keeping dust in the same authored palette while separating it from the dark
tunnel back wall.

As the cloud rises, it receives a small pull toward the centered entrance and
uses a compressed collision core that can pass through the starting tunnel.
Blocked movement is removed only along the wall normal, allowing the remaining
motion to glide along chamber and tunnel edges instead of bouncing away.
Buoyancy is the only vertical force; mining wind scatters smoke sideways but
can never pull it downward. Every support uses the same solid smoke color.
The cloud is removed after its full outline clears the top of the normal
gameplay view. Its terrain-space simulation and buoyancy continue while the
camera reviews earlier terrain, letting the player scroll up and follow it.
Cleanup pauses while the camera is reviewing or returning, so scrolling cannot
consume terrain-bound smoke.

## Encounter-room transitions

Each authored encounter chamber keeps its rectangular logical opening so
landing and collision stay predictable. `TerrainLayerRenderer` precomputes a
stable set of overlapping organic circles across the chamber ceiling, making
the layered art open unevenly into the room.

`Chamber Circle Count`, radius, and jitter are Inspector settings on the
renderer. Placement is derived from encounter depth, so returning to a room
reconstructs the same silhouette instead of rerolling it.

## Review earlier terrain

Mouse-wheel up detaches the view from the miner and scrolls toward previously
visited terrain. Review movement is clamped between the starting surface and
the miner's current depth, so the player can always return to the top without
revealing unvisited ground.

Mining pauses and the timing bar hides while the view is detached. The
down-arrow button starts an accelerating fall to the miner. Mining becomes
available again only after the view reaches the miner's current depth. The
miner is drawn at their true depth during review, so they move below the
viewport while scrolling up and return into view as the camera catches them.

Review step size, scroll speed, return gravity, and maximum fall speed are
Inspector settings on `MiningConfig`. Terrain chunks may unload during a long
review, but their saved impact stamps are reapplied when those chunks return.
