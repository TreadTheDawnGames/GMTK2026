# Canonical Story Order

Status: Approved by Jared on July 24, 2026, using Zephan's narrative order.

This document is the source of truth for story order and intended pacing. Dialogue
wording may still be authored, but agents must not reorder, remove, or replace these
beats without Jared or Zephan approving the narrative change.

## Story Rules

- The pre-thief story targets a roughly 15-minute first playthrough.
- Depth, not elapsed time, triggers encounters. The times below are pacing targets.
- Encounters happen in mineable tunnels entered by breaking through from above.
- The player keeps digging while the credits play.
- The Thief is a distant post-credits objective, not part of the 15-minute run.
- Upgrade-driven speed changes may move later depths, but their order cannot change.

## Canonical Sequence

| Order | Target depth | Target time | Story beat |
| ---: | ---: | ---: | --- |
| 1 | 0 | 0:00 | The bus scene starts the game. |
| 2 | 600 | 0:40 | Cheese Girl introduces herself and says the cheese cafe is straight down. The cafe destination is near depth 14,000; old references to level 80,000 are not canonical. |
| 3 | 1,400 | 1:30 | The player first meets the man with the lantern staff. He cryptically foreshadows the Thief. |
| 4 | 2,500 | 2:40 | The Treasure Hunter introduces himself, criticizes the player's current tool, and gifts the first improved pickaxe. |
| 5 | 4,000 | 4:00 | Rotini is introduced on the cave path. Existing `rutini_*` resource names refer to Rotini until a coordinated rename is approved. |
| 6 | 5,600 | 5:30 | The lantern-staff man returns and gives a clearer warning about the Thief. |
| 7 | 7,400 | 7:15 | The Treasure Hunter finds his treasure and gifts the player another pickaxe because he no longer needs it. This is a second, distinct gift. |
| 8 | 9,200 | 9:00 | Quibble is introduced while heading to the cafe for coffee. He gives the player coffee that makes the player faster. Existing `coffee_cat_*` resources refer to Quibble. |
| 9 | 11,200 | 11:00 | The player tells Rotini that the cheese cafe is straight down. Rotini's rat colony joins the player and mines downward with them. |
| 10 | 14,000 | 14:00 | The player reaches the cafe/end gathering. Cheese Girl, the Treasure Hunter, Rotini and the rats, and Quibble are together and happy. The lantern-staff man foreshadows the importance of time management. |
| 11 | 15,000 | 15:00 | Credits begin while the player remains able to dig. Continuing through the credits is intentional. |
| 12 | 15,200 | Post-credits | The lantern-staff man tells the player that the end has been reached and only miles of stone remain between the player and the Thief. |
| 13 | 100,000 | Long-term objective | The player finally reaches the Thief. The exact reveal and dialogue remain intentionally unspecified here. |

## Implementation Contract

The target depths are the initial authored values, not permission to add time-based
fallbacks. Playtests may tune depths to keep an ordinary run near 15 minutes, but
must preserve the sequence. Any terrain refactor must retain a way to reserve the
next encounter floor, open its tunnel, and capture the player when their mined
depth crosses the tunnel ceiling. The comparison must tolerate one large hit
skipping past the ceiling or floor; no exact impact target is required.

The screenshots supplied by Jared establish story beats, not final dialogue.
Placeholder language for the lantern-staff man and the Thief must not be invented
into canon without narrative approval.
