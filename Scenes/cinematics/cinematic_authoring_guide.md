# Cinematic Authoring Guide

The mining scene has two cinematic forms: the surface arrival that opens every
run and framed character conversations inside authored terrain tunnels. Story text remains in `DialogueConversation` resources. Movement,
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

Open `character_encounter_stage.tscn`, any scene that inherits it such as
`rat_colony_encounter_stage.tscn`, or `arrival_intro.tscn`, and the real terrain
is already there. There is no drawn approximation to drift: the
`EditorTerrainPreview` branch holds a production `TerrainManager` and
`TerrainLayerRenderer`, so the editor runs the same renderer, shader, profile
colours and hole masks the game runs. If the terrain looks wrong in the editor,
it is wrong in the game.

`TerrainLayerRenderer` is `@tool`, but editor drawing is opt-in per instance
through `Preview In Editor`. Only these preview instances set it, so opening
the mining scene stays instant.

The preview lives on the **base** encounter stage, so every concrete stage
inherits it. Its node is offset by `(-576, -260)` to put the terrain's mining
face on the stage's own origin, which is where the stage sits at runtime — so a
marker authored at `y = 0` is on the dig line.

On `EditorTerrainPreview`:

- `Preview Depth Rows` is how far below the surface the preview sits.
- `Preview Combo` is the combo used by its test impacts.

### Changing the look and watching it update

Edit `default_terrain_layer_profile.tres` in the Inspector — strata tints, dirt
detail, rock density, grass, crust, fracture strength — and the previewed rock
recolours immediately. The preview listens to the profile's and the config's
`changed` signal, so any authored value is a live one. Editing
`terrain_layer.gdshader` and saving reloads it the same way.

These are the real production resources, so what you tune in the editor is what
ships. There is no preview-only copy to keep in sync.

### Breaking the terrain in the editor

Two ways, and both dig through the production `TerrainManager` against real
cells — never a hole drawn to look like one.

**Click.** Enable the addon's **Dig Terrain** toggle in the 2D viewport toolbar
(it appears only in a scene that has a preview). Left-click the rock to dig;
**Alt-click** an opening to heal it. Each click adds or removes an authored
`Marker2D`, so the dug state shows in the Scene dock and saves with the scene.
Switch the toggle off to get normal selection and dragging back.

**Drag.** Every `Marker2D` under `EditorTerrainPreview/TestImpacts` is an
opening. Drag one and it follows live; duplicate it for more; delete it and the
rock heals. Moving a marker rebuilds from intact terrain, so openings never pile
up behind you.

The whole branch sits at `z_index -100` and **frees itself before a running game
can pay for it** — in `_enter_tree`, because Godot readies children first and by
`_ready` its terrain stack would already have streamed a full chunk set. Nothing
may read from it at runtime; it owns no state.

### Playing one beat in isolation

Open `Scenes/cinematics/cinematic_preview.tscn` and run it (F6). It boots the
real mining scene and jumps straight to a beat, so a sequence can be watched end
to end without playing up to its trigger:

- `1` surface arrival, `2` rat colony tunnel, `3` first depth encounter
- `R` replays the current beat from a freshly rebuilt scene
- `Esc` quits

It only drives triggers — it crosses the selected encounter's real ceiling
threshold rather than faking a sequence's internals. That is deliberate: if a beat
misbehaves in the preview it misbehaves in the game, so the harness can never
give a false pass.

## Framed conversations

`DialogueDirector` owns the letterbox and the single in-universe bottom
dialogue box. Dialogue advancement and story resources remain independent from
the box presentation.

Every visible speaker needs a `SpeechReaction` targeting only their visual
root. Dialogue does not draw or register speaker anchors. Do not connect
dialogue signals in the scene editor; cross-system routes belong in
`Scripts/mining/mining_scene_wiring.gd`.

Edit character entrances, departures, positions, and appearance resources in
their existing encounter scene or resource. `MiningCinematicFlow` is the sole
owner of timing-window visibility, queued-swing gating, and encounter-camera
focus. A sequence must claim it before starting and release the same named
owner only after its last visual has restored.

## In-world tunnel encounters

Every depth cutscene is a `DepthCharacterEncounter` in the ordered encounter
config. Its depth is the solid chamber floor; the shared chamber height derives
its ceiling. `DepthEncounterController` captures the encounter as soon as the
run crosses that ceiling. Compare with `>=`, never equality: a large combo may
skip the ceiling and floor in one hit and must still transition.

The chamber is carved by `TerrainManager` and rendered by the normal
`TerrainLayerRenderer`. There are exactly four gameplay strata. Encounter
stages may add actors, props, movement, and line cues, but they must not add a
second terrain renderer, custom room artwork, promoted layers, or collision.

Use `Scenes/cinematics/character_encounter_stage.tscn` for ordinary cast
movement. Rotini's colony uses
`Scenes/cinematics/rat_colony_encounter_stage.tscn`: the waiting presenter is
the lead rat beside the miner, while a bounded stream of reusable mouse actors
runs, mines, and exits through the same tunnel. Their strike contacts use
`presentation_strike_requested`, which the central mining wiring routes to the
normal dirt particles, smoke, and shake.

A stage must release every transient actor on closing and cancellation.
`MiningCinematicFlow` remains the sole owner of mining input, HUD visibility,
and camera focus.
