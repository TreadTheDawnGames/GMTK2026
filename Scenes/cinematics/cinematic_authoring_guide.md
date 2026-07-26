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
and stops with its front at centre screen, its door opens, the miner gets off at
that centre-screen dig spot, and the bus pulls away left with its leading
section passing in front of him. He remains beside the newspaper reader. Every
duration is an Inspector property on the sequence root.

The exit reveal uses a split draw order. The full `BusSprite` is behind the
cinematic miner, while `BusFrontOccluder` redraws only the leading section at
absolute `z_index 5`. The miner is placed at `MinerDropOffAnchor` while hidden;
when the bus departs, its front passes in front of him and reveals him over the
remaining body, so he reads as exiting from the front rather than being wiped
out from behind the bus.

The bus root itself parks right of centre: `FrontEdgeAnchor`, measured at the
leftmost edge of the left-facing art, lands at screen x 576 on
`MinerDropOffAnchor`. The miner therefore stands at the bus's physical front
while remaining at the fixed gameplay mining point.

The bus art is mirrored with a negative `scale.x` to face left, and its sprite
offset is mirrored with it so the body stays centred on the node. Wheel-shine
UVs are texture-space and unaffected, but the spin direction is corrected in
script from `sign(scale.x)`.

- Props are authored in viewport pixels against a ground line at **y = 262**.
  The authored terrain-space surface centre begins at **(576, 262)**, and the
  node re-anchors itself to that same world point on both axes every frame.
  `ArrivalIntro` processes after the terrain view, eliminating one-frame scroll
  lag during vertical and snaking movement, and remains under the shared
  `Camera2D` so terrain and stop receive the exact same impact shake.
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

**Every character stands on the second layer, mining or in a cutscene.** Only
the surface is different, because there he is on the ground rather than in it.

With `layer_z_indices` at `(2, 0, -1, -2)`:

| State | Order | Reads as |
| --- | ---: | --- |
| Mining (`buried_draw_order`) | `1` | between the two frontmost strata, down in his dig |
| Cutscene (`cutscene_draw_order`) | `1` | the same stratum, so the foreground rock closes over the cast too |
| Surface (`surface_draw_order`) | `3` | standing on the ground rather than in it |

The cutscene order was `3` until Zephan's direction that every character sit on
the second layer. Clear of every stratum reads as a more legible frame and as a
different world: the cast were pasted on top of rock everything else in the game
is inside. The two numbers are kept separate even though they now agree, because
they mean different things — where a man stands while working, and where a shot
puts its cast — and a later change to one should not silently move the other.

`local_tests/verify_cutscene_cast_draw_order.gd` asserts both ends of that.
These numbers live in `miner_rig.gd` while the strata live in the terrain
profile, and nothing else ties them together: add a stratum or renumber the
existing ones and every cutscene silently starts playing behind the wall, with
no error anywhere. Run that check after touching either file.

The cost of the mining order is real and accepted: the camera does not follow
the miner down, so he sits at the top of his own shaft in every frame and the
foreground stratum crops him at the shins for the whole descent, not only while
he is genuinely inside the ground. Being occluded by the ground he stands in is
the read.

The cast layer follows him. `CharacterLayer` rests at `z_index 1` and
`DepthEncounterController` copies `cutscene_draw_order` onto the whole layer for
the duration of an encounter, because a visitor on a different stratum from the
miner is worse than either of them being consistent.

**That single number is the whole cast's draw order.** There is no per-character
value to keep in step with it, so moving every character to another layer is one
edit in `miner_rig.gd` rather than one per character — worth knowing before
several people set out to move their own.

The surface is the one exception, because there he is standing *on* the ground
rather than in it:

- `MinerRig` owns both values (`surface_draw_order` `3`, `buried_draw_order`
  `1`) and nothing else sets its `z_index`. He opens the run in front of layer
  one so the arrival shot shows a whole miner, and `MiningSceneWiring` calls
  `leave_surface_draw_order()` on the first landing below
  `initial_surface_row`, after which every shot layers exactly as before.
- The arrival hands his order back with `miner_rig.get_rest_draw_order()` on the
  settle beat, while he is visibly planting his feet, rather than carrying its
  own copy of the number.
- A cinematic may lift the miner above the strata (`miner_cinematic_draw_order`)
  while it owns him, but it must return him to `get_rest_draw_order()` as part
  of a visible motion, never as a bare assignment once the frame is already
  open. The restore reads that value live, so a shot that ends at a different
  depth than it started still lands on the right layer.

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

## House rules for authoring one encounter

Read this before changing a room or a stage. Every rule below cost a bug to
learn, and each of the eleven encounters is expected to follow it.

### Own only your own files

An encounter is authored through exactly two files: its room in
`resources/cinematics/sculpts/<id>_room.tres` and its stage in
`Scenes/cinematics/<name>_encounter_stage.tscn`. Its `.tres` in
`resources/encounters/` is wiring and should already be correct.

`sculpt_baker.gd`, `character_encounter_stage.gd`, `rat_colony_encounter_stage.gd`
and `depth_encounter_controller.gd` are shared by all eleven. Changing them to
suit one shot changes the other ten. If a shot needs something they do not do,
add it as an opt-in export whose default preserves current behaviour — the way
`closing_fade_seconds`, the facing trio and `procession_mines` were added — and
say so in the handoff. Scene merges are unrecoverable, so two people must never
edit one `.tscn` in the same session.

### The room must be reachable

The miner arrives by breaking the ceiling and falling. His snaking descent can
land on **any column in a 49-cell band** (terrain columns 168–216), and the
encounter camera centres on whatever column he stopped at.

- The floor under that whole band stays solid. `protected_floor_rows` guards it;
  set it to zero only for a room deliberately authored with a hole, and then hold
  the band solid by hand.
- A room's ground is **not** its floor row — the level tunnel lays up to three
  cells of loose rock on top, and that is what he lands on. The schedule tolerates
  four rows of that (`LANDING_FLOOR_TOLERANCE_ROWS`). Exceed it and the encounter
  never starts: it sits pending forever with the cinematic gate already claimed,
  which in game looks like mining that simply stopped working, with no error.
- `local_tests/verify_encounter_landing_reachable.gd` proves this for every room.
  Run it after any carve.

### Measure spacing, never guess it

One character-width is the **widest single row of opaque pixels**, times the
scale that ships. It is not the sprite's bounding box: the miner's box unions his
pickaxe head at one height with his torso at another and comes out roughly twice
the man. Measured bodies: miner **52.8px**, Cheese Girl **34.3px**, Rotini
**62.7px** — the rat is wider than the man, because the art is long.

House spacing is one miner-width of daylight between two bodies, so root to root
is `(a + b) / 2 + 52.8`. Measured, so nobody has to derive them again:

| Character | Body | Shoulders touching | One miner apart |
| --- | ---: | ---: | ---: |
| miner | 52.8 | — | — |
| cheese_girl | 34.3 | 43.5 | **96.3** |
| moody_teen | 45.0 | 48.9 | 101.7 |
| newspaper_reader | 43.4 | 48.1 | 100.9 |
| rutini | 62.7 | 57.7 | **110.5** |
| thief | 63.4 | 58.1 | 110.9 |
| treasure_hunter | 86.5 | 69.7 | 122.5 |
| cloak_lantern | 100.4 | 76.6 | 129.4 |
| coffee_cat | 202.4 | 127.6 | 180.4 |

Two of those are worth a look before they are used as-is. Quibble reads 202px
wide against the miner's 52.8 — nearly four times him, filling a third of the
frame — and the lantern man 100px. Both are plausibly a scale that was set by eye
against the old sunken grounding rather than a deliberate size.

### A prop is not floor-sampled; the cast are

Every actor marker is authored at `y = 0`, the dig line, and that is correct for
actors: `DepthEncounterController` seats every one of them through
`_sample_cutscene_floor`, so the marker says *which column*, and the terrain says
*how high*. **A prop gets no such treatment.** It is a static node at the y you
typed.

The two are not the same line. A room's ground is not its floor row — the level
tunnel lays up to three cells of loose rock on top, which is **24px**. So a prop
dropped on `y = 0` beside a cast member standing on `y = 0` is buried to its
knees in the surface they are standing on, and in the editor it looks fine,
because the preview draws the rock over it exactly as the game will.

Measure it rather than nudging until it looks right: call
`get_layer_opening_floor_support_screen_y` — the same sampler the controller
uses — at the prop's own columns and author against the answer.
`local_tests/capture_lantern_warning_stage.gd` does this and prints the number.
The bench in encounter 5 came out at `y = -23`.

If the prop also tracks the miner (below), sample across the **whole landing
band**, not just the centre: loose rock is uneven, and a static prop cannot
follow it. Encounter 5's bench sees about 8px of movement either way, which is
the accepted cost of props not being sampled.

### Props stay in the room unless you say otherwise

`conversation_tracks_miner` slides the **`ActorMarkers` root only**. That is
right for a prop that belongs to the terrain — a ledge, a shaft, the lantern
staff standing at the bottom of a drop — and wrong for one that belongs to the
conversation. Left pinned, a prop the visitor is meant to be standing at is up to
**392px** away from them, the full width of the landing band, and the shot has no
subject.

`props_track_tracked_cast` carries `PropMarkers` under the same shift. It only
does anything with `conversation_tracks_miner` on, because it copies the shift
tracking already applied. The Treasure Hunter's hoard and the Lantern Keeper's
bench both use it.

### Entrances and exits must clear the frame

The frame is 1152px wide and centred on the miner, so anything within 576px of
him is on screen. A marker authored at a fixed room offset fails this whenever he
lands toward that side — which is how a visitor ends up popping into existence
mid-shot, or stopping while still visible.

With `conversation_tracks_miner` on, the whole `ActorMarkers` set slides to the
landing column together, so author entrances and exits **relative to
Conversation** and keep them at least 480px away. 600px and 700px are the values
in use.

Turn tracking **off** when a character must stand on a specific piece of rock —
a ledge cannot slide to meet a landing column. The cost is that their distance
from the miner then varies with where he landed, and there is no way around that
short of narrowing the landing band or reframing the camera.

### Characters are hidden until their cutscene claims them

Every presenter is built at `_ready` and parked at its own depth, so one actor
can be reused across repeat visits and gathered for the cafe. They are hidden
there; `prepare()` reveals whoever the stage takes. Do not show one early — a
player mining past would find them standing in the rock waiting.

### Rooms live in files, not inside encounters

Every encounter references its room through an `ExtResource`. If one ever goes
back to a `SubResource`, carving the file in `sculpts/` does nothing at all and
the failure is silent — the editor and the game simply keep drawing the embedded
copy. The landing check reports this.

### A room can be cut by a script, and then it has to prove itself

Rooms are normally painted in the Cutscene panel. Two are not: the Treasure
Hunter's and the Lantern Keeper's Warning are each cut by a script in
`local_tests/` — `carve_treasure_hunter_first_room.gd`,
`carve_lantern_warning_room.gd`. Both compose `CutsceneSculptBaker` and the
panel's own `CutsceneSculptBrush`, so the result is the same rock the brush would
have made and a designer reopening the room finds work they can continue. Every
pass is deterministic from the cell coordinate, so re-running reproduces the room
exactly.

A carve script **must verify before it saves**, and must not save if a check
fails. Both of these do. The reason is the failure mode: a room that is wrong is
not a room that looks wrong, it is a run that stops.

**Nothing may hang below the ceiling line.** This is the trap, and it cost two
failed carves to find. The roughen brush only knows where edges are, not what a
shot needs, so it will happily leave a lump of rock floating in mid-air.
`get_landing_local_rows` — and the real fall — stop the miner on *the first solid
cell under the first opening*, so a single detached cell twenty-five rows up is a
landing surface. He never reaches the floor, the encounter never starts, and it
sits pending forever with the cinematic gate already claimed. In game that looks
like mining that simply stopped working, with nothing in any log.

A band of protected rock under the ceiling is **not** enough, which is the
tempting fix and the second thing that failed: a lump inside the band catches him
just the same. The rule has to be absolute — per column, empty everything from
the topmost opening down to the rock lying on the floor. The ceiling still reads
jagged, because its height varies column to column, which is what the roughen
pass moved. It does not need debris underneath it to look like rock.

Two related traps in the same family, both worth knowing:

- Find the ground by scanning **up** from the floor row, not down from the
  ceiling. Downward finds the first solid cell below the opening, which is the
  right answer only when nothing is hanging — and the whole reason you are
  checking is that something might be.
- Measure headroom as the **contiguous** open air standing on the ground, not as
  the gap between ceiling and floor. The second number cheerfully ignores
  whatever is floating in the middle of it.

### Timelines run, but only where you say so

Timelines used to be a document nothing read. They are not any more: a stage is
handed its encounter's sequence, the actor resolver reaches the whole cast, and a
blocking DIALOGUE beat is released when the conversation the schedule ran
finishes. **Encounter 5, the Lantern Keeper's Warning, is the first shot driven
this way** and is the one to copy from.

It stays opt-in per encounter, behind `plays_authored_timeline` on the
encounter's `.tres`. That switch is deliberately separate from `sequence` being
set, because every encounter still carries a *generated placeholder* timeline
from before any of this ran. Turning them all on at once would replace the
choreography each stage was tuned to and run every conversation twice — once
from the beat, once from the schedule. **A sequence file existing means nothing.
Only the switch does.** Encounters opt in as their timelines are genuinely
authored; the other ten are still notes.

What the timeline owns and what it does not:

- The timeline owns the shot **up to the end of its last beat**. That is what
  `play_opening()` runs.
- `play_closing()` still runs afterwards, and still owns the departure — the
  closing pose, `closing_facing`, `closing_fade_seconds`, the move to `Exit`,
  and the `closing` AnimationPlayer clip. So do not end a timeline by walking the
  actor off or hiding them; you will be fighting the thing that is about to do it
  properly. Encounter 5 ends on a WAIT for exactly this reason.
- Rewards and teardown belong to the encounter ending, not to a beat, and happen
  the same way on both paths.

Two sharp edges worth knowing before you author one:

- `line_range` is authored and validated on a DIALOGUE beat, and then
  **`depth_encounter_controller.gd` ignores it** — every DIALOGUE beat plays the
  whole conversation. You cannot currently land a cue between two lines by
  splitting the beat.
- The clock is clamped to the sequence's own duration, so a beat authored past
  the last beat's end never starts.

Choreography that does not need per-beat timing is still better authored through
the stage's own exports — move durations, poses, the facing trio,
`closing_fade_seconds`, `procession_mines`. Reach for a timeline when beats have
to be placed against each other in time, or against the player's reading speed.

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
