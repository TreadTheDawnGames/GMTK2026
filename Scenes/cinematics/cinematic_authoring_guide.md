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
and settles at centre screen on top of the stop, its door opens, the miner gets
off out of sight behind it at his centre-screen dig spot, and the bus pulls away
left so its trailing edge **wipes him into view** already beside the newspaper
reader. Every duration is an Inspector property on the sequence root.

The reveal depends on draw order: `Bus` is `z_index 5`, in front of the whole
cast, and parked at `BusStopAnchor` it covers the shelter completely. The miner
is placed at `MinerDropOffAnchor` *while still hidden*, so the departure
uncovers someone already standing there rather than popping him in afterwards.

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
  parked bus's span or the wipe has nothing to uncover. For the opening layout,
  both anchors use the fixed centre-screen mining x so the miner does not walk
  away from the bench before play begins.
- The miner moves only through `MinerRig`'s shared cinematic visual override.
  His gameplay root, `RunState`, and mining depth are never touched, and
  `RunIntroController` hands grounding back with `show_intact_floor_grounding()`
  when control returns.
- The attendant is a silent, unrelated newspaper reader, not the lantern-staff
  man or another story character. A `CharacterPresenter` driven by
  `attendant_appearance` on `RunIntroController` places him with the stand-in's
  **feet on the ground**,
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

## The cutscene editor

`addons/cutscene_editor/` adds a **Cutscene** panel to the bottom dock and takes
over the 2D viewport while one of its tools is armed. It replaces the old
`cutscene_terrain_tools` dig toggle, which is gone.

Open any scene holding an `EditorTerrainPreview` — `character_encounter_stage.tscn`
or a stage inheriting it — and pick the encounter you are authoring from
**Authoring encounter** at the top of the panel. Most encounters share one stage
scene, so that dropdown, not the Inspector, is how you say which cutscene you
are working on. The preview moves to that encounter's own depth and draws that
encounter's room.

### Sculpt: cutting the room out of real rock

An encounter with no room uses the procedural chamber: a centred rectangle with
a tapered ceiling, the same everywhere. **Create a room for this encounter**
makes a `CutsceneTerrainSculpt`, saves it beside the encounter in
`resources/cinematics/sculpts/`, and seeds it with exactly the chamber the game
already generates — so your starting point is what you already have, not a wall
of rock.

From there the room is a grid of terrain cells you paint:

- **Carve** opens rock, **Fill** closes it. **Alt** swaps the two mid-drag, which
  is the fastest way to walk back an overshoot.
- **Smooth** runs a majority filter over the cells under the brush, wearing a
  wall down. **Roughen** flips only cells already on a solid/open edge, so it
  jags a silhouette instead of punching holes through solid rock or filling the
  middle of the room.
- **Brush size**, **strength** and **edge falloff** shape the stroke. Every
  decision is seeded from the cell coordinate, so the same stroke over the same
  rock always gives the same result — a stroke you undo and redo comes back
  identical.
- **Dig hit** is the old marker workflow, kept because it is the only way to see
  a room *after* the miner has broken into it: it adds an authored `Marker2D`
  and digs it through the production `TerrainManager` exactly as a pickaxe hit
  does. Alt-click heals one.

A whole drag is one undo entry.

**Sculpting** picks what a stroke changes. *Shape (all strata)* moves the rock
and the ground the miner stands on together. *Stratum N only* changes what one
layer draws and leaves collision alone, which is how a rim reads as receding
rock rather than one silhouette stamped four times. **Rock smoothing** decides
how much the drawn rock rounds off the cell grid: at zero a roughened wall stays
hard-edged and jagged, at one every rim is interpolated.

The room replaces the procedural chamber **inside its own footprint only**, so
you can open rock the taper left solid and leave a pillar standing where it
would have carved one away.

### Seeing the layer you are working on

The foreground stratum covers everything behind it, so a buried layer cannot be
judged while you sculpt it. **See only** leaves one stratum fully visible and
either dims the rest to **Dimmed to** or hides them outright. It follows the
stratum you pick in **Sculpting** unless you untick *Follow the stratum I am
sculpting*.

This is a view, not an edit. It moves no cell, no mask and no draw order, it is
cleared when you open another scene, and nothing in a running game ever sets it
— the game draws every stratum fully opaque exactly as before.

### The landing line

The miner reaches every cutscene by breaking the ceiling and falling, so the
floor is load-bearing, not decoration. Two things protect it:

- **Guarded floor rows** keeps that many rows at the encounter floor solid
  whatever you paint over them, in both collision and the drawn rock. Carving
  straight through the floor is the easiest mistake to make and the hardest to
  notice, because the room still looks finished. Set it to zero only for a room
  deliberately authored without a floor.
- The green line drawn across the room is **where a falling miner actually
  stops**, computed for every column the run's snaking path can arrive down. It
  turns red where a ledge catches him above the floor or a column has nothing to
  land on. Watch it while you carve; the panel says the same thing in words.

### Cast and props

The **Cast** tab places a `CutsceneActorPreview` for each character: an
editor-only stand-in that draws a `CharacterAppearance` exactly as
`CharacterPresenter` will at runtime, so you position the real character inside
the real terrain. Its origin is the character's feet, because every marker in a
stage is authored on the floor line. Its `actor_id` is what timeline beats
refer to and what the runtime resolves to a live presenter.

Props are `PackedScene` instances placed under `PropMarkers`, and new named
`Marker2D`s can be added to any of the three marker roots from here. Everything
added is owned by the edited scene, so it shows in the Scene dock and saves.

Like the terrain preview, an actor stand-in frees itself in `_enter_tree` before
a running game can pay for it.

### Timeline

The **Timeline** tab authors a `CutsceneSequence`: one lane per cast member,
beats you drag to move and whose right edge you drag to change how long they
take. It is a timeline, not a queue — two beats starting at the same second run
in parallel.

Beat kinds are MOVE, POSE, FACE, BOUNCE, WAIT, DIALOGUE, STAGE_CUE, PROP,
STRIKE, SHOW and HIDE. A MOVE walks its actor over sampled terrain through the
same `CharacterPresenter.move_grounded_to` the existing stages use, so a walk
follows the floor you sculpted. A beat marked **blocks** holds the clock until it
genuinely finishes, and everything after it slides — a walk that runs long over
rough ground does not desynchronise the lines that follow it.

Dragging the playhead moves the cast stand-ins, because the scrubber calls
`CutsceneSequencePlayer.evaluate_at()` — the same path maths playback uses, with
no side effects. What you scrub is what plays.

Dialogue beats do not open dialogue themselves. They ask their owner to run a
conversation and wait; `DialogueDirector` stays the only thing that presents a
line.

### Playtest

**Playtest this cutscene** saves the room and runs the real game, breaking into
this encounter's actual ceiling. It never opens the cutscene directly, so a room
the miner cannot fall into fails here exactly as it would fail in a run. That is
the point: the harness can only give a true answer.

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
