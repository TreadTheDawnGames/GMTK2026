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

Pickaxe gifts never replace earlier tools. Every owned definition continues
to contribute mining modifiers and special effects. The newest gift controls
only the visible tool tint. Each definition also authors a combo threshold
and target-scene collection; reaching that combo adds one extra target from
that pickaxe until the streak ends.

Enable `Occurs At Run Bottom` only for the thief. That places the encounter at
zero remaining depth for any configured run length. The thief uses
`thief_encrypted_dialogue.tres`. Its empty ciphertext keeps the ending
unwritten until the story is ready.

To author it without saving plain text, close the editor and run this from the
project console:

`godot --headless --path . --script res://tools/encrypt_dialogue.gd -- res://resources/dialogue/thief_encrypted_dialogue.tres thief_finale "thief=Thief" "miner=Miner" --lines "thief:<line>" "miner:<line>"`

Each quoted argument becomes one ordered line. Omit the `thief:` prefix when
the thief is speaking. The command overwrites only the encrypted resource;
plain text is never written to a project file. Reopen the editor after running
it so Godot reloads the ciphertext.

The current authored order keeps every reward before the late solo descent:

- Cheese Girl at 1,000;
- Treasure Hunter's first visit at 6,000;
- Rutini's first visit at 11,000;
- Treasure Hunter's second visit at 16,000;
- Moody Teen at 25,000;
- Rutini's second visit at 35,000;
- Treasure Hunter's discovery at 47,000;
- COFFEE CAT at 61,000;
- Cloak/Lantern warning at 76,000;
- the full cast farewell at 84,000;
- the thief at 100,000, which is zero remaining depth.

To add a cutscene, duplicate one encounter `.tres`, assign its depth,
conversation, appearance, and optional stage, then insert it into `Encounters`
in strictly increasing depth order. That one entry makes terrain carve the
tunnel above its floor and makes the matching landing start the cutscene.
Reusing an `Actor Id` and appearance keeps a returning character visually
consistent while allowing a new conversation and reward.

`Chamber Height Rows` controls the open fall immediately above each floor.
`Chamber Width Cells` controls the centered opening between the side walls.

One presenter is created per stable `Actor Id`, so returning characters are the
same runtime actor instead of duplicate scene-index entries. Mining to an
encounter depth reserves that encounter, but does not start it. The miner must
fall through the newly opened chamber and land on its authored floor before
framing, stage motion, or dialogue begins. Finishing a conversation stacks its
reward and advances the single ordered schedule.

Character chambers are intentionally only 24 terrain rows tall. The farewell
is marked explicitly with `Is Farewell`; it is not inferred from array position
or depth. `Farewell Actor Ids` controls the named group order, and the right
wall remains open until those actors walk offscreen. The final thief stays
at the authored bottom depth after that departure.

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

A future silent-teen beat should remain concrete story state: after 50
completed conversations with that teen, select the authored first-spoken-line
conversation. Do not add a generic condition language for that single case.

`DialogueDirector` presents every conversation through the in-universe bottom
dialogue box. Top and bottom cinematic bars frame all conversations and may be
kept open between linked dialogue and movement beats.

During dialogue the gameplay tree pauses, while the dialogue overlay and dirt
particles continue processing.

Gameplay depth is separate from screen pixels. Each descended terrain row adds
one depth, so changing terrain or character art size does not move
encounters or alter the 100,000-depth run.
