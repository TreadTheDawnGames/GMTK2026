# Canonical Story Order

Status: Current working revision requested July 25, 2026. This supersedes the
July 24 encounter ordering while the new dialogue is being evaluated.

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
| 1 | 0 | 0:00 | A bus drops the Miner at the excavation site. An unattributed voice tells him he already knows the Thief lies below and that only fools find him. |
| 2 | 300 | 0:40 | Cheese Girl checks on the Miner, invites him to her cheese cafe, and runs away after saying goodbye. |
| 3 | 1,400 | 1:30 | The player first meets the man with the lantern staff. He cryptically foreshadows the Thief. |
| 4 | 2,500 | 2:40 | Rotini is introduced on the cave path. Existing `rutini_*` resource names refer to Rotini until a coordinated rename is approved. |
| 5 | 4,000 | 4:00 | The Treasure Hunter mines in from the side, introduces himself, and gifts the first improved pickaxe. |
| 6 | 5,600 | 5:30 | The lantern-staff man returns and gives a clearer warning about the Thief. |
| 7 | 7,400 | 7:15 | The Treasure Hunter finds his treasure and gifts the player another pickaxe because he no longer needs it. This is a second, distinct gift. |
| 8 | 9,200 | 9:00 | Quibble is introduced while heading to the cafe for coffee. He gives the player coffee that makes the player faster. Existing `coffee_cat_*` resources refer to Quibble. |
| 9 | 11,200 | 11:00 | The player tells Rotini that the cheese cafe is straight down. Rotini's rat colony joins the player and mines downward with them. |
| 10 | 14,000 | 14:00 | The player reaches the cafe/end gathering. Cheese Girl, the Treasure Hunter, Rotini and the rats, and Quibble are together and happy. The lantern-staff man foreshadows the importance of time management. |
| 11 | 15,000 | 15:00 | Credits begin while the player remains able to dig. Continuing through the credits is intentional. |
| 12 | 15,200 | Post-credits | The lantern-staff man remarks on how long the player has been digging and says only a zillion more swings remain before the Thief. |
| 13 | 100,000 | Long-term objective | The player finally reaches the Thief. The exact reveal and dialogue remain intentionally unspecified here. |

## Implementation Contract

The target depths are the initial authored values, not permission to add time-based
fallbacks. Playtests may tune depths to keep an ordinary run near 15 minutes, but
must preserve the sequence. Any terrain refactor must retain a way to reserve the
next encounter floor, open its tunnel, and capture the player when their mined
depth crosses the tunnel ceiling. The comparison must tolerate one large hit
skipping past the ceiling or floor; no exact impact target is required.

The dialogue revision supplied by Jared on July 25, 2026 is the approved wording
for the opening and encounters 1 through 10. Do not paraphrase its unusual
spelling, capitalization, punctuation, or intentionally unattributed opening
voice without narrative approval. Placeholder language for the Thief must not be
invented into canon without narrative approval.
