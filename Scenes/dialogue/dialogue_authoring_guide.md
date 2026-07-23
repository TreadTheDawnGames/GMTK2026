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

## Configure merchant appearances

Create a `MerchantAppearance` resource for every sprite option. Each resource
stores:

- either a single texture or one frame from a sprite sheet;
- scale and offset values that align the merchant's feet with the floor;
- optional tint and horizontal flipping.

Each named encounter references one appearance directly. Reuse the same
appearance in multiple encounters when a character returns later in the run.

The current appearance resources use tinted copies of the miner sheet as
stand-ins. Replacing their textures does not change merchant scheduling.

## Configure named encounters

Open `res://resources/encounters/depth_encounter_config.tres` in the Inspector.
Its `Encounters` array controls both terrain generation and encounter timing.
Each `DepthCharacterEncounter` assigns:

- a unique `Encounter Id`;
- a fixed depth measured from the starting surface;
- one named character appearance and conversation;
- the character's participant slot for speech animation;
- an optional pickaxe reward equipped after dialogue.

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

The current authored order is:

- Traveler with the Stone Pickaxe at 1,000;
- Tinkerer with the Swift Pickaxe at 6,000;
- Tunnel Surveyor with the Excavator Pickaxe at 11,000;
- Old Prospector with the Heavy Pickaxe at 16,000;
- the returning Traveler at 21,000;
- the thief at 100,000, which is zero remaining depth.

There are no randomized merchants. Add another encounter resource to the
array when a named character should return. Reusing an appearance keeps the
character visually consistent while allowing a new conversation and reward.

`Chamber Height Rows` controls the open fall immediately above each floor.
`Chamber Width Cells` controls the centered opening between the side walls.

All six characters are created when the mining scene starts. They exist below
the viewport and scroll into view with the terrain instead of appearing when
the miner lands. Landing only starts the current character's dialogue.
Finishing a merchant conversation equips any assigned reward and advances to
the next array entry. Characters remain at their original floors, so reviewing
earlier terrain does not leave previously visited chambers empty.

Each encounter identifies its `Speaker Slot`. While that participant's text is
being revealed, `MerchantPresenter` periodically bounces the sprite. Miner
lines do not move the merchant.

During dialogue the gameplay tree pauses, while the dialogue overlay and dirt
particles continue processing.

Gameplay depth is separate from screen pixels. Each descended terrain row adds
one depth, so changing terrain or character art size does not move
encounters or alter the 100,000-depth run.
