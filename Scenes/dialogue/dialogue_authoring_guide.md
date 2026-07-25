# Dialogue Authoring Guide

Dialogue is authored as a `DialogueConversation` resource in the Godot
Inspector. The runtime never stores story text in scripts.

The first version intentionally supports clear, ordered conversations. It does
not yet include branching choices, conditions, localization keys, or save-game
history. Those can be added around the same resource model once the jam story
needs them.

## Create a conversation

1. Duplicate a current cast resource such as `res://resources/dialogue/cheese_girl_first_conversation.tres`.
2. Rename the file and give `Conversation Id` a unique `snake_case` value.
3. Expand `Participants` and add one `DialogueParticipant` for each speaker.
4. Give every participant a short stable `Slot`, such as `miner` or
   `market_keeper`, and the name players should see in `Display Name`.
5. Expand `Lines` and add `DialogueLine` resources in playback order.
6. For each line, choose a participant slot and enter the spoken text.
7. Optionally set `Speaker Pose` and `Stage Cue` to named entries provided by
   that actor's pose set and encounter stage.
8. Leave `Auto Advance Delay Seconds` at `0` to wait for Space or Enter. Use a
   positive delay only for intentionally automatic lines.

The conversation validates itself when playback begins. Missing IDs, duplicate
participant slots, unknown speakers, and empty lines are reported as clear
Godot errors instead of silently failing.

## Configure character appearances

Create a `CharacterAppearance` resource for every sprite option. Each resource
stores:

- either a single texture or one frame from a sprite sheet;
- scale and offset values that align the person's feet with the floor;
- optional tint and horizontal flipping.
- an optional `ActorPoseSet` for human-named `idle`, `walk`, or story poses.

Each named encounter references one appearance directly. Reuse the same
appearance in multiple encounters when a character returns later in the run.

The current appearance resources use tinted copies of the miner sheet as
stand-ins. Replacing their textures does not change character scheduling.

## Configure named encounters

Open `res://resources/encounters/depth_encounter_config.tres` in the Inspector.
Its `Encounters` array controls both terrain generation and cutscene order.
Each `DepthCharacterEncounter` assigns:

- a unique `Encounter Id`;
- a stable `Actor Id`, reused for every return by the same person;
- a fixed `Depth From Surface`, measured in terrain rows;
- one named character appearance and conversation;
- an optional `CharacterEncounterStage` scene;
- the character's participant slot for speech animation;
- an optional pickaxe reward appended to the cumulative run stack.
- canonical story-effect flags for Quibble's coffee speed boost, Rotini's
  colony support, the cafe cast gathering, and the post-credit gate.

The Treasure Hunter's two distinct pickaxe gifts never replace earlier tools.
Every owned definition continues
to contribute mining modifiers and special effects. The newest gift controls
only the visible tool tint. Each definition also authors a combo threshold
and target-scene collection; reaching that combo adds one extra target from
that pickaxe until the streak ends.

Enable `Occurs At Run Bottom` only for the thief. That places the encounter at
zero remaining depth for the authored 100,000-depth run. The thief uses
`thief_encrypted_dialogue.tres`. Its empty ciphertext keeps the ending
unwritten until the story is ready.

To author it without saving plain text, close the editor and run this from the
project console:

`godot --headless --path . --script res://tools/encrypt_dialogue.gd -- res://resources/dialogue/thief_encrypted_dialogue.tres thief_finale "thief=Thief" "miner=Miner" --lines "thief:<line>" "miner:<line>"`

Each quoted argument becomes one ordered line. Omit the `thief:` prefix when
the thief is speaking. The command overwrites only the encrypted resource;
plain text is never written to a project file. Reopen the editor after running
it so Godot reloads the ciphertext.

The approved canonical story order is:

- the bus opening at depth 0;
- Cheese Girl at 600, pointing straight down to the cafe near 14,000;
- the lantern-staff man's cryptic first warning at 1,400;
- the Treasure Hunter's introduction and first improved pickaxe at 2,500;
- Rotini's introduction at 4,000;
- the lantern-staff man's clearer Thief warning at 5,600;
- the Treasure Hunter's discovery and second distinct pickaxe at 7,400;
- Quibble's cafe-bound introduction and coffee speed boost at 9,200;
- Rotini's colony joining the downward dig at 11,200;
- the happy cafe gathering and time-management foreshadowing at 14,000;
- gameplay credits beginning at 15,000 while digging remains enabled;
- the post-credit lantern message at 15,200;
- the intentionally unwritten Thief encounter at 100,000.

The `rutini_*` and `coffee_cat_*` filenames and stable actor IDs are legacy
resource aliases for Rotini and Quibble. Their player-facing names are
canonical. Moody Teen and the extra Treasure Hunter visit remain inactive
legacy resources and must not be added to the schedule without narrative
approval.

To add a cutscene, duplicate one encounter `.tres`, assign its depth,
conversation, appearance, and optional stage, then insert it into `Encounters`
in strictly increasing depth order. That one entry makes terrain carve the
tunnel above its floor and makes crossing its ceiling start the cutscene.
Threshold crossing uses `>=`, so one large hit cannot skip an encounter.
Reusing an `Actor Id` and appearance keeps a returning character visually
consistent while allowing a new conversation or approved reward.

`Chamber Height Rows` controls the open fall immediately above each floor.
`Chamber Width Cells` controls the centered opening between the side walls.

One presenter is created per stable `Actor Id`, so returning characters are the
same runtime actor instead of duplicate scene-index entries. Mining to an
encounter depth reserves that encounter, but does not start it. The miner must
fall through the newly opened chamber and land on its authored floor before
framing, stage motion, or dialogue begins. Finishing a conversation stacks its
reward and advances the single ordered schedule.

Character chambers are intentionally only 24 terrain rows tall. The cafe is
marked explicitly with `Gathers Cast`; it is not inferred from array position
or depth. `Gathering Actor Ids` controls the named group order: Cheese Girl,
the Treasure Hunter, Rotini, Quibble, and the lantern-staff man. The encounter
is a happy gathering, not a departure, so it does not open a right-side exit.
The 15,200 lantern encounter uses `Requires Credits Complete`, ensuring its
post-credit message cannot begin until the gameplay credits finish.

## Author encounter stages

The standard encounters inherit
`res://Scenes/cinematics/character_encounter_stage.tscn`. Duplicate or inherit
it for a custom scene, then keep these human-named roots:

- `ActorMarkers`: `Entrance`, `Conversation`, `Work`, `Rest`, and `Exit`;
- `PropMarkers`: named objects such as `Gift`, `Cart`, or `Lantern`;
- `ActionMarkers`: named effect points such as `WallStrike`.

Move markers in the editor and author `AnimationPlayer` clips with readable
names such as `offer_pickaxe` or `look_back`. Put that exact name in a dialogue
line's `Stage Cue`. The controller opens the cinematic frame, walks the actor
over sampled terrain, plays line cues, closes to `Rest`, then releases mining.
An interrupted stage restores its captured presenter transform and animation.
Calling `request_presentation_strike()` from an authored animation relays the
marker through mining scene wiring so shared dirt, smoke, and shake effects can
be reused without coupling the stage to mining systems.

Each encounter identifies its `Speaker Slot`. Every visible participant,
including the miner, bounces once when one of their lines is presented. The
shared `SpeechReaction` component moves presentation-only visual roots; it
never changes gameplay or encounter positions.

The miner is intentionally silent. Any line authored with the stable `miner`
slot is presented as `...`; keep the resource text as `...` as well so the
Inspector communicates the same story rule.

`DialogueDirector` presents every conversation through the in-universe bottom
dialogue box. Top and bottom cinematic bars frame all conversations and may be
kept open between linked dialogue and movement beats.

During dialogue the gameplay tree pauses, while the dialogue overlay and dirt
particles continue processing.

Credits are the exception to cutscene pausing: they begin at depth 15,000 as
an overlay while the miner remains controllable. The 15,200 encounter waits
for that overlay to complete even if the player reaches its depth early.

Gameplay depth is separate from screen pixels. Each descended terrain row adds
one depth, so changing terrain or character art size does not move
encounters or alter the 100,000-depth run.
