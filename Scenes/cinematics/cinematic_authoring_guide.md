# Cinematic Authoring Guide

The mining scene has three concrete cinematic forms: the surface arrival that
opens every run, framed character conversations, and the one-time layer
breakthrough. Story text remains in `DialogueConversation` resources. Movement,
layer timing, rat count, and stage composition remain editable in Godot scenes.

## Surface arrival (run intro)

Open `Scenes/cinematics/arrival_intro.tscn`.

The run opens on black. `GameMainMenu` fades the menu into `StartFadeOverlay`
before changing scenes, and `CinematicFrame` starts with `starts_blacked_out`,
its two letterbox bars meeting in the middle. `RunIntroController` then calls
`reveal_from_blackout()`, which splits that same black apart from the centre
until the bars settle on `bar_height_ratio`. Keep `StartFadeOverlay`'s colour
matched to the bars or the handover will flash.

Beats, in order: blackout splits open, hold, the bus drives in **right to left**
and settles right on top of the stop, its door opens, the miner gets off out of
sight behind it, the bus pulls away left and its trailing edge **wipes him into
view**, and he walks left to his dig spot at centre screen. He turns to face the
stop before anyone speaks. Every duration is an Inspector property on the
sequence root.

The reveal depends on draw order: `Bus` is `z_index 5`, in front of the whole
cast, and parked at `BusStopAnchor` it covers the shelter completely. The miner
is placed at `MinerDropOffAnchor` *while still hidden*, so the departure
uncovers someone already standing there rather than popping him in afterwards.
`miner_reveal_hold_seconds` is how long the bus gets to slide before he sets
off; too short and he walks out of a solid bus.

The bus art is mirrored with a negative `scale.x` to face left, and its sprite
offset is mirrored with it so the body stays centred on the node. Wheel-shine
UVs are texture-space and unaffected, but the spin direction is corrected in
script from `sign(scale.x)`.

- Props are authored in viewport pixels against a ground line at **y = 262**.
  The node re-anchors itself to the live ground line every frame, so the stop
  stays planted and leaves the shot only as the miner actually descends.
- The letterbox top bar covers the first **91 px**. Keep every prop's art below
  that, and check `sun_screen_position` on `SurfacePresentation` against it too.
- The bus, the station, and the door each expose a `Sprite2D` art slot
  (`BusSprite`, `DoorSprite`, `StationSprite`). Assign a transparent PNG whose
  base rests on the node's `y = 0`, then hide that prop's `StandIn*` children.
  The stand-ins deliberately use the project's black-outline/white-fill
  placeholder convention so they can never be mistaken for final art.
- `BusArrivalAnchor` (offscreen right) and `BusExitAnchor` (offscreen left) use
  only their x coordinate. `BusStopAnchor` uses both: x is the stop, y is the
  ground the suspension dip returns to. `MinerDropOffAnchor` must sit inside the
  parked bus's span or the wipe has nothing to uncover.
- The miner moves only through `MinerRig`'s shared cinematic visual override.
  His gameplay root, `RunState`, and mining depth are never touched, and
  `RunIntroController` hands grounding back with `show_intact_floor_grounding()`
  when control returns.
- The attendant is a `CharacterPresenter` driven by `attendant_appearance` on
  `RunIntroController`. It is placed with the stand-in's **feet on the ground**,
  because the current appearance is a standing 256 px frame: seating it on the
  bench would float it and push its head under the top bar. When seated art
  arrives, move the node to `AttendantSeatAnchor` and re-check the head.
- Nothing fades out at the end. Only the letterbox and the HUD change when
  mining begins.

### Ambient attendant pickup

`attendant_pickup_delay_seconds` after control is handed back, a bus returns,
the attendant boards, and it leaves — so a player who scrolls back up finds the
bench empty and the surface changed. It parks at
`AttendantPickupStopAnchor`, which is placed so the bus door lines up with the
stop while the bus stays behind it in draw order, reading as the road behind the
bench. Clearing that anchor, or unticking `attendant_pickup_enabled`, disables
the epilogue without affecting the intro.

This runs entirely outside the player's gates and must stay that way: it never
claims `MiningCinematicFlow`, never touches `MinerRig`, never opens dialogue,
and never pauses the tree. The integration suite asserts all of that while the
pickup plays, so a player who never scrolls up is unaffected by it.

Run `local_tests/capture_arrival_intro.gd` with `--rendering-driver opengl3` to
render every beat to PNG and check the framing by eye.

### Layering rule: the cast stands behind the ground they stand in

During play the miner is on layer two and **terrain layer one draws in front of
him** (`layer_z_indices` starts at `2`; `MinerRig` is `z_index 1`). That is what
makes his legs read as being down in the dig rather than pasted on top of it.

Every surface has to obey the same rule, or the surface looks like a different
game from the mining:

- `SurfaceGround` (grass and gravel) is `z_index 3`, in front of the whole cast.
  Everyone stands behind the grass at the surface, exactly as everyone stands
  behind layer one underground.
- The arrival's `miner_settle_draw_order` is `1` — his gameplay value. The intro
  hands that back on the settle beat, while he is visibly planting his feet, so
  the foreground closing over his legs reads as intentional. Handing it back
  after the shot ends instead makes his legs clip away in a single frame.
- A cinematic may lift the miner above the strata (`miner_cinematic_draw_order`)
  while it owns him, but it must return him to the gameplay value as part of a
  visible motion, never as a bare assignment once the frame is already open.

## Surface daylight and ground

`SurfacePresentation` (under `MiningScene/Systems`) is the single source for the
two values the surface shaders share: where the original ground line sits on
screen, and where the sun sits. It reads the ground line back through
`TerrainManager`'s own conversion, so daylight, the dressed ground, and the dirt
can never disagree, and all of it scrolls away as the miner descends.

- `SurfaceSky` (`z_index -10`) paints the gradient and the sun above the line
  and collapses to the underground void colour below it, so descending past the
  intro looks exactly as it did before.
- Grass and crust are **not** here. They live in `terrain_layer.gdshader` and
  belong to the foreground stratum itself, so a mined opening takes them away
  with the ground it removed. See the terrain layering guide. There used to be a
  `SurfaceGround` overlay rect; it was deleted because a fullscreen rect cannot
  read the dug mask and so drew grass straight across a fresh hole.
- `SunlightWash` (`z_index 6`) adds an additive warm pool under the sun, above
  the cast, so sunlight touches the characters too.

There are no `Light2D` nodes. This is deliberate: engine lighting washes out the
black linework baked into the character art, and the GL Compatibility web export
is the primary target.

## Authoring tools

Cinematic scenes are authored in viewport pixels but open on an empty canvas, so
anchors end up placed blind against a field of anonymous crosses. Two aids fix
that; neither is part of the game.

### Seeing the terrain in the editor

Open `layer_cutscene_environment.tscn` or `arrival_intro.tscn` and the real
terrain is already there. There is no drawn approximation to drift: the
`EditorTerrainPreview` branch holds a production `TerrainManager` and
`TerrainLayerRenderer`, so the editor runs the same renderer, shader, profile
colours and hole masks the game runs. If the terrain looks wrong in the editor,
it is wrong in the game.

`TerrainLayerRenderer` is `@tool`, but editor drawing is opt-in per instance
through `Preview In Editor`. Only these preview instances set it, so opening
the mining scene stays instant.

On `EditorTerrainPreview`:

- `Preview Depth Rows` is how far below the surface this cutscene plays. The
  breakthrough stage uses 400, the arrival uses 0 so it sits on the surface
  with its grass and crust.
- `Preview Combo` is the combo the test hits resolve at. Above the renderer's
  `Deepest Layer Combo Threshold` the openings expose the deep backdrop, which
  is what a breakthrough-qualifying hit does.

### Breaking the terrain in the editor

Every `Marker2D` under `EditorTerrainPreview/TestImpacts` is dug with a real
`dig_tunnel` call against real cells — not a hole drawn to look like one. Drag
one and the opening follows it live; duplicate it for more openings; delete it
and the rock heals. Moving a marker rebuilds from intact terrain, so openings
never pile up behind you.

The whole branch sits at `z_index -100` and **frees itself the moment the game
runs**, so no second terrain stack ever reaches a player. That is asserted by
`local_tests/verify_cutscene_terrain_preview.gd`. Nothing may read from it at
runtime; it owns no state.

Run `local_tests/capture_cutscene_terrain_preview.gd` with
`--rendering-driver opengl3` to render the preview to PNG and check it by eye
without opening a Godot window.

### Playing one beat in isolation

Open `Scenes/cinematics/cinematic_preview.tscn` and run it (F6). It boots the
real mining scene and jumps straight to a beat, so a sequence can be watched end
to end without playing up to its trigger:

- `1` surface arrival, `2` layer breakthrough, `3` depth encounter
- `R` replays the current beat from a freshly rebuilt scene
- `Esc` quits

It only drives triggers — it arms the real controller and feeds it a qualifying
hit rather than faking a sequence's internals. That is deliberate: if a beat
misbehaves in the preview it misbehaves in the game, so the harness can never
give a false pass.

## Framed conversations

`DialogueDirector` owns the letterbox and the single in-universe bottom
dialogue box. Dialogue advancement and story resources remain independent from
the box presentation.

Every visible speaker needs a `SpeechReaction` targeting only their visual
root. The miner keeps a separate `CinematicFocusAnchor` for the breakthrough
iris; dialogue no longer draws or registers speaker anchors. Do not connect
dialogue signals in the scene editor; cross-system routes belong in
`Scripts/mining/mining_scene_wiring.gd`.

Edit character entrances, departures, positions, and appearance resources in
their existing encounter scene or resource. `MiningCinematicFlow` is the sole
owner of timing-window visibility, queued-swing gating, and encounter-camera
focus. A sequence must claim it before starting and release the same named
owner only after its last visual has restored.

## Layer breakthrough

Open `Scenes/cinematics/layer_cutscene_environment.tscn` for the reusable
tunnel stage. Open
`Scenes/cinematics/layer_breakthrough_sequence.tscn` only for the concrete
mouse encounter layered on top of that environment.

- The qualifying hit's regular terrain stamp is the entry point between the
  first layers. Cinematic expansion recenters that retained stamp behind the
  miner horizontally, raises its visible mask so the miner reads at bottom
  center, and adds symmetric side clearance; it does not draw a second portal.
- `LayerCutsceneEnvironment` owns reversible miner/terrain presentation,
  stage opening, floor grounding, and restoration. It emits
  `stage_ready`, `restored`, or `failed`; the concrete sequence still owns
  story beats, actors, and dialogue.
- A concrete coordinator calls `prepare_entrance_impact()` synchronously when
  the qualifying hit resolves. This expands and reserves that exact stamp
  before letterboxing; cancelling before landing restores its original mask,
  geometry, and chunk history.
- On physical landing the coordinator calls `prepare_environment()`. This
  commits the already-prepared opening without stamping again. After the
  discovery beat, `open_environment_stage()` promotes the destination
  immediately behind the focused iris. Finish with
  `restore_environment()` or interrupt with `cancel_environment()`.
- The normal gameplay fall is the only entrance motion. The environment has no
  walk-through-layers mode, scripted second fall, or per-layer pass nodes.
- Source indices `0..3` remain gameplay strata. Source index `4` is promoted
  as the first cutscene destination, and one deeper stratum stays untouched as
  the visible backing.
- `PassageBounds/TopLeft` and `BottomRight` author the centered reversible
  source-4 passage. Runtime moves the `PassageBounds` root to the miner focus;
  the default local bounds are `(-96,-96)` through `(96,96)`.
- `DestinationStage/TunnelBounds` sizes the temporary room.
  `TerrainLayerRenderer` expands the prepared passage into that room with the
  same production-mask snapshots; the environment contains no replacement
  terrain artwork or collision.
- `DestinationStage/StageFloor` authors the miner's stage x position; runtime
  samples and assigns y from the production mask, then places the already-landed
  miner there without another tween. Add concrete actor positions
  beneath `DestinationStage/ActorMarkers` and interaction targets beneath
  `DestinationStage/ActionMarkers` so the reusable environment grounds them
  with the stage.
- Concrete choreography should query `get_cutscene_room_screen_rect()` or
  `get_stage_motion_bounds()` and use `ground_stage_marker()` for additional
  authored markers. Do not duplicate terrain-floor sampling in an actor
  controller.
- `stage_ready` emits only after the room has expanded, marker roots have been
  grounded, and the miner reaches `DestinationStage/StageFloor`. The concrete
  sequence then waits for the iris to open before its lead actor enters. The
  miner response focuses the same iris for restoration; control returns only
  after it opens and the bars leave.
- `RatSpawnAnchor` and `RatExitAnchor` author the offscreen entrance and exit.
  Only the exit marker's x coordinate is used; keep it beyond the right
  viewport edge so the complete mouse mines out of frame before cleanup.
  Repeated `MiningTargets` author distinct wall indents; each target controls
  its floor offset, jump height, front/behind plane, and strike count. A target
  with `Jump Height` of zero is reachable on foot, so a mouse that has just
  landed runs to it instead of arcing — that is what makes `LowFrontIndent` the
  lane that reads as "hit the ground and ran off".
- `RatEntryPoints` are the cave's ways in, cycled in child order. `OpenSideEntry`
  needs no breach: mice simply run in along the floor from off the left edge.
  The three `*BackWallBreach` markers are holes struck through the backing wall
  at staggered heights; a mouse pops out of the hole it just opened and falls to
  the floor on a real parabola (`Wall Pop Rise` is only how far it rises first —
  the descent always accelerates), then holds a landing squash for
  `Land Recovery Seconds` before its owner sends it anywhere.

Live follower cap, web cap, spawn spacing, run durations, strike cadence,
indent size, draw planes, exit time, and response pause are Inspector
properties on the sequence root. Spawning starts with the rat warning,
continues through the miner response, and repeats as actors leave; finishing
the response stops new spawns and lets every live rat mine fully offscreen
before restoration. `Lead Rat Appearance` is Rutini's own paired art and is
deliberately held out of `Rat Appearances`, which cycles the three follower
colors by spawn index, so the speaking lead never shares a color with the crowd.
`Follower Spawn Interval` paces arrivals into a trickle; short values let the
cast fill to its cap in one burst and then re-burst as a group exits together. Each resource keeps its idle and hit PNG together, while the actor
rig retains movement and strike anchors. `ActorSpriteView` remains an optional
future sprite-sheet seam; leaving its pose set empty preserves the paired PNG
behavior used by the shipped mice.
The lead rat's warning and miner's response are separate resources under
`resources/dialogue/`, so text changes do not require script edits.

The breakthrough is presentation-only. Never move `MinerRig`'s gameplay root,
change `RunState`, or add a second collision model for the deeper tunnel.
Cancellation must restore promoted terrain layers, the miner visual root,
camera focus, letterbox state, and the timing/swing gate.

The only trigger is a hit at or above `Minimum Combo` whose resulting run depth
has reached at least `Minimum Run Depth` rows (combo 8 and depth 400 in the
shipped scene). The layer controller is intentionally the first
`depth_changed` subscriber in `mining_scene_wiring.gd`, so it can prepare the
qualifying hit before a regular encounter claims the flow. There is no
alternate depth-only trigger: missing the combo leaves regular depth encounters
unchanged.
