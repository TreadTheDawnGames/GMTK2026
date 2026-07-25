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
Each layer is also offset from the impact center, and takes its own mirror,
quarter-turn, and small size jitter derived from the hit's seed, so a strike
leaves four differently shaped rims instead of one silhouette traced four times
at shrinking scale. Nesting is unaffected: the authored cavity is normalised
into each layer's opening rect whatever its orientation, so a deeper opening
cannot escape the shallower one in front of it. The jitter is seeded from the
stored stamp, so streaming a chunk out and back redraws identical rims.
Overlapping impacts are combined in the persistent chunk masks rather than
drawn as separate decals.

Dark strokes drawn in a mask are treated separately from its cavity. Only the
strokes hugging the cavity are kept, within `Fracture Rim Reach Px`; loose
scribbles standing further out in the rock are dropped, because they read as
marks lying on the dirt rather than as a broken edge. `Fracture Line Layer
Depth` then limits how many strata print those strokes at all — one inked rim
reads as a break, four stacked copies read as concentric worms.

Normal hits clear the pale and tan strata but retain orange as the decorative
tunnel backdrop. Hits large enough to select the big-hole mask family also
clear orange and reveal the solid brown back wall. This intentionally leaves
one colored backdrop over logically open cells; it never changes collision or
depth. Press F3 to overlay the logical openings when checking visual parity.

## Tuning

- `Rim Width` controls the visible distance between strata.
- `Fracture Line Layer Depth`, `Fracture Line Depth Falloff`, and
  `Fracture Rim Reach Px` control how much authored crack art survives, per the
  section above. `Fracture Shade Color` multiplies the rock under a stroke
  instead of printing neutral pixels over it, so a crack keeps the stratum's hue.
- `Dirt Shade Steps` quantises the dirt variation into flat bands to match the
  hard shading steps the characters are drawn with. Zero restores the original
  continuous gradient.
- `Sharpen Mask Edges` re-thresholds the filtered mask against its own
  screen-space gradient. The mask is authored below world resolution and drawn
  with linear filtering, so without this every cut arrives as a wide soft ramp.
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

## Rat-cave entry points

`Scenes/cinematics/layer_breakthrough_sequence.tscn` keeps follower entrances
under `DestinationStage/ActorMarkers/RatEntryPoints`. Followers cycle those
direct children in scene order. `OpenSideEntry` is the existing left opening;
the three ceiling markers each punch one reversible small indent through the
production terrain mask at the actor's existing strike-contact frame and reuse
it for later followers. That same contact emits the shared impact event, keeping
the mask change, smoke, particles, and shake synchronized.

`Scenes/cinematics/layer_cutscene_environment.tscn` owns the reusable tunnel
stage. The normal gameplay fall is the entrance; the scene contains no
synthetic walk or scripted-fall transition. Source indices `0..3` remain
gameplay strata. Source index `4` and every deeper layer belong to the
extensible cutscene destination/background stack.

`PassageBounds` controls the opening held behind the miner before dialogue.
Runtime centers its local `TopLeft`/`BottomRight` markers on the miner focus.
`DestinationStage/TunnelBounds` expands that same reversible source-4
snapshot after landing. `StageFloor`,
`ActorMarkers`, and `ActionMarkers` are then grounded from the production mask.
At least one deeper source layer must remain untouched as the visible backing.

Place each breach marker at the center of the intended opening. Its
`Behind Start Offset` must put the whole actor on the solid side, while its
`Inside Offset` must put the actor root wholly inside the horizontal cave. The
two offsets should form a readable path through the marker. Actors use the
authored draw order between the promoted foreground and its backing until they
reach the inside endpoint; only then do they join a front or back mining lane.
For the current actor rig, `Behind Start Offset` `(-48, -18)` aligns its
`StrikeAnchor` exactly with the marker while the foreground still occludes it.

Set `Requires Breach` to false only for a route that is already visibly open.
The shipped four markers spend three of the renderer's bounded cinematic-indent
budget. Adding another breach requires rechecking that web exports still have
enough indent capacity for every right-wall exit lane.

`resources/cinematics/rat_appearance_*.tres` pairs every mouse color's idle and
strike PNG so the sequence cannot mix colors during a hit. `Rat Appearances` on
the breakthrough sequence cycles brown, grey, red, and white by spawn index.
The actor switches to the paired strike frame during its existing contact clip;
motion, terrain damage, and effects still use the shared choreography. Mouse
imports are capped at 512 pixels because their authored canvases are much larger
than their on-screen size, keeping web texture memory bounded.

The tunnel stage does not retint source indices `0..3` while gameplay is
visible. After the real fall, they are hidden together behind the focused iris.
Only source index `4` and deeper cutscene strata receive `Deep Layer Palette`
colors in the destination room. Add new encounter depth behind index `4`; do
not increase the gameplay layer count unless gameplay gains another real
terrain stratum.

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

The Stone Pickaxe cracks the dirt outward from the actual left and right edges
of its normal impact. Because the origin uses the resolved tunnel half-width,
larger combo blasts never leave disconnected lightning marks beneath the miner.
Low combos make one short crack on a random side. Higher combos add alternating
left/right paths, increase their lateral reach and shallow vertical wander, and
widen their dark fracture strokes. The renderer connects the path cells into a
sharp line instead of repeating the full hole stamp. The inner crack cuts the
first two strata and scores the third dark enough to remain readable through
the opening. Its weakening outer section cuts only the foreground stratum, so
the end reads as a fading ground fracture instead of another full tunnel.

Maximum crack count, length, and depth are Inspector settings on the pickaxe
definition. Logical paths are sent to the renderer as one batch, and every
affected chunk uploads its masks only once. The terrain manager owns which cells
break; each persistent renderer stamp stores the combo-scaled stroke width and
two-layer reach so streaming a chunk out and back cannot resize an old crack.
Browser exports cap the maximum at three twelve-cell cracks. The normal
`impact_resolved` signal still produces the bounded dirt-particle burst, smoke,
shake, and dig number once for the complete hit rather than once per crack.

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

The encounter's `Depth From Surface` is the room's solid floor. Terrain opens
the configured chamber rows directly above it, but leaves the ceiling above
that chamber mineable. A normal hit breaks through that ceiling, the miner
falls through the authored opening, and only the landing on that floor starts
the cutscene. Elapsed run time never moves or starts an encounter.

New tunnel cutscenes do not need terrain code. Duplicate a
`DepthCharacterEncounter` resource, set its depth and story resources, and add
it to the ordered `Encounters` array in
`resources/encounters/depth_encounter_config.tres`. An optional
`CharacterEncounterStage` adds custom movement and line cues; without one, the
same physical landing opens the conversation directly.

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

## Strata edge depth

`TerrainLayerProfile` exposes a **Strata Edge Depth** group that bevels every
stratum against its own opening, so exposed rims read as one connected rock face
receding backward instead of flat stacked cutouts.

- `edge_shade_world_pixels` is how far the contact shadow reaches into the rock,
  authored in world pixels and converted through `chunk_world_size`, so it is
  independent of mask resolution.
- `edge_shade_strength` is the darkening at a cut edge. Deeper strata scale past
  it automatically, so rims further back sit further back.
- `edge_light_strength` brightens the upward-facing lip only, matching light
  from above, which is what gives each rim its readable thickness.
- `layer_edge_shading_enabled` turns the whole thing off in one place.

The shader finds the edge with four mask taps per fragment inside `fragment()`
and passes them to `apply_edge_shading()`. Godot only exposes `TEXTURE` inside
`fragment()`, so the taps must stay there; the helper takes the sampled
neighbours as a `vec4`. Benchmark with `local_tests/benchmark_layered_terrain.gd`
before and after changing the reach, since this runs on the hot render path.

## Surface dressing

Grass and the packed crust are part of the **foreground stratum**, not an
overlay. `TerrainLayerProfile`'s **Surface Dressing** group authors them, and
`TerrainLayerRenderer` enables them for layer zero only.

The reason is that the miner breaks the grass first. An overlay drawn on top of
terrain cannot read the dug mask, so it bridges straight across a fresh hole. By
growing grass out of layer one's own top edge, a mined opening removes the grass
with the ground, for free and with no extra state.

- `surface_band_world_px` limits grass to the original ground line, so ledges
  deep underground stay bare rock.
- `grass_texture` is a horizontal atlas of clumps cut from the artist's sheet,
  every clump bottom-aligned in its own cell. That alignment is the whole trick:
  the strip maps a cell's bottom edge onto the ground line, so a blade can never
  start mid-air. Each cell along the ground picks a clump by hash and jitters it
  inside the cell, and the clump's own transparent margin becomes the gap.
- `grass_height_world_px`, `grass_cell_world_px` (spacing) and `grass_cell_aspect`
  size and space the tufts. Keep the aspect matched to the atlas cell or clumps
  stretch.
- The atlas is **pre-scaled** to roughly display size (22x48 cells) and its blade
  colour is **bled into the transparent margin** before scaling. Both matter: at
  the source 217x471 the minification is about 24x, which aliases thin blades
  into dashes, and linear filtering against transparent black muddies the green.
  If the sheet is redrawn, rebuild the atlas the same way rather than pointing
  the profile at the raw art.
- `crust_depth_world_px` / `crust_color` / `crust_strength` tint the exposed top
  of the surface as packed earth. This is a tint on solid pixels, so it costs
  nothing extra and is carved by digging like everything else.

Godot will not let a user function take the built-in `TEXTURE` sampler, so the
grass helpers stay pure and the one mask tap is done inside `fragment()`. Keep
it that way; passing `TEXTURE` into a helper fails at shader compile with a
`custom_samplers` error rather than a readable message.

## Gem outcrops

`GemOutcropField` (`Scripts/mining/gem_outcrop_field.gd`) rarely leaves a drawn
crystal jutting out of a stratum a hit just cut through. It is presentation
only: nothing reads it back, and it never touches cells, depth, or collision.

It builds one child **shelf** per stratum a hit can expose, each carrying that
stratum's `z_index`. Because the field sits after `TerrainLayerRenderer` in the
scene and Godot draws equal-z siblings in tree order, a crystal on shelf N draws
just in front of layer N and **behind** everything shallower. That is what makes
a crystal look embedded: its base is sunk below the covering stratum's rim by
`Buried Fraction`, so that stratum's rock hides the buried end and only the tip
juts out.

Placement is deliberately narrow, because every relaxation of it produced a
crystal that looked wrong:

- Only the **bottom row** of a hit is used. A cell higher up also has drawn rock
  beneath it, but that rock is the bottom of the whole opening, far enough below
  to be an unrelated rim.
- The base is seated on the drawn rim via
  `TerrainLayerRenderer.get_layer_opening_floor_support_screen_y` — the same
  query the miner lands on — not on the logical cell floor, which sits higher
  because the drawn opening is grown past the cells a hit removed.
- If no rim can be reached, the roll is **dropped** rather than placed. An
  unseated crystal stands in mid-air. Crystals are rare enough that losing a
  roll costs nothing; `Floor Seating Attempts` bounds the mask walks first.
- A crystal keeps the solid cell it grew from and is dropped when that cell is
  later mined, so one can never be left hanging in an opened tunnel.

Colour comes from the stratum plus the run's depth band, with a
`Variant Drift Chance` of taking a neighbouring colour, so a stratum reads as a
signature rather than a rule and all five drawn colours come into play across a
run. `Depth Shade Color` multiplies deeper crystals toward the muddy shadow of
the rock around them instead of letting them glow out of the tunnel.

`Assets/Props/gem_crystals.png` is a horizontal atlas of the artist's one drawn
crystal, each frame the same drawing with its facets rotated in hue and scaled in
saturation; value and the black outline are untouched, so the drawn shading and
inked silhouette survive. Mipmaps are on, because the frame is 140px tall and
displays around 30px. If the crystal is redrawn, rebuild the atlas the same way
rather than pointing the field at the raw art.

Cutscenes call `place_gem(terrain_position, surface_normal, layer_index,
variant_index, world_height)` to stand an authored crystal anywhere they frame.
That path skips the seating test on purpose: a cutscene draws its own ground, so
the caller owns the placement. Pass a `layer_index` to choose which depth it is
covered at; a negative variant or a zero height takes the field's own choice.
