# Dialogue Authoring Guide

Dialogue is authored as a `DialogueConversation` resource in the Godot
Inspector. The runtime never stores story text in scripts.

The first version intentionally supports clear, ordered conversations. It does
not yet include branching choices, conditions, localization keys, or save-game
history. Those can be added around the same resource model once the jam story
needs them.

## Create a conversation

1. Duplicate `res://resources/dialogue/stone_pickaxe_gift.tres`.
2. Rename the file and give `Conversation Id` a unique `snake_case` value.
3. Expand `Participants` and add one `DialogueParticipant` for each speaker.
4. Give every participant a short stable `Slot`, such as `miner` or
   `market_keeper`, and the name players should see in `Display Name`.
5. Expand `Lines` and add `DialogueLine` resources in playback order.
6. For each line, choose a participant slot and enter the spoken text.
7. Leave `Auto Advance Delay Seconds` at `0` to wait for Space or Enter. Use a
   positive delay only for intentionally automatic lines.

The conversation validates itself when playback begins. Missing IDs, duplicate
participant slots, unknown speakers, and empty lines are reported as clear
Godot errors instead of silently failing.

## Configure recurring gift encounters

Open `res://resources/encounters/depth_encounter_config.tres` in the Inspector.
Its schedule and chamber values control both terrain generation and encounter
timing:

- `First Floor Depth` places the first chamber floor.
- `Repeat Interval Depth` sets how far apart later chambers are. With the sample
  first floor at 1,000, use `5,000` for floors at 1,000, 6,000, 11,000, and
  so on; use `10,000` for floors at 1,000, 11,000, 21,000, and so on.
- `Maximum Floor Count` must match the number of authored gift encounters.
  It prevents unused empty chambers from appearing after the final gift.
- `Chamber Height Rows` controls the open fall immediately above each floor.
- `Chamber Width Cells` controls the centered opening between the side walls.

The sample first floor is at exactly 1,000 depth and has 100 rows of open fall
space above it. `DepthEncounterController` reveals the NPC, hides
the timing bar, and starts dialogue when the miner lands on that floor.

Each entry in the controller's `Gift Encounters` array pairs one conversation
with the pickaxe granted after its final line. Entries play in array order.
Once every authored gift has been delivered, no additional encounter chamber
is scheduled. Finishing a conversation equips its gift and restores the timing
bar so mining can continue.

During dialogue the gameplay tree pauses, while the dialogue overlay and dirt
particles continue processing.

Gameplay depth is separate from screen pixels. Each descended terrain row adds
one depth, so changing terrain or character art size does not move
encounters or alter the 100,000-depth run.
